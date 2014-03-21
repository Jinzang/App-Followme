#!/usr/bin/env perl
use strict;

use Cwd;
use File::Path qw(rmtree);
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

use Test::More tests => 4;

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

require App::Followme::ConfiguredObject;

my $test_dir = catdir(@path, 'test');

rmtree($test_dir);
mkdir $test_dir;
chdir $test_dir;
$test_dir = cwd();

#----------------------------------------------------------------------
# Test object creation

do {
    my $top_dir = $test_dir;
    my $base_dir = catfile($test_dir, 'subdir');
    my $configuration = {
                         quick_update => 1,
                         base_directory => $base_dir,
                         top_directory => $top_dir,
                         extra => 'foobar',
                    };
    
    my $co = App::Followme::ConfiguredObject->new($configuration);

    is($co->{quick_update}, 1, 'Set quick update'); # test 1
    is($co->{base_directory}, $base_dir, 'Set base directory'); # test 2
    is($co->{top_directory}, $top_dir, 'Set top directory'); # test 3
    is($co->{extra}, undef, 'Nothing extra'); # test 4
};
