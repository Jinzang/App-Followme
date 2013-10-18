#!/usr/bin/env perl
use strict;

use IO::File;
use Test::More tests => 20;
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

require App::Followme::Update;
require App::Followme::Common;

my $test_dir = catdir(@path, 'test');
system("/bin/rm -rf $test_dir");
mkdir $test_dir;
chdir $test_dir;

#----------------------------------------------------------------------
# Test new and load module

do {
    my $updater = App::Followme::Update->new({});
    is(ref $updater, 'App::Followme::Update', 'Create updater'); # test 1
   
    my $configuration = {module => ['App::Followme::Update']};
    $updater->load_modules($configuration);
    my $module = $configuration->{module}[0];
    is(ref $module, 'App::Followme::Update', 'Load modules'); # test 2
};

#----------------------------------------------------------------------
# Test  get subdirectories

do {
    my @dirs = qw(first second third);
    foreach my $dir (@dirs) {
        mkdir $dir;
    }
    
    my $up = App::Followme::Update->new({});
    my @subdirectories = sort $up->get_subdirectories();
    is_deeply(\@subdirectories, \@dirs, 'Get subdirectories'); # test 3
};

#----------------------------------------------------------------------
# Test update configuration

do {
    my $configuration = {hash => {}, array => [], module => []};
    my $up = App::Followme::Update->new({});

    $up->set_configuration($configuration, 'scalar', 'one');
    is($configuration->{scalar}, 'one', 'set scalar configuration'); # test 4

    $up->set_configuration($configuration, 'array', 1);
    $up->set_configuration($configuration, 'array', 2);
    $up->set_configuration($configuration, 'array', 3);
    is_deeply($configuration->{array}, [1, 2, 3],
              'set array configuration'); # test 5

    $up->set_configuration($configuration, 'hash', 'a');
    $up->set_configuration($configuration, 'hash', 'b');
    $up->set_configuration($configuration, 'hash', 'c');
    is_deeply($configuration->{hash}, {a => 1, b => 1, c => 1},
              'set hash configuration'); # test 6

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
    
    $configuration = $up->update_configuration($filename, $configuration);
    is($configuration->{scalar}, 'two', 'update scalar configuration'); # test 7

    is_deeply($configuration->{array}, [1, 2, 3, 4],
              'set array configuration'); # test 8

    is_deeply($configuration->{hash}, {a => 1, b => 1, c => 1, d => 1},
              'set hash configuration'); # test 9
};

#----------------------------------------------------------------------
# Test initialize configuration

do {
    my @levels;
    my $path = $test_dir;

    foreach my $i (1..5) {
        $path = catfile($path, "level$i");
        my $filename = catfile($path, 'followme.cfg');
        $levels[$i] = "Now we are on level $i";
        
        mkdir($path);
        my $fd = IO::File->new($filename, 'w');
        print $fd "level$i = $levels[$i]\n";
        print $fd "bottom = $levels[$i]\n";
        print $fd "module = App::Followme::Mock";
        close($fd);
    }
    
    my $up = App::Followme::Update->new({});
    my $configuration = $up->initialize_configuration($path);

    my $top_dir = App::Followme::Common::top_directory();
    is($top_dir, "$test_dir/level1", 'Set top directory'); # test 10
    
    is($configuration->{bottom}, $levels[4],
       'Initialize configuration variable'); # test 11

    foreach my $i (1..4) {
        is($configuration->{"level$i"}, $levels[$i],
           "Initialize configuration level $i"); # test 12-15
    }
};

#----------------------------------------------------------------------
# Test update folder

do {
    my $configuration = {module => ['App::Followme::Mock']};
    my $up = App::Followme::Update->new($configuration);
    $up->update_folder("$test_dir/level1", $configuration);

    my $path = $test_dir;
    foreach my $i (1..5) {
        $path = catfile($path, "level$i");
        my $filename = catfile($path, 'mock.txt');
        my $level = "Now we are on level $i";
        
        my %hash;
        my $fd = IO::File->new($filename, 'r');
        while (<$fd>) {
            chomp;
            my($name, $value) = split(/\s*=\s*/, $_, 2);
            $hash{$name} = $value;
        }
        close($fd);
        is($hash{bottom}, $level, "Update folder level$i"); # tests 16-20
    }
};