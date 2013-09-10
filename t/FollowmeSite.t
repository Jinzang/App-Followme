#!/usr/bin/env perl
use strict;

use IO::File;
use Test::More tests => 3;
use File::Spec::Functions qw(catfile catdir rel2abs splitdir);

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

require App::FollowmeSite;

my $test_dir = catdir(@path, 'test');
system("/bin/rm -rf $test_dir");
mkdir $test_dir;
chdir $test_dir;

#----------------------------------------------------------------------
# Test next_file

do {
    my (@files, @texts);
    while(my ($file, $text) = App::FollowmeSite::next_file()) {
        push(@files, $file);
        push(@texts, $text);
    }
    
    my @files_ok = qw(template.html {{archive_index}}_template.html
                      {{archive_directory}}/index_template.html);

    foreach (@files_ok) {
        my @dirs = split('/', $_);
        $_ = catfile(@dirs);
    }
    
    is_deeply(\@files, \@files_ok, "Next file name"); # test 1
    
    my @long = grep {length($_) > 100} @texts;
    is(@long, 3, "Next file"); # test 2
    
    my $file = shift @files;
    my $text = shift @texts;
    App::FollowmeSite::copy_file($file, $text);
    ok(-e $file, 'Copy file'); #test 3
};