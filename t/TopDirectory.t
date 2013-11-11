#!/usr/bin/env perl
use strict;

use IO::File;
use File::Path qw(rmtree);
use File::Spec::Functions qw(catdir rel2abs splitdir);

use Test::More tests => 2;

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

require App::Followme::TopDirectory;

my $test_dir = catdir(@path, 'test');

rmtree($test_dir);
mkdir $test_dir;

#----------------------------------------------------------------------
# Test top directory

do {
    my $dir = App::Followme::TopDirectory->name($test_dir);
    is($dir, $test_dir, 'Set top directory'); # test 1
};

do {
    my $dir = App::Followme::TopDirectory->name;
    is($dir, $test_dir, 'Set top directory'); # test 2
};

