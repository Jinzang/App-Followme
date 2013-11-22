#!/usr/bin/env perl
use strict;

use IO::File;
use File::Path qw(rmtree);
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

use Test::More tests => 3;

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

require App::Followme::IndexHandler;
require App::Followme::TopDirectory;

my $test_dir = catdir(@path, 'test');

rmtree($test_dir);
mkdir $test_dir;

my $subdir = catdir($test_dir, 'sub');
mkdir $subdir;
chdir $subdir;

App::Followme::TopDirectory->name($test_dir);

#----------------------------------------------------------------------
# Test 

do {
    my $configuration = {
                        exclude_files => '*.htm,template_*'
                        };

    my $idx = App::Followme::IndexHandler->new($configuration);
    my $excluded_files = $idx->{exclude_files};
    my $excluded_files_ok = ['\.htm$', '^template_'];
    
    is_deeply($excluded_files, $excluded_files_ok, 'Set excluded files'); # test 1

    my $dir_ok = $test_dir;
    my $file_ok = 'index.html';
    my $filename = catfile($dir_ok, $file_ok);
    my ($dir, $file) = $idx->split_filename($filename);
    is($dir, $dir_ok, 'Split directory'); # test 2
    is($file, $file_ok, 'Split filename'); # test 3
};