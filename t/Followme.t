#!/usr/bin/env perl
use strict;

use Cwd;
use IO::File;
use File::Path qw(rmtree);
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

use Test::More tests => 10;

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
    
    my @dir_ok = splitdir($test_dir);
    my @base_directory = splitdir($app->{base_directory});
    my @test_directory = splitdir($app->{top_directory});
    
    is_deeply(\@base_directory, \@dir_ok, 'Set base directory'); # test 1
    is_deeply(\@test_directory, \@dir_ok, 'Set top directory'); # test 2
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

run_after = App::Followme::CreateSitemap

EOQ

    my $filename = 'test.cfg';
    my $fd = IO::File->new($filename, 'w');
    print $fd $source;
    close($fd);
    
    %configuration = $app->update_configuration($filename, %configuration);
    my %configuration_ok = (one => 1, two => 2, three => 3, four => 4,
                            run_before => [],
                            run_after => ['App::Followme::CreateSitemap']);
    
    is_deeply(\%configuration, \%configuration_ok,
              'Update configuration'); # test 3
};

#----------------------------------------------------------------------
# Test run

do {
    my $app = App::Followme->new({});

    chdir($test_dir);
    my $config = 'followme.cfg';
    my @config_files_ok = (catfile($test_dir, $config));
    
    $app->write_page($config, "site_url = http://www.example.com\n");

    my $directory;
    foreach my $dir (qw(one two three)) {
        mkdir($dir);
        chdir ($dir);
        $directory = getcwd();
        
        $config = catfile($directory, 'followme.cfg');
        push(@config_files_ok, $config);

        $app->write_page($config, "run_after = App::Followme::CreateSitemap\n");

        foreach my $file (qw(first.html second.html third.html)) {
            $app->write_page($file, "Fake data\n");
        }
    }

    my $config_files = $app->find_configuration($directory);
    is_deeply($config_files, \@config_files_ok, 'Find configuration'); # test 4
    $app->run($test_dir);

    my $count = 9;
    chdir($test_dir);
    foreach my $dir (qw(one two three)) {
        chdir ($dir);

        my $filename = rel2abs('sitemap.txt');
        ok(-e $filename, 'Ran create sitemap'); # test 5, 7, 9

        my $page = $app->read_page($filename);

        my @lines = split(/\n/, $page);
        is(@lines, $count, 'Right number of urls'); # test 6, 8, 10
        
        $count -= 3;
    }
};
