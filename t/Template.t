#!/usr/bin/env perl
use strict;

use Test::More tests => 37;

use File::Path qw(rmtree);
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

require App::Followme::Template;
require App::Followme::HandleSite;

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

my $data;
my $result = $pp->render(\$data);
is($result, '', "Rendar undef"); # test 3

$data = \'foobar';
$result = $pp->render($data);
is($result, 'foobar', "Rendar scalar"); # test 4

$data = [1, 2];
$result = $pp->render($data);
is($result, "<ul>\n<li>1</li>\n<li>2</li>\n</ul>", "Render array"); # test 5

$data = {a => 1, b => 2};
$result = $pp->render($data);
is($result, "<dl>\n<dt>a</dt>\n<dd>1</dd>\n<dt>b</dt>\n<dd>2</dd>\n</dl>",
   "Render hash"); # test 6

#----------------------------------------------------------------------
# Test type coercion

$data = $pp->coerce('$', 2);
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
@lines = map {"$_\n"} @lines;
my @ok = @lines;

my @block = $pp->parse_block($sections, \@lines, '');
my @sections = sort keys %$sections;

is_deeply(\@block, \@ok, "All lines returned from parse_block"); # test 19
is_deeply(\@sections, [qw(footer header)],
          "All sections returned from parse_block"); #test 20
is_deeply($sections->{footer}, ["Footer\n"],
          "Right value in footer from parse_block"); # test 21

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
@lines = map {"$_\n"} @lines;

my @sublines = split(/\n/, $subtemplate);
@sublines = map {"$_\n"} @sublines;

@ok = @lines;
$ok[1] = "Another Header\n";
$ok[-2] = "Another Footer\n";

$sections = {};
@block = $pp->parse_block($sections, \@sublines, '');
@block = $pp->parse_block($sections, \@lines, '');

is_deeply(\@block, \@ok, "Template and subtemplate with parse_block"); # test 22
is_deeply($sections->{header}, ["Another Header\n"],
          "Right value in header for template & subtemplate"); # test 23

#----------------------------------------------------------------------
# Test read and write page

my $template_name = catfile($test_dir, 'template.htm');
my $subtemplate_name = catfile($test_dir, 'subtemplate.htm');

my $hs = App::Followme::HandleSite->new();
$hs->write_page($template_name, $template);
my $test_template = $hs->read_page($template_name);
is($test_template, $template, 'Read and write template'); # test 24

$hs->write_page($subtemplate_name, $subtemplate);
my $test_subtemplate = $hs->read_page($subtemplate_name);
is($test_subtemplate, $subtemplate, 'Read and write subtemplate'); # test 25

my $sub = $pp->compile($template_name, $subtemplate_name);
is(ref $sub, 'CODE', "compiled template"); # test 26

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

is($text, $text_ok, "Run compiled template"); # test 27

$pp->{keep_sections} = 1;
@lines = split(/\n/, $template);
@sublines = split(/\n/, $subtemplate);

@block = $pp->parse_block($sections, \@sublines, '');
@block = $pp->parse_block($sections, \@lines, '');

is($block[0], "<!-- section header extra -->", "Section start teag"); # test 28
is($block[2], "<!-- endsection header -->", "Section end teag"); # test 29

$sub = $pp->compile($template_name, $subtemplate_name);
is(ref $sub, 'CODE', "compiled template"); # test 30

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

is($text, $text_ok, "Run compiled template"); # test 31

#----------------------------------------------------------------------
# Test for loop

$template = <<'EOQ';
<!-- for @list -->
$name $sep $phone
<!-- endfor -->
EOQ

$hs->write_page($template_name, $template);

$sub = App::Followme::Template->compile($template_name);
$data = {sep => ':', list => [{name => 'Ann', phone => '4444'},
                              {name => 'Joe', phone => '5555'}]};

$text = $sub->($data);

$text_ok = <<'EOQ';
Ann : 4444
Joe : 5555
EOQ

is($text, $text_ok, "For loop"); # test 32

#----------------------------------------------------------------------
# Test with block

$template = <<'EOQ';
$a
<!-- with %hash -->
$a $b
<!-- endwith -->
$b
EOQ

$hs->write_page($template_name, $template);

$sub = App::Followme::Template->compile($template_name);
$data = {a=> 1, b => 2, hash => {a => 10, b => 20}};

$text = $sub->($data);

$text_ok = <<'EOQ';
1
10 20
2
EOQ

is($text, $text_ok, "With block"); # test 33

#----------------------------------------------------------------------
# Test while loop

$template = <<'EOQ';
<!-- while $count -->
$count
<!-- set $count = $count - 1 -->
<!-- endwhile -->
go
EOQ

$hs->write_page($template_name, $template);
$sub = App::Followme::Template->compile($template_name);
$data = {count => 3};

$text = $sub->($data);

$text_ok = <<'EOQ';
3
2
1
go
EOQ

is($text, $text_ok, "While loop"); # test 34

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

$hs->write_page($template_name, $template);
$sub = App::Followme::Template->compile($template_name);

$data = {x => 1};
$text = $sub->($data);
is($text, "\$x is 1 (one)\n", "If block"); # test 35

$data = {x => 2};
$text = $sub->($data);
is($text, "\$x is 2 (two)\n", "Elsif block"); # test 36

$data = {x => 3};
$text = $sub->($data);
is($text, "\$x is unknown\n", "Else block"); # test 37

