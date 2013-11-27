#!/usr/bin/env perl
use strict;

use Cwd;
use IO::File;
use File::Path qw(rmtree);
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

use Test::More tests => 15;

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

require App::Followme;
require App::Followme::TopDirectory;

my $test_dir = catdir(@path, 'test');

rmtree($test_dir);
mkdir $test_dir;
chdir $test_dir;

#----------------------------------------------------------------------
# Test new and load module

do {
    my $app = App::Followme->new({});
    is(ref $app, 'App::Followme', 'Create Followme'); # test 1
   
    my $configuration = {module => ['App::Followme']};
    $configuration = $app->load_modules($configuration);
    my $module = $configuration->{module}[0];
    
    is(ref $module, 'App::Followme', 'Load modules'); # test 2
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
    my $user = 'Bieber';
    my $fd = IO::File->new('followme.cfg', 'w');
    print $fd "module = App::Followme::Mock\nuser = $user\n";
    close($fd);
    
    foreach my $i (1..5) {
        my $dir = "level$i";
        mkdir $dir;
        chdir($dir);
    }
    
    my $path = getcwd();
    my $app = App::Followme->new();
    my $configuration = $app->initialize_configuration($path);

    my $top_dir = App::Followme::TopDirectory->name;
    is($top_dir, $test_dir, 'Set top directory'); # test 9
    
    is($configuration->{user}, $user,
       'Initialize configuration variable'); # test 10
};

#----------------------------------------------------------------------
# Test update folder

do {
    my $configuration = {module => ['App::Followme::Mock']};
    my $app = App::Followme->new($configuration);
    $app->load_modules($configuration);
    my $mock = $app->{module}[0];
    
    chdir($test_dir);
    $app->update_folder(catfile($test_dir,"level1"), $configuration);

    my $path = $test_dir;
    foreach my $i (1..5) {
        $path = catfile($path, "level$i");
        my $filename = catfile($path, 'mock.txt');

        my $fd = IO::File->new($filename, 'r');
        my $text = <$fd>;
        close $fd;
        
        my $text_ok = "$mock->{user} is here: $path\n";
        is($text, $text_ok, "Update folder level$i"); # tests 11-15
    }
};
