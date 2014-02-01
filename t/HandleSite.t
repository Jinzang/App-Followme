#!/usr/bin/env perl
use strict;

use Test::More tests => 46;

use File::Path qw(rmtree);
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

require App::Followme::HandleSite;

my $test_dir = catdir(@path, 'test');

rmtree($test_dir);
mkdir $test_dir;

#----------------------------------------------------------------------
# Create object

my $pp = App::Followme::HandleSite->new();
isa_ok($pp, "App::Followme::HandleSite"); # test 1
can_ok($pp, qw(new make_template)); # test 2

#----------------------------------------------------------------------
# Test escaping

my $result = $pp->escape('< & >');
is($result, '&#60; & &#62;', "Escape"); # test 3

#----------------------------------------------------------------------
# Test render

my $data;
$result = $pp->render(\$data);
is($result, '', "Rendar undef"); # test 4

$data = \'<>';
$result = $pp->render($data);
is($result, '&#60;&#62;', "Rendar scalar"); # test 5

$data = [1, 2];
$result = $pp->render($data);
is($result, "<ul>\n<li>1</li>\n<li>2</li>\n</ul>", "Render array"); # test 6

$data = {a => 1, b => 2};
$result = $pp->render($data);
is($result, "<dl>\n<dt>a</dt>\n<dd>1</dd>\n<dt>b</dt>\n<dd>2</dd>\n</dl>",
   "Render hash"); # test 7

#----------------------------------------------------------------------
# Test type coercion

$data = $pp->coerce('$', 2);
is($$data, 2, "Coerce scalar to scalar"); # test 8

$data = $pp->coerce('@', 2);
is_deeply($data, [2], "Coerce scalar to array"); # test 9

$data = $pp->coerce('%', 2);
is($data, undef, "Coerce scalar to hash"); # test 10

$data = $pp->coerce('$');
is($$data, undef, "Coerce undef to scalar"); # test 11

$data = $pp->coerce('@');
is($data, undef, "Coerce undef to array"); # test 12

$data = $pp->coerce('%');
is($data, undef, "Coerce undef to hash"); # test 13

$data = $pp->coerce('$', [1, 3]);
is($$data, 2, "Coerce array to scalar"); # test 14

$data = $pp->coerce('@', [1, 3]);
is_deeply($data, [1, 3], "Coerce array to array"); # test 15

$data = $pp->coerce('%', [1, 3]);
is_deeply($data, {1 => 3}, "Coerce array to hash"); # test 16

$data = $pp->coerce('$', {1 => 3});
is($$data, 2, "Coerce hash to scalar"); # test 17

$data = $pp->coerce('@', {1 => 3});
is_deeply($data, [1, 3], "Coerce hash to array"); # test 18

$data = $pp->coerce('%', {1 => 3});
is_deeply($data, {1 => 3}, "Coerce hash to hash"); # test 19

#----------------------------------------------------------------------
# Test parse_block

my $template = <<'EOQ';
<!-- section header extra -->
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
my @lines = split(/\n/, $template);
my @ok = map {"$_\n"} @lines;

my @block = $pp->parse_block($sections, \@lines, '');
my @sections = sort keys %$sections;

is_deeply(\@block, \@ok, "All lines returned from parse_block"); # test 20
is_deeply(\@sections, [qw(footer header)],
          "All sections returned from parse_block"); #test 21
is_deeply($sections->{footer}, ["Footer\n"],
          "Right value in footer from parse_block"); # test 22

my $subtemplate = <<'EOQ';
<!-- section header -->
Another Header
<!-- endsection -->
Another Body
<!-- section footer -->
Another Footer
<!-- endsection -->
EOQ

@lines = split(/\n/, $template);
my @sublines = split(/\n/, $subtemplate);
@ok = map {"$_\n"} @lines;
$ok[1] = "Another Header\n";
$ok[-2] = "Another Footer\n";

$sections = {};
@block = $pp->parse_block($sections, \@sublines, '');
@block = $pp->parse_block($sections, \@lines, '');

is_deeply(\@block, \@ok, "Template and subtemplate with parse_block"); # test 23
is_deeply($sections->{header}, ["Another Header\n"],
          "Right value in header for template & subtemplate"); # test 24

#----------------------------------------------------------------------
# Test read and write page

my $template_name = catfile($test_dir, 'template.htm');
my $subtemplate_name = catfile($test_dir, 'subtemplate.htm');

$pp->write_page($template_name, $template);
my $test_template = $pp->read_page($template_name);
is($test_template, $template, 'Read and write template'); # test 25

$pp->write_page($subtemplate_name, $subtemplate);
my $test_subtemplate = $pp->read_page($subtemplate_name);
is($test_subtemplate, $subtemplate, 'Read and write subtemplate'); # test 26

my $sub = $pp->compile($template_name, $subtemplate_name);
is(ref $sub, 'CODE', "compiled template"); # test 27

my $text = $sub->([1, 2]);
my $text_ok = <<'EOQ';
<!-- section header extra -->
Another Header
<!-- endsection header -->
Even line
Odd line
<!-- section footer -->
Another Footer
<!-- endsection footer -->
EOQ

is($text, $text_ok, "Run compiled template"); # test 28

$pp->{keep_sections} = 1;
@lines = split(/\n/, $template);
@sublines = split(/\n/, $subtemplate);

@block = $pp->parse_block($sections, \@sublines, '');
@block = $pp->parse_block($sections, \@lines, '');

is($block[0], "<!-- section header extra -->\n", "Section start teag"); # test 29
is($block[2], "<!-- endsection header -->\n", "Section end teag"); # test 30

$sub = $pp->compile($template_name, $subtemplate_name);
is(ref $sub, 'CODE', "compiled template"); # test 31

$text = $sub->([1, 2]);
$text_ok = <<'EOQ';
<!-- section header extra -->
Another Header
<!-- endsection header -->
Even line
Odd line
<!-- section footer -->
Another Footer
<!-- endsection footer -->
EOQ

is($text, $text_ok, "Run compiled template"); # test 32

#----------------------------------------------------------------------
# Test is newer?

do {
   my $code = <<'EOQ';
<html>
<head>
<meta name="robots" content="archive">
<!-- section meta -->
<title>%%</title>
<!-- endsection meta -->
</head>
<body>
<!-- section content -->
<h1>%%</h1>
<!-- endsection content -->
<!-- section navigation in folder -->
<p><a href="">Link</a></p>
<!-- endsection navigation -->
</body>
</html>
EOQ

    chdir($test_dir);
    my $hs = App::Followme::HandleSite->new;
    
    foreach my $count (qw(four three two one)) {
        sleep(1);
        my $output = $code;
        $output =~ s/%%/Page $count/g;

        my $filename = catfile($test_dir, "$count.html");
        $hs->write_page($filename, $output);

        my $input = $hs->read_page($filename);
        is($input, $output, "Read and write page $filename"); #tests 33-36
    }

    my $newer = $hs->is_newer('three.html', 'two.html', 'one.html');
    is($newer, undef, 'Source is  newer'); # test 37
    
    $newer = $hs->is_newer('one.html', 'two.html', 'three.html');
    is($newer, 1, "Target is newer"); # test 38
    
    $newer = $hs->is_newer('five.html', 'one.html');
    is($newer, undef, 'Target is undefined'); # test 39
    
    $newer = $hs->is_newer('six.html', 'five.html');
    is($newer, 1, 'Source and target undefined'); # test 40
};

#----------------------------------------------------------------------
# Test for loop

$template = <<'EOQ';
<!-- for @list -->
$name $sep $phone
<!-- endfor -->
EOQ

$pp->write_page($template_name, $template);

$sub = App::Followme::HandleSite->compile($template_name);
$data = {sep => ':', list => [{name => 'Ann', phone => '4444'},
                              {name => 'Joe', phone => '5555'}]};

$text = $sub->($data);

$text_ok = <<'EOQ';
Ann : 4444
Joe : 5555
EOQ

is($text, $text_ok, "For loop"); # test 41

#----------------------------------------------------------------------
# Test with block

$template = <<'EOQ';
$a
<!-- with %hash -->
$a $b
<!-- endwith -->
$b
EOQ

$pp->write_page($template_name, $template);

$sub = App::Followme::HandleSite->compile($template_name);
$data = {a=> 1, b => 2, hash => {a => 10, b => 20}};

$text = $sub->($data);

$text_ok = <<'EOQ';
1
10 20
2
EOQ

is($text, $text_ok, "With block"); # test 42

#----------------------------------------------------------------------
# Test while loop

$template = <<'EOQ';
<!-- while $count -->
$count
<!-- set $count = $count - 1 -->
<!-- endwhile -->
go
EOQ

$pp->write_page($template_name, $template);
$sub = App::Followme::HandleSite->compile($template_name);
$data = {count => 3};

$text = $sub->($data);

$text_ok = <<'EOQ';
3
2
1
go
EOQ

is($text, $text_ok, "While loop"); # test 43

#----------------------------------------------------------------------
# Test if blocks

$template = <<'EOQ';
<!-- if $x == 1 -->
\$x is $x (one)
<!-- elsif $x  == 2 -->
\$x is $x (two)
<!-- else -->
\$x is unknown
<!-- endif -->
EOQ

$pp->write_page($template_name, $template);
$sub = App::Followme::HandleSite->compile($template_name);

$data = {x => 1};
$text = $sub->($data);
is($text, "\$x is 1 (one)\n", "If block"); # test 44

$data = {x => 2};
$text = $sub->($data);
is($text, "\$x is 2 (two)\n", "Elsif block"); # test 45

$data = {x => 3};
$text = $sub->($data);
is($text, "\$x is unknown\n", "Else block"); # test 46

