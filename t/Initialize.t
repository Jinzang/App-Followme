#!/usr/bin/env perl
use strict;

use IO::File;
use File::Path qw(rmtree);
use File::Spec::Functions qw(catfile catdir rel2abs splitdir);

use Test::More tests => 3;

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

require App::Followme::Initialize;

my $test_dir = catdir(@path, 'test');

rmtree($test_dir);
mkdir $test_dir;
chdir $test_dir;

#----------------------------------------------------------------------
# Test next_file

do {
    my (@files, @texts);
    my ($read, $unread) = App::Followme::Initialize::data_readers();
    while(my ($file, $text) = App::Followme::Initialize::next_file($read, $unread)) {
        push(@files, $file);
        push(@texts, $text);
    }
    @files =sort(@files);
    @texts = sort(@texts);

    my @files_ok = qw(index.html followme.cfg archive/followme.cfg
                      templates/page.htm templates/news.htm
                      templates/news_index.htm templates/index.htm
                      templates/gallery.htm);

    foreach (@files_ok) {
        my @dirs = split('/', $_);
        $_ = catfile(@dirs);
    }
    @files_ok = sort(@files_ok);

    is_deeply(\@files, \@files_ok, "Next file name"); # test 1

    my @long = grep {length($_) > 50} @texts;
    is(@long, 8, "Next file"); # test 2

    my $file = shift @files;
    my $text = shift @texts;
    App::Followme::Initialize::copy_file($file, $text);
    ok(-e $file, 'Copy file'); #test 3
};
