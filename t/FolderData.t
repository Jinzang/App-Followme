#!/usr/bin/env perl
use strict;

use Test::More tests => 26;

use Cwd;
use File::Path qw(rmtree);
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

#----------------------------------------------------------------------
# Change the modification date of a file

sub age {
	my ($filename, $sec) = @_;
	return unless -e $filename;
	return if $sec <= 0;
	
    my @stats = stat($filename);
    my $date = $stats[9];
    $date -= $sec;
    utime($date, $date, $filename);
    
    return; 
}

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

$lib = catdir(@path, 't');
unshift(@INC, $lib);

eval "use App::Followme::FIO";
require App::Followme::FolderData;

my $test_dir = catdir(@path, 'test');
rmtree($test_dir);

mkdir $test_dir or die $!;
chmod 0755, $test_dir;

my $archive = catfile(@path, 'test', 'archive'); 
mkdir $archive or die $!;
chmod 0755, $archive;

chdir($test_dir) or die $!;
$test_dir = cwd();

#----------------------------------------------------------------------
# Create object

my $obj = App::Followme::FolderData->new();
isa_ok($obj, "App::Followme::FolderData"); # test 1
can_ok($obj, qw(new build)); # test 2

#----------------------------------------------------------------------
# Test builders

do {
    my $site_url = 'http://www.example.com';
    my $remote_url = 'http://www.cloud.com';

    my %configuration = (directory => $test_dir,
                         author => 'Bernie Simon',
                         site_url => $site_url,
                         remote_url => $remote_url,
                         );

    my $obj = App::Followme::FolderData->new(%configuration);

    my $filename = catfile('archive','one.txt');

    my $title = $obj->calculate_title($filename);
    my $title_ok = 'One';
    is($title, $title_ok, 'Calculate file title'); # test 3

    my $index_name = catfile('archive','index.html');
    $title = $obj->calculate_title($index_name);
    $title_ok = 'Archive';
    is($title, $title_ok, 'Calculate directory title'); # test 4

    my $keywords = $obj->calculate_keywords($filename);
    my $keywords_ok = 'archive';
    is($keywords, $keywords_ok, 'Calculate file keywords'); # test 5

    my $is_index = $obj->get_is_index($filename);
    is($is_index, 0, 'Regular file in not index'); # test 6

    $is_index = $obj->get_is_index($index_name);
    is($is_index, 1, 'Index file is index'); # test 7

    my $url = $obj->get_url($filename);
    my $url_ok = 'archive/one.html';
    is($url, $url_ok, 'Build a relative file url'); # test 8

    $url = $obj->get_absolute_url($filename);
    $url_ok = $site_url . '/archive/one.html';
    is($url, $url_ok, 'Build an absolute file url'); # test 9

    $url = $obj->get_remote_url($filename);
    $url_ok = $remote_url . '/archive/one.html';
    is($url, $url_ok, 'Build a remote file url'); # test 10

    my $url_base = $obj->get_url_base($filename);
    my $url_base_ok = 'archive/one';
    is($url_base, $url_base_ok, 'Build a file url base'); # test 11

    $url = $obj->get_url($test_dir);
    is($url, 'index.html', 'Build directory url'); #test 12

    my $date = $obj->calculate_date('two.html');
    like($date, qr(^20\d\d-\d\d-\d\dT\d\d:\d\d:\d\d$), 'Calculate date'); # test 13

    $date = $obj->format_date(1, time());
    like($date,  qr(^20\d\d-\d\d-\d\dT\d\d:\d\d:\d\d$), 
        'Format date with default format'); # test 14

    $obj->{date_format} = 'Day, dd Mon yyyy';
    $date = $obj->format_date(0, time());
    like($date, qr(\w\w\w, \d\d \w\w\w \d\d\d\d$),
         'Format date with user supplied format'); # test 15

    my $size = $obj->format_size(0, 2500);
    is($size, '2kb', 'Format size'); # test 16

    $size = $obj->format_size(1, 2500);
    my $ok_size = sprintf("%012d", $size);
    is($size, $ok_size, 'Format size'); # test 17

    my $author = $obj->calculate_author($test_dir);
    is($author, $configuration{author}, "Get author"); # test 18

    my $site_url = $obj->get_site_url($test_dir);
    is($site_url, $configuration{site_url}, "Get site url"); # test 19
};

#----------------------------------------------------------------------
# Test filename variables

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
<!-- endsection content -->
<ul>
<!-- section nav -->
<li><a href="%%.html">%%</a></li>
<!-- endsection nav -->
</ul>
</body>
</html>
EOQ

	my $sec = 100;
    my @ok_files;
    my @ok_all_files;
    my @ok_breadcrumbs;
    foreach my $dir (('', 'archive')) {
        my $index_name = 'index.html';
        $index_name = catfile($dir, $index_name) if $dir;
        push(@ok_breadcrumbs, rel2abs($index_name));

        foreach my $count (sort qw(four three two one index)) {
            my $output = $code;
            $output =~ s/%%/$count/g;

            my @dirs;
            push(@dirs, $test_dir);
            push(@dirs, $dir) if $dir;
            my $filename = catfile(@dirs, "$count.html");

            push(@ok_files, $filename) unless $dir;
            push(@ok_all_files, $filename);
            fio_write_page($filename, $output);
			age($filename, $sec);
			$sec -= 10;
        }
    }

    my $obj = App::Followme::FolderData->new(directory => $test_dir);

    my $size = $obj->get_size('three.html');
    ok($size > 300, 'get file size'); # test 20

    my $index_file = catfile($test_dir,'index.html');
    my $files = $obj->get_files($index_file);
    is_deeply($files, \@ok_files, 'Build files'); # test 21

    my $all_files = $obj->get_all_files($index_file);
    is_deeply($all_files, \@ok_all_files, 'Build all files'); # test 22

    my $filename = catfile('archive', 'two.html');
    my $breadcrumbs = $obj->get_breadcrumbs($filename);
    is_deeply($breadcrumbs, \@ok_breadcrumbs, 'Build breadcrumbs'); # test 23

    $filename = rel2abs('archive');
    my $folders = $obj->get_folders($test_dir);
    is_deeply($folders, [$filename], 'Build folders'); # test 24

    $obj = App::Followme::FolderData->new(directory => $test_dir,
                                               list_length => 2,
                                               sort_field => 'mdate',
                                               );

    my $top_files = $obj->get_top_files($index_file);
    my $top_files_ok = [catfile($test_dir, 'archive','two.html'),
                        catfile($test_dir, 'archive','three.html')];

    is_deeply($top_files, $top_files_ok, 'Build top files');  # test 25

    my $newest_file_ok = [$ok_all_files[-1]];
    my $newest_file = $obj->get_newest_file();
    is_deeply($newest_file, $newest_file_ok, 'Get newest file'); # test 26
};
