#!/usr/bin/env perl
use strict;

use Test::More tests => 38;

use File::Path qw(rmtree);
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

eval "use App::Followme::FIO";
require App::Followme::Template;
require App::Followme::Module;

my $test_dir = catdir(@path, 'test');

rmtree($test_dir);
mkdir $test_dir;

#----------------------------------------------------------------------
# Create object

my $pp = App::Followme::Template->new();
isa_ok($pp, "App::Followme::Template"); # test 1
can_ok($pp, qw(new compile)); # test 2

#----------------------------------------------------------------------
# Test render

do {
    my $data;
    my $result = $pp->render(\$data);
    is($result, '', "Rendar undef"); # test 3

    $data = \'<>';
    $result = $pp->render($data);
    is($result, '<>', "Rendar scalar"); # test 4

    $data = [1, 2];
    $result = $pp->render($data);
    is($result, "<ul>\n<li>1</li>\n<li>2</li>\n</ul>", "Render array"); # test 5

    $data = {a => 1, b => 2};
    $result = $pp->render($data);
    is($result, "<dl>\n<dt>a</dt>\n<dd>1</dd>\n<dt>b</dt>\n<dd>2</dd>\n</dl>",
       "Render hash"); # test 6
};

#----------------------------------------------------------------------
# Test type coercion

do {
    my $data = $pp->coerce('$', 2);
    is($$data, 2, "Coerce scalar to scalar"); # test 7

    $data = $pp->coerce('@', 2);
    is_deeply($data, [2], "Coerce scalar to array"); # test 8

    $data = $pp->coerce('%', 2);
    is($data, undef, "Coerce scalar to hash"); # test 9

    $data = $pp->coerce('$');
    is($$data, undef, "Coerce undef to scalar"); # test 10

    $data = $pp->coerce('@');
    is($data, undef, "Coerce undef to array"); # test 11

    $data = $pp->coerce('%');
    is($data, undef, "Coerce undef to hash"); # test 12

    $data = $pp->coerce('$', [1, 3]);
    is($$data, 2, "Coerce array to scalar"); # test 13

    $data = $pp->coerce('@', [1, 3]);
    is_deeply($data, [1, 3], "Coerce array to array"); # test 14

    $data = $pp->coerce('%', [1, 3]);
    is_deeply($data, {1 => 3}, "Coerce array to hash"); # test 15

    $data = $pp->coerce('$', {1 => 3});
    is($$data, 2, "Coerce hash to scalar"); # test 16

    $data = $pp->coerce('@', {1 => 3});
    is_deeply($data, [1, 3], "Coerce hash to array"); # test 17

    $data = $pp->coerce('%', {1 => 3});
    is_deeply($data, {1 => 3}, "Coerce hash to hash"); # test 18
};

#----------------------------------------------------------------------
# Test substitute_sections

do {
    my $template = <<'EOQ';
<!-- section header -->
Header
<!-- endsection header -->
<!-- set $i = 0 -->
<!-- for @data -->
  <!-- set $i = $i + 1 -->
  <!-- if $i % 2 -->
Even line
  <!-- else -->
Odd line
  <!-- endif -->
<!-- endfor -->
<!-- section footer -->
Footer
<!-- endsection footer -->
EOQ

    my $sections = {};
    $pp->substitute_sections($template, $sections);
    my @sections = sort keys %$sections;

    is_deeply(\@sections, [qw(footer header)],
              "All sections returned from substitute_sections"); #test 19
    is($sections->{footer}, "\nFooter\n",
       "Right value in footer from substitute_sections"); # test 20

    my $subtemplate = <<'EOQ';
<!-- section header -->
Another Header
<!-- endsection header -->
Another Body
<!-- section footer -->
Another Footer
<!-- endsection footer -->
EOQ

    $sections = {};
    my $text = $pp->substitute_sections($subtemplate, $sections);
    $text = $pp->substitute_sections($template, $sections);

    like($text, qr/<!-- section header -->/, "Keep sections start tag"); # test 21
    like($text, qr/<!-- endsection header -->/, "Keep sections start tag"); # test 22

    my $sub = $pp->compile($template, $subtemplate);
    is(ref $sub, 'CODE', "compiled template with keep sections"); # test 23

    $text = $sub->({data => [1, 2]});
    my $text_ok = <<'EOQ';
<!-- section header -->
Another Header
<!-- endsection header -->
Even line
Odd line
<!-- section footer -->
Another Footer
<!-- endsection footer -->
EOQ

    is($text, $text_ok, "Run compiled template with keep sections"); # test 24

    my $template_name = catfile($test_dir, 'template.htm');
    my $subtemplate_name = catfile($test_dir, 'subtemplate.htm');

    my $hs = App::Followme::Module->new();
    fio_write_page($template_name, $template);
    my $test_template = fio_read_page($template_name);
    is($test_template, $template, 'Read and write template'); # test 25

    fio_write_page($subtemplate_name, $subtemplate);
    my $test_subtemplate = fio_read_page($subtemplate_name);
    is($test_subtemplate, $subtemplate, 'Read and write subtemplate'); # test 26

    $sub = $pp->compile($template_name, $subtemplate_name);
    is(ref $sub, 'CODE', "Compiled template"); # test 27

    $text = $sub->({data => [1, 2]});
    $text_ok = <<'EOQ';
<!-- section header -->
Another Header
<!-- endsection header -->
Even line
Odd line
<!-- section footer -->
Another Footer
<!-- endsection footer -->
EOQ

    is($text, $text_ok, "Run compiled template"); # test 28

    $sub = $pp->compile($template_name, $subtemplate_name);
    is(ref $sub, 'CODE', "Compiled template"); # test 29

    $text = $sub->([1, 2]);
    $text_ok = <<'EOQ';
<!-- section header -->
Another Header
<!-- endsection header -->
Even line
Odd line
<!-- section footer -->
Another Footer
<!-- endsection footer -->
EOQ

    is($text, $text_ok, "Run compiled template"); # test 30
};

#----------------------------------------------------------------------
# Test for loop

do {
    my $template = <<'EOQ';
<!-- for @list -->
$name $sep $phone
<!-- endfor -->
EOQ

    my $sub = App::Followme::Template->compile($template);
    my $data = {sep => ':', list => [{name => 'Ann', phone => '4444'},
                                     {name => 'Joe', phone => '5555'}]};

    my $text = $sub->($data);

    my $text_ok = <<'EOQ';
Ann : 4444
Joe : 5555
EOQ

    is($text, $text_ok, "For loop"); # test 31
};

#----------------------------------------------------------------------
# Test each loop

do {
    my $template = <<'EOQ';
<ul>
<!-- each %hash -->
<li><b>$key</b> $value</li>
<!-- endeach -->
</ul>
EOQ

    my $sub = App::Followme::Template->compile($template);
    my $data = {hash => {one => 1, two => 2, three => 3}};

    my $text = $sub->($data);
    like($text, qr(<li><b>two</b> 2</li>), 'Each loop substitution'); # Test 32

    my @match = $text =~ /(<li>)/g;
    is(scalar @match, 3, 'Each loop count'); # Test 33
};

#----------------------------------------------------------------------
# Test with block

do {
    my $template = <<'EOQ';
<!-- section body -->
$a
<!-- with %hash -->
$a $b
<!-- endwith -->
$b
<!-- endsection body -->
EOQ

    my $sub = App::Followme::Template->compile($template);
    my $data = {a=> 1, b => 2, hash => {a => 10, b => 20}};
    my $text = $sub->($data);

    my $text_ok = <<'EOQ';
<!-- section body -->
1
10 20
2
<!-- endsection body -->
EOQ

    is($text, $text_ok, "With block"); # test 34
};

#----------------------------------------------------------------------
# Test while loop

do {
    my $template = <<'EOQ';
<!-- while $count -->
$count
<!-- set $count = $count - 1 -->
<!-- endwhile -->
go
EOQ

    my $sub = App::Followme::Template->compile($template);
    my $data = {count => 3};

    my $text = $sub->($data);

    my $text_ok = <<'EOQ';
3
2
1
go
EOQ

    is($text, $text_ok, "While loop"); # test 35
};

#----------------------------------------------------------------------
# Test if blocks

do {
    my $template = <<'EOQ';
<!-- if $x == 1 -->
\$x is $x (one)
<!-- elsif $x  == 2 -->
\$x is $x (two)
<!-- else -->
\$x is unknown
<!-- endif -->
EOQ

    my $sub = App::Followme::Template->compile($template);

    my $data = {x => 1};
    my $text = $sub->($data);
    is($text, "\$x is 1 (one)\n", "If block"); # test 36

    $data = {x => 2};
    $text = $sub->($data);
    is($text, "\$x is 2 (two)\n", "Elsif block"); # test 37

    $data = {x => 3};
    $text = $sub->($data);
    is($text, "\$x is unknown\n", "Else block"); # test 38
};
