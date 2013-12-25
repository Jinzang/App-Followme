#!/usr/bin/env perl
use strict;

use IO::File;
use File::Path qw(rmtree);
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

use Test::More tests => 35;

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
mkdir catfile($test_dir, 'sub');
chdir $test_dir;

#----------------------------------------------------------------------
# Test parse_blocks

do {
    my $blocks = {};
    my $block_handler = sub {
        my ($blockname, $in, $blocktext) = @_;
        $blocks->{$blockname} = $blocktext;
        return;
    };
    
    my $prototype = [];
    my $template_handler = sub {
        my ($blocktext) = @_;
        push(@$prototype, $blocktext);
        return;
    };
    
    my @page = (
                "Top line",
                "<!-- section first in folder -->",
                "First block",
                "<!-- endsection first -->",
                "Middle line",
                "<!-- section second -->",
                "Second block",
                "<!-- endsection second -->",
                "Last line",
               );

    my $page = join("\n", @page) . "\n";
    
    my $hs = App::Followme::HandleSite->new;
    $hs->parse_blocks($page, $block_handler, $template_handler);

    my $ok_blocks = {
        first => "\nFirst block\n",
        second => "\nSecond block\n",
    };

    my $ok_prototype = [
                        "Top line\n",
                        "<!-- section first in folder -->",
                        "<!-- endsection first -->",
                        "\nMiddle line\n",
                        "<!-- section second -->",
                        "<!-- endsection second -->",
                        "\nLast line\n",
                           ];

    is_deeply($blocks, $ok_blocks, 'Parse blocks'); # test 1
    is_deeply($prototype, $ok_prototype, 'Parse prototype'); # test 2
    
    $blocks = {};
    $prototype = [];
    my @bad_page = @page;
    pop(@bad_page); pop(@bad_page);
    $page =join("\n", @bad_page) . "\n";

    eval {
        $hs->parse_blocks($page, $block_handler, $template_handler);
    };
    is($@, "Unmatched block (<!-- section second -->)\n", 'Missing end'); # test 3

    @bad_page = @page;
    shift(@bad_page); shift(@bad_page);
    $page =join("\n", @bad_page) . "\n";

    eval {
        $hs->parse_blocks($page, $block_handler, $template_handler);
    };
    is($@, "Unmatched (<!-- endsection first -->)\n", 'Missing begin'); # test 4

    @bad_page = @page;
    splice(@bad_page, 3, 1);
    $page =join("\n", @bad_page) . "\n";

    eval {
        $hs->parse_blocks($page, $block_handler, $template_handler);
    };
    is($@, "Improperly nested block (<!-- section second -->)\n",
       'Begin inside of begin'); # test 5

    @bad_page = @page;
    splice(@bad_page, 3, 3);
    $page =join("\n", @bad_page) . "\n";

    eval {
        $hs->parse_blocks($page, $block_handler, $template_handler);
    };
    is($@, "Unmatched (<!-- endsection second -->)\n",
       'Begin does not match end'); # test 6
};

#----------------------------------------------------------------------
# Test parse_page

do {
    my @page = (
                "Top line",
                "<!-- section first -->",
                "First block",
                "<!-- endsection first -->",
                "Middle line",
                "<!-- section second -->",
                "Second block",
                "<!-- endsection second -->",
                "Last line",
               );

    my $page = join("\n", @page) . "\n";
    my $hs = App::Followme::HandleSite->new;
    my $blocks = $hs->parse_page($page);

    my $ok_blocks = {
        first => "\nFirst block\n",
        second => "\nSecond block\n",
    };
    
    is_deeply($blocks, $ok_blocks, 'Parse undecorated blocks'); # test 7

    my $bad_page = $page;
    $bad_page =~ s/second/first/g;
    $blocks = eval {$hs->parse_page($bad_page)};
    
    is($@, "Duplicate block name (first)\n", 'Duplicate block names'); # test 8
};

#----------------------------------------------------------------------
# Test update_page

do {
    my @prototype = (
                "Top line",
                "<!-- section first in folder -->",
                "First block",
                "<!-- endsection first -->",
                "Middle line",
                "<!-- section second -->",
                "Second block",
                "<!-- endsection second -->",
                "Last line",
               );

    my $prototype = join("\n", @prototype) . "\n";

    my $page = $prototype;
    $page =~ s/line/portion/g;
    $page =~ s/block/section/g;
    
    my $prototype_path = {folder => 1};
    my $hs = App::Followme::HandleSite->new;
    my $output = $hs->update_page($prototype, $page, $prototype_path);
    my @output = split(/\n/, $output);
    
    my @output_ok = @prototype;
    $output_ok[6] =~ s/block/section/;

    is_deeply(\@output, \@output_ok, 'Update page'); # test 9
    my $bad_page = $page;
    $bad_page =~ s/second/third/g;

    $output = eval{$hs->update_page($prototype, $bad_page, $prototype_path)};
    is($@, "Unused blocks (third)\n", 'Update page bad block'); # test 10
};

#----------------------------------------------------------------------
# Test read and write page

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
<p><a href="">&&</a></p>
<!-- endsection navigation -->
</body>
</html>
EOQ

    my $hs = App::Followme::HandleSite->new;
    foreach my $dir (('sub', '')) {
        foreach my $count (qw(four three two one)) {
            sleep(1);
            my $output = $code;
            $output =~ s/%%/Page $count/g;
            $output =~ s/&&/$dir link/g;

            my @dirs;
            push(@dirs, $test_dir);
            push(@dirs, $dir) if $dir;

            my $filename = catfile(@dirs, "$count.html");
            $hs->write_page($filename, $output);

            my $input = $hs->read_page($filename);
            is($input, $output, "Read and write page $filename"); #tests 11-18
        }
    }
};

#----------------------------------------------------------------------
# Test file name conversion

do {
    my $hs = App::Followme::HandleSite->new;

    my $filename = 'foobar.txt';
    my $filename_ok = catfile($test_dir, $filename);
    my $test_filename = $hs->full_file_name($test_dir, $filename);
    is($test_filename, $filename_ok, 'Full file name relative path'); # test 19
    
    $filename = $filename_ok;
    $test_filename = $hs->full_file_name($test_dir, $filename);
    is($test_filename, $filename_ok, 'Full file name absolute path'); # test 20
};

#----------------------------------------------------------------------
# Test is newer?

do {
    my $hs = App::Followme::HandleSite->new;

    my $newer = $hs->is_newer('three.html', 'two.html', 'one.html');
    is($newer, undef, 'Source is  newer'); # test 21
    
    $newer = $hs->is_newer('one.html', 'two.html', 'three.html');
    is($newer, 1, "Target is newer"); # test 22
    
    $newer = $hs->is_newer('five.html', 'one.html');
    is($newer, undef, 'Target is undefined'); # test 23
    
    $newer = $hs->is_newer('six.html', 'five.html');
    is($newer, 1, 'Source and target undefined'); # test 24
};

#----------------------------------------------------------------------
# Test converters

do {
   my $text = <<'EOQ';
<p>This is a paragraph</p>

<pre>
This is preformatted text.
</pre>
EOQ

   my $template = <<'EOQ';
<html>
<head>
<meta name="robots" content="archive">
<!-- section meta -->
<title>{{title}}</title>
<!-- endsection meta -->
</head>
<body>
<!-- section content -->
<h1>{{title}}</h1>

{{body}}

<ul>
<!-- loop -->
<li>{{count}} {{item}}</li>
<!-- endloop -->
</ul>
<!-- endsection content -->
</body>
</html>
EOQ

    my @loop;
    my $i = 0;
    foreach my $word (qw(one two three four)) {
        $i = $i + 1;
        push(@loop, {count => $i, item => $word});
    }
    
    my $data = {title =>'Three', body => $text, loop => \@loop};

    my $hs = App::Followme::HandleSite->new;
    my $sub = $hs->compile_template($template);
    my $page = $sub->($data);

    ok($page =~ /<h1>Three<\/h1>/, 'Apply template to title'); # test 25
    ok($page =~ /<p>This is a paragraph<\/p>/,
       'Apply template to body'); # test 26

    my @li = $page =~ /(<li>)/g;
    is(@li, 4, 'Loop over data items'); # test 27
    ok($page =~ /<li>2 two<\/li>/, 'Substitute in loop'); # test 28
};

#----------------------------------------------------------------------
# Test builders

do {
    chdir($test_dir);
    
    my $data = {};
    my $hs = App::Followme::HandleSite->new;
    my $text_name = catfile('watch','this-is-only-a-test.txt');
    
    $data = $hs->build_title_from_filename($data, $text_name);
    my $title_ok = 'This Is Only A Test';
    is($data->{title}, $title_ok, 'Build file title'); # test 29

    my $index_name = catfile('watch','index.html');
    $data = $hs->build_title_from_filename($data, $index_name);
    $title_ok = 'Watch';
    is($data->{title}, $title_ok, 'Build directory title'); # test 30
    
    $data = $hs->build_url($data, $test_dir, $text_name);
    my $url_ok = 'watch/this-is-only-a-test.html';
    is($data->{url}, $url_ok, 'Build a relative file url'); # test 31

    $url_ok = '/' . $url_ok;
    is($data->{absolute_url}, $url_ok, 'Build an absolute file url'); # test 32

    mkdir('watch');
    $data = $hs->build_url($data, $test_dir, 'watch');
    is($data->{url}, 'watch/index.html', 'Build directory url'); #test 33
       
    $data = {};
    my $date = $hs->build_date($data, 'two.html');
    my @date_fields = grep {/\S/} sort keys %$date;
    my @date_ok = sort qw(day month monthnum  weekday hour24 hour 
                   minute second year ampm);
    is_deeply(\@date_fields, \@date_ok, 'Build date'); # test 34
    
    $data = {};
    $data = $hs->external_fields($data, $test_dir, 'two.html');
    my @keys = sort keys %$data;
    my @keys_ok = sort(@date_ok, 'absolute_url', 'title', 'url');
    is_deeply(\@keys, \@keys_ok, 'Get data for file'); # test 35
};
