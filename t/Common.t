#!/usr/bin/env perl
use strict;

use IO::File;
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);
use Test::More tests => 40;

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

require App::Followme::Common;

my $test_dir = catdir(@path, 'test');
system("/bin/rm -rf $test_dir");
mkdir $test_dir;
mkdir "$test_dir/sub";
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
    
    my $decorated = 0;
    App::Followme::Common::parse_blocks($page, $decorated, $block_handler,
                                        $template_handler);

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
        App::Followme::Common::parse_blocks($page, $decorated,
                                            $block_handler,
                                            $template_handler);
    };
    is($@, "Unmatched block (<!-- section second -->)\n", 'Missing end'); # test 3

    @bad_page = @page;
    shift(@bad_page); shift(@bad_page);
    $page =join("\n", @bad_page) . "\n";

    eval {
        App::Followme::Common::parse_blocks($page, $decorated,
                                            $block_handler,
                                            $template_handler);
    };
    is($@, "Unmatched (<!-- endsection first -->)\n", 'Missing begin'); # test 4

    @bad_page = @page;
    splice(@bad_page, 3, 1);
    $page =join("\n", @bad_page) . "\n";

    eval {
        App::Followme::Common::parse_blocks($page, $decorated,
                                            $block_handler,
                                            $template_handler);
    };
    is($@, "Improperly nested block (<!-- section second -->)\n",
       'Begin inside of begin'); # test 5

    @bad_page = @page;
    splice(@bad_page, 3, 3);
    $page =join("\n", @bad_page) . "\n";

    eval {
        App::Followme::Common::parse_blocks($page, $decorated,
                                            $block_handler,
                                            $template_handler);
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

    my $decorated = 0;
    my $page = join("\n", @page) . "\n";
    my $blocks = App::Followme::Common::parse_page($page, $decorated);

    my $ok_blocks = {
        first => "\nFirst block\n",
        second => "\nSecond block\n",
    };
    
    is_deeply($blocks, $ok_blocks, 'Parse undecorated blocks'); # test 7

    $decorated = 1;
    $blocks = App::Followme::Common::parse_page($page, $decorated);

    $ok_blocks = {
        first => "<!-- section first -->\nFirst block\n<!-- endsection first -->",
        second => "<!-- section second -->\nSecond block\n<!-- endsection second -->",
    };

    is_deeply($blocks, $ok_blocks, 'Parse decorated blocks'); # test 8

    my $bad_page = $page;
    $bad_page =~ s/second/first/g;
    $blocks = eval {App::Followme::Common::parse_page($bad_page, $decorated)};
    
    is($@, "Duplicate block name (first)\n", 'Duplicate block names'); # test 9
};

#----------------------------------------------------------------------
# Test checksum_prototype and unchanged_prototype

do {
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

    my $decorated = 0;
    my $prototype_path = {folder => 1};
    my $page_one = join("\n", @page) . "\n";
    my $checksum_one = App::Followme::Common::checksum_prototype($page_one,
                                                                 $decorated,
                                                                 $prototype_path);

    my $page_two = $page_one;
    $page_two =~ s/Second/2nd/g;
    my $checksum_two = App::Followme::Common::checksum_prototype($page_two,
                                                                 $decorated,
                                                                 $prototype_path);
    is($checksum_one, $checksum_two, 'Checksum same prototype'); # test 10    

    my $page_three = $page_one;
    $page_three =~ s/First/1st/g;
    my $checksum_three = App::Followme::Common::checksum_prototype($page_three,
                                                                   $decorated,
                                                                   $prototype_path);
    isnt($checksum_one, $checksum_three,
         'Checksum different prototype'); # test 11   

    my $flag = App::Followme::Common::unchanged_prototype($page_one,
                                                          $page_two,
                                                          $decorated,
                                                          $prototype_path);
                                                             
    is($flag, 1, 'Unchanged prototype, similar files'); # test 12

    $flag = App::Followme::Common::unchanged_prototype($page_one,
                                                          $page_three,
                                                          $decorated,
                                                          $prototype_path);
                                                             
    is($flag, 0, 'Unchanged prototype, dissimilar files'); # test 13
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

    my $decorated = 0;
    my $page = $prototype;
    $page =~ s/line/portion/g;
    $page =~ s/block/section/g;
    
    my $prototype_path = {folder => 1};
    my $output = App::Followme::Common::update_page($prototype, $page,
                                                    $decorated,
                                                    $prototype_path);
    my @output = split(/\n/, $output);
    
    my @output_ok = @prototype;
    $output_ok[6] =~ s/block/section/;

    is_deeply(\@output, \@output_ok, 'Update page'); # test 14

    my $bad_page = $page;
    $bad_page =~ s/second/third/g;

    $output = eval{App::Followme::Common::update_page($prototype, $bad_page,
                                                      $decorated, $prototype_path)};
    is($@, "Unused blocks (third)\n", 'Update page bad block'); # test 15
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

    foreach my $dir (('sub', '')) {
        foreach my $count (qw(four three two one)) {
            sleep(1);
            my $output = $code;
            $output =~ s/%%/Page $count/g;
            $output =~ s/&&/$dir link/g;

            my $filename = $dir ? "$dir/$count.html" : "$count.html";
            App::Followme::Common::write_page($filename, $output);

            my $input = App::Followme::Common::read_page($filename);
            is($input, $output, "Read and write page $filename"); #tests 16-24
        }
    }
};

#----------------------------------------------------------------------
# Sort files by depth

do {
    my $level = App::Followme::Common::get_level();
    is($level, 0, 'Level of root directory'); # test 25
    
    $level = App::Followme::Common::get_level('archive/topic/post.html');
    is($level, 3, 'Level of archived post'); # test 26

    my @indexes = qw(a/b/c/four.html a/b/three.html a/two.html one.html);
    my @indexes_ok = reverse @indexes;
    @indexes = App::Followme::Common::sort_by_depth(@indexes);
    is_deeply(\@indexes, \@indexes_ok, 'Sort by depth'); # test 27
    
};

#----------------------------------------------------------------------
# Sort files by name

do {
    my @files = qw (third.html second.html first.html index.html);
    my @files_ok = reverse @files;
    
    @files = App::Followme::Common::sort_by_name(@files);
    is_deeply(\@files, \@files_ok, "Sort by name"); # test 28    
};

#----------------------------------------------------------------------
# Sort files by modification date

do {
    my @filenames = qw(one.html two.html three.html four.html);
    my @filenames_ok = reverse @filenames;
    
    @filenames = App::Followme::Common::sort_by_date(@filenames);
    is_deeply(\@filenames, \@filenames_ok, 'Sort by date'); #test 29
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
    my $sub = App::Followme::Common::compile_template($template);
    my $page = $sub->($data);

    ok($page =~ /<h1>Three<\/h1>/, 'Apply template to title'); # test 30
    ok($page =~ /<p>This is a paragraph<\/p>/,
       'Apply template to body'); # test 31

    my @li = $page =~ /(<li>)/g;
    is(@li, 4, 'Loop over data items'); # test 3
    ok($page =~ /<li>2 two<\/li>/, 'Substitute in loop'); # test 32
};

#----------------------------------------------------------------------
# Test builders

do {
    App::Followme::Common::top_directory($test_dir);
    chdir($test_dir);
    
    my $text_name = catfile('watch','this-is-only-a-test.txt');
    my $page_name = App::Followme::Common::build_page_name($text_name);
    my $page_name_ok = catfile('watch','this-is-only-a-test.html');
    is($page_name, $page_name_ok, 'Build page'); # test 33
    
    my $title = App::Followme::Common::build_title($text_name);
    my $title_ok = 'This Is Only A Test';
    is($title, $title_ok, 'Build file title'); # test 34

    my $index_name = catfile('watch','index.html');
    $title = App::Followme::Common::build_title($index_name);
    $title_ok = 'Watch';
    is($title, $title_ok, 'Build directory title'); # test 35
    
    my $url = App::Followme::Common::build_url($text_name, 'html');
    my $url_ok = '/watch/this-is-only-a-test.html';
    is($url, $url_ok, 'Build file url'); # test 36

    mkdir('watch');
    $url = App::Followme::Common::build_url('watch', 'html');
    is($url, '/watch/index.html', 'Build absolute directory url'); #test 37
       
    $url = App::Followme::Common::build_url('watch', 'html', 'index.html');
    is($url, 'watch/index.html', 'Build relative directory url'); #test 38
       
    my $time = 1;
    my $date = App::Followme::Common::build_date(time());
    my @date_fields = grep {/\S/} sort keys %$date;
    my @date_ok = sort qw(day month monthnum  weekday hour24 hour 
                   minute second year ampm);
    is_deeply(\@date_fields, \@date_ok, 'Build date'); # test 39
    
    my $data = App::Followme::Common::set_variables('two.html', 'html', 0);
    my @keys = sort keys %$data;
    my @keys_ok = sort(@date_ok, 'title', 'url');
    is_deeply(\@keys, \@keys_ok, 'Get data for file'); # test 40
};

