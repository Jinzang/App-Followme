#!/usr/bin/env perl
use strict;

use Cwd;
use IO::File;
use File::Path qw(rmtree);
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

use Test::More tests => 6;

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

require App::Followme::EveryFile;

my $test_dir = catdir(@path, 'test');

rmtree($test_dir);
mkdir $test_dir;
chdir $test_dir;
$test_dir = cwd();

#----------------------------------------------------------------------
# Test file visitor

do {
    my $exclude_files = '*.htm,template_*';
    my $excluded_files_ok = ['\.htm$', '^template_'];
    
    my $ef = App::Followme::EveryFile->new();
    is($ef->{base_directory}, $test_dir, 'Set EveryFile base directory');  # test 1

    my $excluded_files = $ef->glob_patterns($exclude_files);
    is_deeply($excluded_files, $excluded_files_ok, 'Glob patterns'); # test 2

    my $dir_ok = $test_dir;
    my $file_ok = 'index.html';
    my $filename = catfile($dir_ok, $file_ok);
    my ($dir, $file) = $ef->split_filename($filename);

    my @dir = splitdir($dir);
    my @dir_ok = splitdir($dir_ok);
    is_deeply(\@dir, \@dir_ok, 'Split directory'); # test 3
    is($file, $file_ok, 'Split filename'); # test 4
};

#----------------------------------------------------------------------
# Create test files and test run method and its submethods

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
<p><a href="">%%</a></p>
<!-- endsection navigation -->
</body>
</html>
EOQ

    my @ok_filenames;
    foreach my $count (qw(first second third)) {
        my $output = $code;
        $output =~ s/%%/Page $count/g;

        my $filename = catfile($test_dir, "$count.html");
        push(@ok_filenames, $filename) ;
        
        my $fd = IO::File->new($filename, 'w');
        print $fd $output;
        close $fd;
    }

    my @ok_folders;
    foreach my $folder (qw(sub-one sub-two)) {
        my $dir = catfile($test_dir, $folder);
        push(@ok_folders, $dir);
        mkdir($dir);
    }
    
    my $ef = App::Followme::EveryFile->new();
    my ($files, $folders) = $ef->visit($test_dir);
   
    is_deeply($folders, \@ok_folders, 'get list of folders'); # test 5
    is_deeply($files, \@ok_filenames, 'get list of files'); # test 6
};

