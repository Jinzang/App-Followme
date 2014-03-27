#!/usr/bin/env perl
use strict;

use Test::More tests => 36;

use Cwd;
use IO::File;
use File::Path qw(rmtree);
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

require App::Followme::Module;

my $test_dir = catdir(@path, 'test');

rmtree($test_dir);
mkdir $test_dir;
chdir $test_dir;
$test_dir = cwd();

#----------------------------------------------------------------------
# Test same file

do {
    my $mo = App::Followme::Module->new();

    my $same = $mo->same_file('first.txt', 'first.txt');
    is($same, 1, 'Same file'); # test 1
    
    $same = $mo->same_file('first.txt', 'second.txt');
    is($same, undef, 'Not same file'); # test 2
    
};

#----------------------------------------------------------------------
# Test file visitor

do {
    my $exclude_files = '*.htm,template_*';
    my $excluded_files_ok = ['\.htm$', '^template_'];
    
    my $mo = App::Followme::Module->new();
    is($mo->{base_directory}, $test_dir, 'Set Module base directory');  # test 3

    my $excluded_files = $mo->glob_patterns($exclude_files);
    is_deeply($excluded_files, $excluded_files_ok, 'Glob patterns'); # test 4

    my $dir_ok = $test_dir;
    my $file_ok = 'index.html';
    my $filename = catfile($dir_ok, $file_ok);
    my ($dir, $file) = $mo->split_filename($filename);

    my @dir = splitdir($dir);
    my @dir_ok = splitdir($dir_ok);
    is_deeply(\@dir, \@dir_ok, 'Split directory'); # test 5
    is($file, $file_ok, 'Split filename'); # test 6
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

    my @ok_folders;
    my @ok_filenames;
    my $mo = App::Followme::Module->new;
    
    foreach my $dir (('', 'sub-one', 'sub-two')) {
        if ($dir ne '') {
            mkdir $dir;
            push(@ok_folders, catfile($test_dir, $dir));
        }
        
        foreach my $count (qw(first second third)) {
            my $output = $code;
            $output =~ s/%%/Page $count/g;
            $output =~ s/&&/$dir link/g;

            my @dirs;
            push(@dirs, $test_dir);
            push(@dirs, $dir) if $dir;

            my $filename = catfile(@dirs, "$count.html");
            push(@ok_filenames, $filename) if $dir eq '';
        
            $mo->write_page($filename, $output);

            my $input = $mo->read_page($filename);
            is($input, $output, "Read and write page $filename"); #tests 7-15
        }
    }
    
    my ($files, $folders) = $mo->visit($test_dir);
    is_deeply($folders, \@ok_folders, 'get list of folders'); # test 16
    is_deeply($files, \@ok_filenames, 'get list of files'); # test 17
};

#----------------------------------------------------------------------
# Test file name conversion

do {
    my $mo = App::Followme::Module->new;

    my $filename = 'foobar.txt';
    my $filename_ok = catfile($test_dir, $filename);
    my $test_filename = $mo->full_file_name($test_dir, $filename);
    is($test_filename, $filename_ok, 'Full file name relative path'); # test 18
    
    $filename = $filename_ok;
    $test_filename = $mo->full_file_name($test_dir, $filename);
    is($test_filename, $filename_ok, 'Full file name absolute path'); # test 19
};

#----------------------------------------------------------------------
# Test builders

do {
    chdir($test_dir);
    
    my $data = {};
    my $mo = App::Followme::Module->new;
    my $text_name = catfile('watch','this-is-only-a-test.txt');
    
    $data = $mo->build_title_from_filename($data, $text_name);
    my $title_ok = 'This Is Only A Test';
    is($data->{title}, $title_ok, 'Build file title'); # test 20

    my $index_name = catfile('watch','index.html');
    $data = $mo->build_title_from_filename($data, $index_name);
    $title_ok = 'Watch';
    is($data->{title}, $title_ok, 'Build directory title'); # test 21
    
    $data = $mo->build_is_index($data, $text_name);
    is($data->{is_index}, 0, 'Regular file in not index'); # test 22
    
    $data = $mo->build_is_index($data, $index_name);
    is($data->{is_index}, 1, 'Index file is index'); # test 23
    
    $data = $mo->build_url($data, $test_dir, $text_name);
    my $url_ok = 'watch/this-is-only-a-test.html';
    is($data->{url}, $url_ok, 'Build a relative file url'); # test 24

    $url_ok = '/' . $url_ok;
    is($data->{absolute_url}, $url_ok, 'Build an absolute file url'); # test 25

    mkdir('watch');
    $data = $mo->build_url($data, $test_dir, 'watch');
    is($data->{url}, 'watch/index.html', 'Build directory url'); #test 26
       
    $data = {};
    my $date = $mo->build_date($data, 'two.html');
    my @date_fields = grep {/\S/} sort keys %$date;
    my @date_ok = sort qw(day month monthnum  weekday  
                          hour24 hour minute second year ampm);
    is_deeply(\@date_fields, \@date_ok, 'Build date'); # test 27
    
    $data = {};
    $data = $mo->external_fields($data, $test_dir, 'two.html');
    my @keys = sort keys %$data;
    my @keys_ok = sort(@date_ok, 'absolute_url', 'title', 'url', 'is_index');
    is_deeply(\@keys, \@keys_ok, 'Get data for file'); # test 28
    
    my $body = <<'EOQ';
    <h2>The title</h2>
    
    <p>The body
</p>
EOQ

    $data = {body => $body};
    $data = $mo->build_title_from_header($data);
    is($data->{title}, 'The title', 'Get title from header'); # test 29
    
    $data = $mo->build_summary($data);
    is($data->{summary}, "The body\n", 'Get summary'); # test 30
};

#----------------------------------------------------------------------
# Test is newer?

do {
   my $code = <<'EOQ';
<html>
<head>
<meta name="robots" content="archive">
<!-- section meta -->
<title>Page %%</title>
<!-- endsection meta -->
</head>
<body>
<!-- section content -->
<h1>Page %%</h1>

<p><a href="%%.html">Link %%</a></p>
<!-- endsection content -->
</body>
</html>
EOQ

    chdir($test_dir);
    my $mo = App::Followme::Module->new;
    
    my $template = $code;
    $template =~ s/%%/Page \$count/g;

    my $template_name = 'template.htm';
    $mo->write_page(catfile($test_dir, $template_name), $template);

    foreach my $count (qw(four three two one)) {
        sleep(1);
        my $output = $code;
        $output =~ s/%%/Page $count/g;

        my $filename = catfile($test_dir, "$count.html");
        $mo->write_page($filename, $output);
    }

    my $newer = $mo->is_newer('three.html', 'two.html', 'one.html');
    is($newer, undef, 'Source is  newer'); # test 31
    
    $newer = $mo->is_newer('one.html', 'two.html', 'three.html');
    is($newer, 1, "Target is newer"); # test 32
    
    $newer = $mo->is_newer('five.html', 'one.html');
    is($newer, undef, 'Target is undefined'); # test 33
    
    $newer = $mo->is_newer('six.html', 'five.html');
    is($newer, 1, 'Source and target undefined'); # test 34
    
    my $index_name = catfile($test_dir, 'index.html');
    $newer = $mo->index_is_newer($index_name, $template_name, $test_dir);
    is($newer, undef, 'Index is undefined'); # test 35

    sleep(1);
    $mo->write_page($index_name, $template);
    $newer = $mo->index_is_newer($index_name, $template_name, $test_dir);
    is($newer, 1, 'Index is defined'); # test 36
};
