#!/usr/bin/env perl
use strict;

use Cwd;
use IO::File;
use File::Path qw(rmtree);
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

use Test::More tests => 19;

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

require App::Followme;

my $test_dir = catdir(@path, 'test');

rmtree($test_dir);
mkdir $test_dir;
chdir $test_dir;

#----------------------------------------------------------------------
# Test new and load module

do {
    my $app = App::Followme->new({});
    is(ref $app, 'App::Followme', 'Create Followme'); # test 1
   
    my $configuration = {module => ['App::Followme::Mock']};
    $configuration = $app->load_modules($test_dir, $configuration);
    my $module = $configuration->{module}[0];
    
    is(ref $module, 'App::Followme::Mock', 'Load modules'); # test 2
};

#----------------------------------------------------------------------
# Test update configuration

do {
    my $configuration = {hash => {}, array => [], module => []};
    my $app = App::Followme->new({});

    $app->set_configuration($configuration, 'scalar', 'one');
    is($configuration->{scalar}, 'one', 'set scalar configuration'); # test 3

    $app->set_configuration($configuration, 'array', 1);
    $app->set_configuration($configuration, 'array', 2);
    $app->set_configuration($configuration, 'array', 3);
    is_deeply($configuration->{array}, [1, 2, 3],
              'set array configuration'); # test 4

    $app->set_configuration($configuration, 'hash', 'a');
    $app->set_configuration($configuration, 'hash', 'b');
    $app->set_configuration($configuration, 'hash', 'c');
    is_deeply($configuration->{hash}, {a => 1, b => 1, c => 1},
              'set hash configuration'); # test 5

    my $source = <<'EOQ';
# Test configuration file

array = 4
hash = d

scalar = two
EOQ

    my $filename = 'test.cfg';
    my $fd = IO::File->new($filename, 'w');
    print $fd $source;
    close($fd);
    
    $configuration = $app->update_configuration($filename, $configuration);
    is($configuration->{scalar}, 'two', 'update scalar configuration'); # test 6

    is_deeply($configuration->{array}, [1, 2, 3, 4],
              'set array configuration'); # test 7

    is_deeply($configuration->{hash}, {a => 1, b => 1, c => 1, d => 1},
              'set hash configuration'); # test 8
};

#----------------------------------------------------------------------
# Test initialize configuration

do {
    chdir($test_dir);
    my $update = 'yes';
    my $fd = IO::File->new('followme.cfg', 'w');
    print $fd "module = App::Followme::Mock\nquick_update = $update\n";
    close($fd);
    
    my $app = App::Followme->new();
    my $configuration = $app->initialize_configuration($test_dir);
    is($app->{top_directory}, $test_dir, 'Set top directory'); # test 9
    is($app->{base_directory}, $test_dir, 'Set base directory'); # test 10
};

#----------------------------------------------------------------------
# Test run

do {
    my $app = App::Followme->new({});

    chdir($test_dir);
    my $config = 'followme.cfg';
    $app->write_page($config, "subdir = 1\nextension = txt\n");
    
    foreach my $dir (qw(one two three)) {
        mkdir($dir);
        chdir ($dir);
        
        $app->write_page($config, "module = App::Followme::Mock\n");
        foreach my $file (qw(first.txt second.txt third.txt)) {
            $app->write_page($file, "Fake data\n")
        }
    }

    $app->run($test_dir);

    my $count = 9;
    chdir($test_dir);
    foreach my $dir (qw(one two three)) {
        chdir ($dir);

        my $filename = rel2abs('index.dat');
        ok($filename, 'Ran mock'); # test 11, 14, 17

        my $page = $app->read_page($filename);
        is(index($page, "first.txt\nsecond.txt\nthird.txt"), 0,
           'Generated results'); # test 12, 15, 18

        my @lines = split(/\n/, $page);
        is(@lines, $count, 'Right number'); # test 13, 16, 19
        
        $count -= 3;
    }
};
