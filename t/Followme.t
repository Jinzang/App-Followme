#!/usr/bin/env perl
use strict;

use IO::File;
use Test::More tests => 74;
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

require App::Followme;

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
        my ($blockname, $per, $blocktext) = @_;
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
                "<!-- section first per folder -->",
                "First block",
                "<!-- endsection first -->",
                "Middle line",
                "<!-- section second -->",
                "Second block",
                "<!-- endsection second -->",
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
                        "<!-- section first per folder -->",
                        "<!-- endsection first -->",
                        "\nMiddle line\n",
                        "<!-- section second -->",
                        "<!-- endsection second -->",
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
    is($@, "Unmatched block (<!-- section second -->)\n", 'Missing end'); # test 3

    @bad_page = @page;
    shift(@bad_page); shift(@bad_page);
    $page =join("\n", @bad_page) . "\n";

    eval {
        App::Followme::parse_blocks($page, $block_handler, $template_handler);
    };
    is($@, "Unmatched (<!-- endsection first -->)\n", 'Missing begin'); # test 4

    @bad_page = @page;
    splice(@bad_page, 3, 1);
    $page =join("\n", @bad_page) . "\n";

    eval {
        App::Followme::parse_blocks($page, $block_handler, $template_handler);
    };
    is($@, "Improperly nested block (<!-- section second -->)\n",
       'Begin inside of begin'); # test 5

    @bad_page = @page;
    splice(@bad_page, 3, 3);
    $page =join("\n", @bad_page) . "\n";

    eval {
        App::Followme::parse_blocks($page, $block_handler, $template_handler);
    };
    is($@, "Unmatched (<!-- endsection second -->)\n",
       'Begin does not match end'); # test 6
};

#----------------------------------------------------------------------
# Test parse_page

do {
    my @page = (
                "Top line",
                "<!-- section first per folder -->",
                "First block",
                "<!-- endsection first -->",
                "Middle line",
                "<!-- section second -->",
                "Second block",
                "<!-- endsection second -->",
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
                "<!-- section first per folder -->",
                "First block",
                "<!-- endsection first -->",
                "Middle line",
                "<!-- section second -->",
                "Second block",
                "<!-- endsection second -->",
                "Last line",
               );

    my $locality = 0;
    my $page_one = join("\n", @page) . "\n";
    my $checksum_one = App::Followme::checksum_template($page_one, $locality);

    my $page_two = $page_one;
    $page_two =~ s/Second/2nd/g;
    my $checksum_two = App::Followme::checksum_template($page_two, $locality);
    is($checksum_one, $checksum_two, 'Checksum same template'); # test 9    

    my $page_three = $page_one;
    $page_three =~ s/First/1st/g;
    my $checksum_three = App::Followme::checksum_template($page_three, $locality);
    isnt($checksum_one, $checksum_three,
         'Checksum different template'); # test 10   
};

#----------------------------------------------------------------------
# Test update_page

do {
    my @template = (
                "Top line",
                "<!-- section first per folder -->",
                "First block",
                "<!-- endsection first -->",
                "Middle line",
                "<!-- section second -->",
                "Second block",
                "<!-- endsection second -->",
                "Last line",
               );

    my $template = join("\n", @template) . "\n";

    my $page = $template;
    $page =~ s/line/portion/g;
    $page =~ s/block/section/g;
    
    my $locality = 0;
    my $output = App::Followme::update_page($template, $page, $locality);
    my @output = split(/\n/, $output);
    
    my @output_ok = @template;
    $output_ok[6] =~ s/block/section/;

    is_deeply(\@output, \@output_ok, 'Update page'); # test 11

    my $bad_page = $page;
    $bad_page =~ s/second/third/g;

    $output = eval{App::Followme::update_page($template, $bad_page, $locality)};
    is($@, "Unused blocks (third)\n", 'Update page bad block'); # test 12
};

#----------------------------------------------------------------------
# Test read and write pages

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
<!-- section navigation per folder -->
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
            App::Followme::write_page($filename, $output);
    
            my $input = App::Followme::read_page($filename);
            is($input, $output, "Read and write page $filename"); #tests 13-20
        }
    }
};

#----------------------------------------------------------------------
# Test configuration

do {
    my $length = 10;
    App::Followme::configure_followme('archive_index_length', $length);
    my $new_length = App::Followme::configure_followme('archive_index_length');
    
    is($new_length, $length, "Set and get configuration"); # test 21

    eval{App::Followme::configure_followme('meaning_of_everything', 42)};
    is ($@, "Bad configuration field (meaning_of_everything)\n",
        "Bad configuration field"); # test 22
    
};

#----------------------------------------------------------------------
# Get the level of a filename

do {
    my $level = App::Followme::get_level();
    is($level, 0, 'Level of root directory'); # test 23
    
    $level = App::Followme::get_level('archive/topic/post.html');
    is($level, 3, 'Level of archived post'); # test 24
};

#----------------------------------------------------------------------
# Test make relative url

do {
    my $url = App::Followme::make_relative('dorothy.html');
    is($url, 'dorothy.html', 'Make relative, no dir'); # test 25
    
    $url = App::Followme::make_relative('2012/05may/topic.html', '2012/05may');
    is($url, 'topic.html', 'Make relative to dir'); # test 26
    
    $url = App::Followme::make_relative('2012/05may/topic.html', '2012');
    is($url, '05may/topic.html', 'Make relative to partial url'); #test 27
    
    App::Followme::configure_followme('absolute_url', 1);
    $url = App::Followme::make_relative('archive/index.html', 'archive');
    is($url, '/archive/index.html', 'Make absolute url'); # test 28
    
    App::Followme::configure_followme('absolute_url', 0);
};

#----------------------------------------------------------------------
# Test file visitor

do {
    my $visitor = App::Followme::visitor_function('html');
    
    my @filenames;
    while (my $filename = &$visitor) {
        push(@filenames, $filename);
    }
    
    my @ok_filenames = qw(one.html two.html three.html four.html
                          sub/one.html sub/two.html sub/three.html
                          sub/four.html);
    for (@ok_filenames) {
        my @dirs = split('/', $_);
        $_ = catfile(@dirs);
    }
    
    is_deeply(\@filenames, \@ok_filenames, 'File visitor'); # test 29
};

#----------------------------------------------------------------------
# Test more_recent_files and update_site

do {
    my @filenames = App::Followme::more_recent_files(3);
    is_deeply(\@filenames, [qw(one.html two.html three.html)],
              'other most recent files'); # test 30

    my $template = shift(@filenames);
    my $page = App::Followme::read_page($template);
    $page =~ s/archive/noarchive/;
    $page =~ s/Page/Folio/g;
    $page =~ s/link/anchor/g;
    App::Followme::write_page($template, $page);
    App::Followme::update_site();

    foreach my $filename (@filenames) {       
        my $input = App::Followme::read_page($filename);
        ok($input =~ /noarchive/, 'Followme changed template'); # tests 31,34
        ok($input =~ /Page/, "Followme kept contents"); # tests 32,35
        if ($filename =~ /^sub/) {
            ok($input =~ /link/, 'Followme per folder block'); # test 33
        } else {
            ok($input =~ /anchor/, 'Followme per folder block'); # test 36
        }
    }    
};

#----------------------------------------------------------------------
# Test same directory

do {
    my $same = App::Followme::same_directory('one.html', 'blog.html');
    is($same, 1, 'Same directory'); # test 37
    
    $same = App::Followme::same_directory('one.html', 'archive/index.html');
    is($same, undef, 'Not same directory'); # test 38
};

#----------------------------------------------------------------------
# Test builders

do {

    my $text_name = catfile('watch','this-is-only-a-test.txt');
    my $page_name = App::Followme::build_page_name($text_name);
    my $page_name_ok = catfile('watch','this-is-only-a-test.html');
    is($page_name, $page_name_ok, 'Build page'); # test 39
    
    my $title = App::Followme::build_title($text_name);
    my $title_ok = 'This Is Only A Test';
    is($title, $title_ok, 'Build file title'); # test 40

    my $index_name = catfile('watch','index.html');
    $title = App::Followme::build_title($index_name);
    $title_ok = 'Watch';
    is($title, $title_ok, 'Build directory title'); # test 41
    
    my $url = App::Followme::build_url($text_name);
    my $url_ok = 'watch/this-is-only-a-test.html';
    is($url, $url_ok, 'Build file url'); # test 42

    $url = App::Followme::build_url('watch');
    is($url, 'watch/index.html', 'Build directory url'); #test 43
       
    my $time = 1;
    my $date = App::Followme::build_date(time());
    my @date_fields = grep {/\S/} sort keys %$date;
    my @date_ok = sort qw(day month monthnum  weekday hour24 hour 
                   minute second year ampm);
    is_deeply(\@date_fields, \@date_ok, 'Build date'); # test 44
    
    my $data = App::Followme::set_variables('two.html');
    my @keys = sort keys %$data;
    my @keys_ok = sort(@date_ok, 'title');
    is_deeply(\@keys, \@keys_ok, 'Get data for file'); # test 45
};

#----------------------------------------------------------------------
# Test converters

do {
   my $text = <<'EOQ';
Page %%

This is a paragraph

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
<!-- endsection content -->
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
    is($template_file, $template_file_ok, 'Find specific templae'); # test 46

    $template_file = App::Followme::find_template('two.html');
    $template_file_ok ='template.html';
    is($template_file, $template_file_ok, 'Generic templae'); # test 47

    my $page = App::Followme::read_page('three.txt');
    my $tagged_text = App::Followme::add_tags($page);
    my $tagged_text_ok = $text;
    
    $tagged_text_ok =~ s/Page %%/<p>Page three<\/p>/;
    $tagged_text_ok =~s/This is a paragraph/<p>This is a paragraph<\/p>/;
    
    is($tagged_text, $tagged_text_ok, 'Add tags'); # test 48
    
    my $data = {title =>'Three', body => $tagged_text};
    my $sub = App::Followme::compile_template('template.html');
    $page = $sub->($data);

    ok($page =~ /<h1>Three<\/h1>/, 'Apply template to title'); # test 49
    ok($page =~ /<p>This is a paragraph<\/p>/, 'Apply template to body'); # test 50
    
    App::Followme::convert_a_file('four.txt');
    $page = App::Followme::read_page('four.html');
    ok($page =~ /<h1>Four<\/h1>/, 'Convert a file'); # test 51

    App::Followme::convert_text_files();
    $page = App::Followme::read_page('one.html');
    ok($page =~ /<h1>One<\/h1>/, 'Convert text files one'); # test 52
    $page = App::Followme::read_page('two.html');
    ok($page =~ /<h1>Two<\/h1>/, 'Convert text files two'); # test 53
};

#----------------------------------------------------------------------
# Create indexes

do {
    my @indexes = qw(a/b/c/four.html a/b/three.html a/two.html one.html);
    my @indexes_ok = reverse @indexes;
    @indexes = App::Followme::sort_by_depth(@indexes);
    is_deeply(\@indexes, \@indexes_ok, 'Sort by depth'); # test 54
    
    my @converted_files = qw(archive/cars/chevrolet.html archive/cars/edsel.html
                             archive/planes/cessna.html);
                             
    @indexes = App::Followme::get_indexes(\@converted_files);
    @indexes_ok = qw(archive/planes/index.html archive/cars/index.html 
                     archive/index.html);

    foreach (@indexes_ok) {
        my @dirs = split('/', $_);
        $_ = catfile(@dirs);
    }

    is_deeply(\@indexes, \@indexes_ok, 'Get indexes'); # test 55
    
    mkdir('archive');

   my $page = <<'EOQ';
<html>
<head>
<meta name="robots" content="archive">
<!-- section meta -->
<title>Post %%</title>
<!-- endsection meta -->
</head>
<body>
<!-- section content -->
<h1>Post %%</h1>

<p>All about %%.</p>
<!-- endsection content -->
</body>
</html>
EOQ

   my $index_template = <<'EOQ';
<html>
<head>
<meta name="robots" content="noarchive,follow">
<!-- section meta -->
<title>{{title}}</title>
<!-- endsection meta -->
</head>
<body>
<!-- section content -->
<h1>$title</h1>

<ul>
<!-- loop -->
<li><a href="{{url}}">{{title}}</a></li>
<!-- endloop -->
</ul>
<!-- endsection content -->
</body>
</html>
EOQ

   my $archive_template = <<'EOQ';
<html>
<head>
<meta name="robots" content="noarchive,follow">
<!-- section meta -->
<title>{{title}}</title>
<!-- endsection meta -->
</head>
<body>
<!-- section content -->
<h1>{{title}}</h1>

<!-- loop -->
{{body}}
<p>{{month}} {{day}} {{year}}<a href="{{url}}">Permalink</a></p>
<!-- endloop -->
<!-- endsection content -->
</body>
</html>
EOQ

my $body_ok = <<'EOQ';

<h1>Post three</h1>

<p>All about three.</p>
EOQ

    App::Followme::write_page('archive/index_template.html', $index_template);
    App::Followme::write_page('blog_template.html', $archive_template);

    my @archived_files;
    foreach my $count (qw(four three two one)) {
        sleep(2);
        my $output = $page;
        $output =~ s/%%/$count/g;
        
        my $filename = catfile('archive',"$count.html");
        App::Followme::write_page($filename, $output);
        push(@archived_files, $filename);
    }

    my $data = App::Followme::index_data(catfile('archive','index.html'));
    is($data->{title}, 'Archive', 'Index title'); # test 56
    is($data->{url}, 'index.html', 'Index url'); # test 57
    is($data->{loop}[0]{title}, 'Four', 'Index first page title'); # test 58
    is($data->{loop}[3]{title}, 'Two', 'Index last page title'); # test 59
    
    App::Followme::create_an_index('archive/index.html');
    $page = App::Followme::read_page('archive/index.html');
    
    ok($page =~ /<title>Archive<\/title>/, 'Write index title'); # test 60
    ok($page =~ /<li><a href="two.html">Two<\/a><\/li>/,
       'Write index link'); #test 61
    
    $data = App::Followme::recent_archive_data('blog.html', 'archive');
    is($data->{url}, 'blog.html', 'Archive index url'); # test 62
    is($data->{loop}[2]{body}, $body_ok, "Archive index body"); #test 63

    App::Followme::create_archive_index('blog.html');
    $page = App::Followme::read_page('blog.html');
    ok($page =~ /All about two/, 'Archive index content'); # test 64
    ok($page =~ /<a href="archive\/one.html">/, 'Archive index length'); # test 65
    
    unlink('blog.html', catfile('archive','index.html'));
    
    my @index_files = App::Followme::get_indexes(\@archived_files);
    my @all_indexes = App::Followme::all_indexes();
    is_deeply(\@all_indexes, \@index_files, 'All indexes'); # test 66
    
    App::Followme::create_indexes(@index_files);
    ok(-e 'archive/index.html', 'Create archive index'); # test 67
    ok(-e 'blog.html', 'Create blog index'); # test 68
};

#----------------------------------------------------------------------
# Test site initialization

do {
    App::Followme::configure_followme('archive_directory', 'foobar');
    my $file = '{{archive_directory}}/index_template.html';
    $file = App::Followme::rename_template($file);
    my $file_ok = 'foobar/index_template.html';
    is($file, $file_ok, 'Rename index template'); # test 69
    
    App::Followme::configure_followme('archive_index', 'news.html');
    $file = '{{archive_index}}_template.html';
    $file = App::Followme::rename_template($file);
    $file_ok = 'news_template.html';
    is($file, $file_ok, 'Rename blog template'); # test 70
    
    my $text = <<'EOQ';
<html>
<head>
<meta name="robots" content="noarchive,follow">
<!-- section meta -->
<title>{{title}}</title>
<!-- endsection meta -->
</head>
<body>
<!-- section content -->
<h1>{{title}}</h1>

<!-- loop -->
{{body}}
<p>{{month}} {{day}} {{year}}<a href="{{url}}">Permalink</a></p>
<!-- endloop -->
<!-- endsection content -->
</body>
</html>
EOQ

    App::Followme::configure_followme('body_tag', 'article');
    App::Followme::configure_followme('variable', '$(*)');

    $text = App::Followme::modify_template($text);
    ok(index($text, 'section article') > 0, 'Modify begin tag'); # test 71
    ok(index($text, 'endsection article') > 0, 'Modify end tag'); # test 72

    ok(index($text, '$(day)') > 0, 'Modify day variable'); # test 73
    ok(index($text, '$(url)') > 0, 'Modify url tag'); # test 74
    
    App::Followme::configure_followme('archive_directory', 'archive');
    App::Followme::configure_followme('archive_index', 'blog.html');

    App::Followme::configure_followme('body_tag', 'content');
    App::Followme::configure_followme('variable', '{{*}}');
}