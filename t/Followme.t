#!/usr/bin/env perl
use strict;

use Cwd;
use IO::File;
use File::Path qw(rmtree);
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

use Test::More tests => 13;

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
$test_dir = getcwd();

#----------------------------------------------------------------------
# Test set directory

do {
    my $app = App::Followme->new({});

    my $config_file = catfile($test_dir, 'followme.cfg');
    $app->set_directories($config_file);
    
    is($app->{base_directory}, $test_dir, 'Set base directory'); # test 1
    is($app->{top_directory}, $test_dir, 'Set top directory'); # test 2
};

#----------------------------------------------------------------------
# Test update configuration

do {
    my %configuration = (one => 1, two => 2);
    my $app = App::Followme->new({});

    my $source = <<'EOQ';
# Test configuration file

three = 3
four = 4

module = App::Followme::Mock

EOQ

    my $filename = 'test.cfg';
    my $fd = IO::File->new($filename, 'w');
    print $fd $source;
    close($fd);
    
    %configuration = $app->update_configuration($filename, %configuration);
    my %configuration_ok = (one => 1, two => 2, three => 3, four => 4,
                            module => ['App::Followme::Mock']);
    
    is_deeply(\%configuration, \%configuration_ok,
              'Update configuration'); # test 3
};

#----------------------------------------------------------------------
# Test run

do {
    my $app = App::Followme->new({});

    chdir($test_dir);
    my $config = 'followme.cfg';
    my @config_files_ok = (rel2abs($config));
    
    $app->write_page($config, "subdir = 1\nextension = txt\n");
    
    my $directory;
    foreach my $dir (qw(one two three)) {
        mkdir($dir);
        chdir ($dir);
        $directory = getcwd();
        
        $config = catfile($directory, 'followme.cfg');
        push(@config_files_ok, $config);

        $app->write_page($config, "module = App::Followme::Mock\n");

        foreach my $file (qw(first.txt second.txt third.txt)) {
            $app->write_page($file, "Fake data\n")
        }
    }

    pop(@config_files_ok);
    my @config_files = $app->find_configuration($directory);
    is_deeply(\@config_files, \@config_files_ok, 'Find configuration'); # test 4
    $app->run($test_dir);

    my $count = 9;
    chdir($test_dir);
    foreach my $dir (qw(one two three)) {
        chdir ($dir);

        my $filename = rel2abs('index.dat');
        ok($filename, 'Ran mock'); # test 5, 8, 11

        my $page = $app->read_page($filename);
        is(index($page, "first.txt\nsecond.txt\nthird.txt"), 0,
           'Generated results'); # test 6, 9, 12

        my @lines = split(/\n/, $page);
        is(@lines, $count, 'Right number'); # test 7, 10, 13
        
        $count -= 3;
    }
};
