#!/usr/bin/env perl
use strict;

use IO::File;
use Test::More tests => 34;

#----------------------------------------------------------------------
# Load package

my @path = split(/\//, $0);
pop(@path);

my $bin = join('/', @path);
my $lib = "$bin/../lib";
unshift(@INC, $lib);

require App::Followme;

my $test_dir = "$bin/../test";
system("/bin/rm -rf $test_dir");
mkdir $test_dir;
chdir $test_dir;

#----------------------------------------------------------------------
# Test parse_blocks

do {
    my $blocks = {};
    my $block_handler = sub {
        my ($blockname, $blocktext) = @_;
        $blocks->{$blockname} = $blocktext;
        return;
    };
    
    my $template = [];
    my $template_handler = sub {
        my ($blocktext) = @_;
        push(@$template, $blocktext);
        return;
    };
    
    my @page = (
                "Top line",
                "<!-- begin first -->",
                "First block",
                "<!-- end first -->",
                "Middle line",
                "<!-- begin second -->",
                "Second block",
                "<!-- end second -->",
                "Last line",
               );

    my $page = join("\n", @page) . "\n";
    
    App::Followme::parse_blocks($page, $block_handler, $template_handler);

    my $ok_blocks = {
        first => "\nFirst block\n",
        second => "\nSecond block\n",
    };

    my $ok_template = [
                        "Top line\n",
                        "<!-- begin first -->",
                        "<!-- end first -->",
                        "\nMiddle line\n",
                        "<!-- begin second -->",
                        "<!-- end second -->",
                        "\nLast line\n",
                           ];

    is_deeply($blocks, $ok_blocks, 'Parse blocks'); # test 1
    is_deeply($template, $ok_template, 'Parse template'); # test 2
    
    $blocks = {};
    $template = [];
    my @bad_page = @page;
    pop(@bad_page); pop(@bad_page);
    $page =join("\n", @bad_page) . "\n";

    eval {
        App::Followme::parse_blocks($page, $block_handler, $template_handler);
    };
    is($@, "Unmatched block (<!-- begin second -->)\n", 'Missing end'); # test 3

    @bad_page = @page;
    shift(@bad_page); shift(@bad_page);
    $page =join("\n", @bad_page) . "\n";

    eval {
        App::Followme::parse_blocks($page, $block_handler, $template_handler);
    };
    is($@, "Unmatched (<!-- end first -->)\n", 'Missing begin'); # test 4

    @bad_page = @page;
    splice(@bad_page, 3, 1);
    $page =join("\n", @bad_page) . "\n";

    eval {
        App::Followme::parse_blocks($page, $block_handler, $template_handler);
    };
    is($@, "Improperly nested block (<!-- begin second -->)\n",
       'Begin inside of begin'); # test 5

    @bad_page = @page;
    splice(@bad_page, 3, 3);
    $page =join("\n", @bad_page) . "\n";

    eval {
        App::Followme::parse_blocks($page, $block_handler, $template_handler);
    };
    is($@, "Unmatched (<!-- end second -->)\n",
       'Begin does not match end'); # test 6
};

#----------------------------------------------------------------------
# Test parse_page

do {
    my @page = (
                "Top line",
                "<!-- begin first -->",
                "First block",
                "<!-- end first -->",
                "Middle line",
                "<!-- begin second -->",
                "Second block",
                "<!-- end second -->",
                "Last line",
               );

    my $page = join("\n", @page) . "\n";
    my $blocks = App::Followme::parse_page($page);

    my $ok_blocks = {
        first => "\nFirst block\n",
        second => "\nSecond block\n",
    };

    is_deeply($blocks, $ok_blocks, 'Parse blocks'); # test 7

    my $bad_page = $page;
    $bad_page =~ s/second/first/g;
    $blocks = eval {App::Followme::parse_page($bad_page)};
    
    is($@, "Duplicate block name (first)\n", 'Duplicate block names'); # test 8
};

#----------------------------------------------------------------------
# Test checksum_template

do {
    my @page = (
                "Top line",
                "<!-- begin first -->",
                "First block",
                "<!-- end first -->",
                "Middle line",
                "<!-- begin second -->",
                "Second block",
                "<!-- end second -->",
                "Last line",
               );

    my $page_one = join("\n", @page) . "\n";
    my $checksum_one = App::Followme::checksum_template($page_one);

    my $page_two = $page_one;
    $page_two =~ s/block/mock/g;
    my $checksum_two = App::Followme::checksum_template($page_two);
    is($checksum_one, $checksum_two, 'Checksum same template'); # test 9    

    my $page_three = $page_one;
    $page_three =~ s/line/part/g;
    my $checksum_three = App::Followme::checksum_template($page_three);
    isnt($checksum_one, $checksum_three,
         'Checksum different template'); # test 10   
};

#----------------------------------------------------------------------
# Test update_page

do {
    my @template = (
                "Top line",
                "<!-- begin first -->",
                "First block",
                "<!-- end first -->",
                "Middle line",
                "<!-- begin second -->",
                "Second block",
                "<!-- end second -->",
                "Last line",
               );

    my $template = join("\n", @template) . "\n";

    my $page = $template;
    $page =~ s/line/portion/g;
    $page =~ s/block/section/g;
    
    my $output = App::Followme::update_page($template, $page);
    my @output = split(/\n/, $output);
    
    my @output_ok = @template;
    $output_ok[2] =~ s/block/section/;
    $output_ok[6] =~ s/block/section/;

    is_deeply(\@output, \@output_ok, 'Update page'); # test 11

    my $bad_page = $page;
    $bad_page =~ s/second/third/g;

    $output = eval{App::Followme::update_page($template, $bad_page)};
    is($@, "Unused blocks (third)\n", 'Update page bad block'); # test 12
};

#----------------------------------------------------------------------
# Test read, write and sort pages

do {
   my $code = <<'EOQ';
<html>
<head>
<meta name="robots" content="archive">
<!-- begin meta -->
<title>%%</title>
<!-- end meta -->
</head>
<body>
<!-- begin content -->
<h1>%%</h1>
<!-- end content -->
</body>
</html>
EOQ

    foreach my $count (qw(four three two one)) {
        sleep(1);
        my $output = $code;
        $output =~ s/%%/Page $count/g;
        
        my $filename = "$count.html";
        App::Followme::write_page($filename, $output);

        my $input = App::Followme::read_page($filename);
        is($input, $output, "Read and write page $count"); #tests 13-16
    }
};

#----------------------------------------------------------------------
# Test configuration

do {
    my $set_file = 'test.md5';
    App::Followme::configure_followme('checksum_file', $set_file);
    my $get_file = App::Followme::configure_followme('checksum_file');
    
    is($get_file, $set_file, "Set and get configuration"); # test 17

    eval{App::Followme::configure_followme('meaning_of_everything', 42)};
    is ($@, "Bad configuration field (meaning_of_everything)\n",
        "Bad configuration field"); # test 18
    
};

#----------------------------------------------------------------------
# Test visitors

do {
    my ($dir_visitor, $file_visitor) = App::Followme::visitors('html');
    
    my $dir = $dir_visitor->();
    is($dir, '.', 'Dirrctory visitor'); # test 19
    
    $dir = $dir_visitor->();
    is($dir, undef, 'Dirrctory visitor done'); # test 20
    
    my @filenames;
    while (my $filename = $file_visitor->()) {
        push(@filenames, $filename);
    }
    
    is_deeply(\@filenames,
              [qw(one.html two.html three.html four.html)],
              'File visitor'); # test 21
};

#----------------------------------------------------------------------
# Test most_recent_files and update_site

do {
    my ($visit_dirs, $visit_files, $most_recent_files) =
        App::Followme::visitors('html');
        
    my @filenames = $most_recent_files->(3);
    my $template = shift(@filenames);

    is($template, 'one.html', 'Most recent file'); # test 22
    is_deeply(\@filenames, [qw(two.html three.html)],
              'other most recent files'); # test 23
    
    my $page = App::Followme::read_page($template);

    $page =~ s/archive/noarchive/;
    $page =~ s/Page/Folio/g;
    App::Followme::write_page($template, $page);
    App::Followme::update_site('.');
    
    foreach my $filename (@filenames) {       
        my $input = App::Followme::read_page($filename);
        ok($input =~ /noarchive/, 'Followme changed template'); # tests 24,25
        ok($input =~ /Page/, "Followme kept contents"); # tests 26,27
    }
};

#----------------------------------------------------------------------
# Test builders

do {

    my $text_name = 'watch/this-is-only-a-test.txt';
    my $page_name = App::Followme::build_page_name($text_name);
    my $page_name_ok = 'watch/this-is-only-a-test.html';
    is($page_name, $page_name_ok, 'Build page'); # test 28
    
    my $title = App::Followme::build_title($text_name);
    my $title_ok = 'This Is Only A Test';
    is($title, $title_ok, 'Build file title'); # test 29

    my $index_name = 'watch/index.html';
    $title = App::Followme::build_title($index_name);
    $title_ok = 'Watch';
    is($title, $title_ok, 'Build directory title'); # test 30
    
    my $url = App::Followme::build_url($text_name);
    my $url_ok = 'watch/this-is-only-a-test.html';
    is($url, $url_ok, 'Build file url'); # test 31

    $url = App::Followme::build_url('watch');
    is($url, 'watch/index.html', 'Build directory url'); #test 32
       
    my $time = 1374019907;
    my $data = App::Followme::build_date($time);
    my $data_ok = {day => 16, month => 'Jul', monthnum => '07', 
                   weekday => 'Tue', hour24 => 20, hour => '08',
                   minute => 11, second => 47, year => 2013,
                   ampm => 'pm'};
    is_deeply($data, $data_ok, 'Build date'); # test 33
    
    $data = App::Followme::get_data_for_file('two.html');
    my @keys = sort keys %$data;
    my @keys_ok = sort(keys(%$data_ok), 'title', 'url');
    is_deeply(\@keys, \@keys_ok, 'Get data for file'); # test 34
};

#----------------------------------------------------------------------
# Test converters

do {
   my $text = <<'EOQ';
Page %%

This is a paragraph.
EOQ

   my $template = <<'EOQ';
<html>
<head>
<meta name="robots" content="archive">
<!-- begin meta -->
<title>$title</title>
<!-- end meta -->
</head>
<body>
<!-- begin content -->
<h1>$title</h1>

$body
<!-- end content -->
</body>
</html>
EOQ

    foreach my $count (qw(four three two one)) {
        my $output = $text;
        $output =~ s/%%/$count/g;
        
        my $filename = "$count.txt";
        App::Followme::write_page($filename, $output);
    }

    foreach my $root (qw(template one_template)) {
        my $filename = "$root.html";
        App::Followme::write_page($filename, $template);
    }

    my $template_file = App::Followme::find_template('one.html');
    my $template_file_ok ='one_template.html';
    is($template_file, $template_file_ok, 'Find specific templae'); # test 35

    $template_file = App::Followme::find_template('two.html');
    $template_file_ok ='template.html';
    is($template_file, $template_file_ok, 'Generic templae'); # test 36

};
