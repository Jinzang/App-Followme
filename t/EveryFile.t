#!/usr/bin/env perl
use strict;

use Cwd;
use IO::File;
use File::Path qw(rmtree);
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

use Test::More tests => 17;

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
# Test same file

do {
    my $ef = App::Followme::EveryFile->new();

    my $same = $ef->same_file('first.txt', 'first.txt');
    is($same, 1, 'Same file'); # test 1
    
    $same = $ef->same_file('first.txt', 'second.txt');
    is($same, undef, 'Not same file'); # test 2
    
};

#----------------------------------------------------------------------
# Test file visitor

do {
    my $exclude_files = '*.htm,template_*';
    my $excluded_files_ok = ['\.htm$', '^template_'];
    
    my $ef = App::Followme::EveryFile->new();
    is($ef->{base_directory}, $test_dir, 'Set EveryFile base directory');  # test 3

    my $excluded_files = $ef->glob_patterns($exclude_files);
    is_deeply($excluded_files, $excluded_files_ok, 'Glob patterns'); # test 4

    my $dir_ok = $test_dir;
    my $file_ok = 'index.html';
    my $filename = catfile($dir_ok, $file_ok);
    my ($dir, $file) = $ef->split_filename($filename);

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
    my $ef = App::Followme::EveryFile->new;
    
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
        
            $ef->write_page($filename, $output);

            my $input = $ef->read_page($filename);
            is($input, $output, "Read and write page $filename"); #tests 7-15
        }
    }
    
    my ($files, $folders) = $ef->visit($test_dir);
    is_deeply($folders, \@ok_folders, 'get list of folders'); # test 16
    is_deeply($files, \@ok_filenames, 'get list of files'); # test 17
};

