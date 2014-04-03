#!/usr/bin/env perl
use strict;

use Cwd;
use IO::File;
use File::Path qw(rmtree);
use File::Spec::Functions qw(catfile catdir rel2abs splitdir);

use Test::More tests => 15;

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

require App::Followme;
require App::Followme::Initialize;

my $test_dir = catdir(@path, 'test');

rmtree($test_dir);
mkdir $test_dir;
chdir $test_dir;
$test_dir = cwd();

#----------------------------------------------------------------------
# Initialize web site

do {
    App::Followme::Initialize::initialize($test_dir);
    ok(-e 'templates', 'Created templates directory'); # test 1
    ok(-e 'archive', 'Created archive directory'); # test 2
    ok(-e 'followme.cfg', 'Created configuration file'); # test 3
};

#----------------------------------------------------------------------
# Create index page

do {
    chdir($test_dir);
    my $followme = App::Followme->new();

    my $text = "This is the top page\n";
    $followme->write_page('index.md', $text);
    $followme->run($test_dir);
    
    ok(-e 'index.html', 'Index file created'); #test 4
    ok(! -e 'index.md', 'Text file deleted'); #test 5
    
    chomp($text);
    my $page = $followme->read_page('index.html');
    ok(index($page, '<h2>Test</h2>') > 0, 'Generated title'); # test 6
    ok(index($page, "<p>$text</p>") > 0, 'Generated body'); # test 7

};

#----------------------------------------------------------------------
# Create archive pages

do {
    chdir($test_dir);
    my $followme = App::Followme->new();

    my $path = catfile($test_dir, 'archive');
    foreach my $dir (qw(2013 12december)) {
        $path = catfile($path, $dir);
        mkdir($path);
    }

    foreach my $count (qw(first second third)) {
        my $file = "$count.md";
        $file = catfile($path, $file);
        
        my $text = "$count blog post.\n";
        $followme->write_page($file, $text);
        
        $followme->run($path);
        $file =~ s/md$/html/;
        sleep(1);
        
        chomp($text);
        my $page = $followme->read_page($file);
        ok(index($page, "<p>$text</p>") > 0,
           "Generated $count blog post"); # test 8-10
    }
    
    $path = catfile($test_dir, 'archive');
    my $file = catfile($path, 'index.html'); # test 11
    ok(-e $file, "archive index file created");

    foreach my $dir (qw(2013 12december)) {
        my $page = $followme->read_page($file);
        ok(index($page, "$dir/index.html") > 0,
           "Link to $dir directory"); # test 12,14
        
        $path = catfile($path, $dir);
        $file = catfile($path, 'index.html');
        ok(-e $file, "$dir index file created"); # test 13,15
    }    
};
