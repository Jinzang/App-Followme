#!/usr/bin/env perl
use strict;

use Test::More tests => 27;

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

eval "use App::Followme::FIO";
eval "use App::Followme::Web";

my $test_dir = catdir(@path, 'test');

rmtree($test_dir);
mkdir $test_dir;
chdir $test_dir;
$test_dir = cwd();

#----------------------------------------------------------------------
# Test same file

do {
    my $same = fio_same_file('first.txt', 'first.txt');
    is($same, 1, 'Same file'); # test 1

    $same = fio_same_file('first.txt', 'second.txt');
    is($same, undef, 'Not same file'); # test 2

};

#----------------------------------------------------------------------
# Test glob_patterns

do {
    my $exclude_files = '*.htm,template_*';
    my $excluded_files_ok = ['\.htm$', '^template_'];

    my $excluded_files = fio_glob_patterns($exclude_files);
    is_deeply($excluded_files, $excluded_files_ok, 'Glob patterns'); # test 3
};

#----------------------------------------------------------------------
# Test split_filename

do {
    my $dir_ok = $test_dir;
    my $file_ok = 'index.html';
    my $filename = catfile($dir_ok, $file_ok);
    my ($dir, $file) = fio_split_filename($filename);

    my @dir = splitdir($dir);
    my @dir_ok = splitdir($dir_ok);
    is_deeply(\@dir, \@dir_ok, 'Split directory'); # test 4
    is($file, $file_ok, 'Split filename'); # test 5
};

#----------------------------------------------------------------------
# Test set and get date

do {
    my $ok_date = 12345;
    fio_set_date($test_dir, $ok_date);
    my $date = fio_get_date($test_dir);
    is($date, $ok_date, "set and get date"); # test 6

    fio_set_date($test_dir, $date);
    $date = fio_get_date($test_dir);
    is($date, $ok_date, "set and get date"); # test 7

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

            fio_write_page($filename, $output);

            my $input = fio_read_page($filename);
            is($input, $output, "Read and write page $filename"); #tests 8-16
        }
    }

    my ($files, $folders) = fio_visit($test_dir);
    is_deeply($folders, \@ok_folders, 'get list of folders'); # test 17
    is_deeply($files, \@ok_filenames, 'get list of files'); # test 18
};

#----------------------------------------------------------------------
# Test file name conversion

do {
    my $filename = 'foobar.txt';
    my $filename_ok = catfile($test_dir, $filename);
    my $test_filename = fio_full_file_name($test_dir, $filename);
    is($test_filename, $filename_ok, 'Full file name relative path'); # test 19

    $filename = $filename_ok;
    $test_filename = fio_full_file_name($test_dir, $filename);
    is($test_filename, $filename_ok, 'Full file name absolute path'); # test 20
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

    my $template = $code;
    $template =~ s/%%/Page \$count/g;

    my $template_name = 'template.htm';
    fio_write_page(catfile($test_dir, $template_name), $template);

    foreach my $count (qw(four three two one)) {
        sleep(1);
        my $output = $code;
        $output =~ s/%%/Page $count/g;

        my $filename = catfile($test_dir, "$count.html");
        fio_write_page($filename, $output);
    }

    my $newer = fio_is_newer('three.html', 'two.html', 'one.html');
    is($newer, undef, 'Source is  newer'); # test 21

    $newer = fio_is_newer('one.html', 'two.html', 'three.html');
    is($newer, 1, "Target is newer"); # test 22

    $newer = fio_is_newer('five.html', 'one.html');
    is($newer, undef, 'Target is undefined'); # test 23

    $newer = fio_is_newer('six.html', 'five.html');
    is($newer, 1, 'Source and target undefined'); # test 24
};

#----------------------------------------------------------------------
# Test filename  to url

do {
    my $url_ok = 'index.html';
    my $filename = catfile($test_dir, $url_ok);
    my $url = fio_filename_to_url($test_dir, $filename);
    is($url, $url_ok, 'Simple url'); # test 25

    $filename = catfile($test_dir, 'index.md');
    $url = fio_filename_to_url($test_dir, $filename, 'html');
    is($url, $url_ok, 'Url from filename'); # test 26

    $url_ok = 'subdir/foobar.html';
    my @path = split(/\//, $url_ok);
    $filename = catfile($test_dir, @path);
    $url = fio_filename_to_url($test_dir, $filename, 'html');
    is($url, $url_ok, 'Url in subdirectory'); # test 27

};
