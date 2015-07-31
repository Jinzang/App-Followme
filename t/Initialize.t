#!/usr/bin/env perl
use strict;

use IO::File;
use File::Path qw(rmtree);
use File::Spec::Functions qw(catfile catdir rel2abs splitdir);

use Test::More tests => 8;

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
# Testsupport functions

do {
    my $line = "#>>> copy text common followme.cfg";
    my $is = App::Followme::Initialize::is_command($line);
    is($is, " copy text common followme.cfg", "test is command line"); # test 1

    $line = "run_before = App::Followme::FormatPage";
    $is = App::Followme::Initialize::is_command($line);
    is($is, undef, "test is not command line"); # test 2

    my @dirs = qw(one-fixed two-full three-full one-full);
    eval {App::Followme::Initialize::check_choice(\@dirs, 'two-full')};

    my $error = $@;
    is($error, '', "test is valid choice"); # test 3

    eval {App::Followme::Initialize::check_choice(\@dirs, 'not-full')};
    $error = $@;
    isnt($error, '', "test is not valid choice"); # test 4
};

#----------------------------------------------------------------------
# Test next_file

do {
    my (@commands, @texts, @files, @args);
    my ($read, $unread) = App::Followme::Initialize::data_readers();
    while(my ($command, $lines) = App::Followme::Initialize::next_command($read, $unread)) {
        push(@commands, $command);
        push(@texts, $lines);

        @args = split(' ', $command);
        push(@files, pop @args) if $args[0] eq 'copy';
    }

    my $command = shift @commands;
    my $text = shift @texts;

    @args = split(' ', $command);
    my @args_ok = qw(set dir one-fixed two-full three-full one-full);
    is_deeply(\@args, \@args_ok, "Set command"); # Test 5

    @files = sort(@files);
    @texts = sort(@texts);

    my @files_ok = ('LICENCE', 'apple-touch-icon.png', 'favicon.ico',
                    'followme.cfg', 'index.html', 'index.html','index.html',
                    'index.html', 'styles.css', 'styles.css',
                    'styles.css', 'styles.css', 'templates/gallery.htm',
                    'templates/index.htm', 'templates/news.htm',
                    'templates/news_index.htm', 'templates/page.htm',);

    foreach (@files_ok) {
        my @dirs = split('/', $_);
        $_ = catfile(@dirs);
    }
    @files_ok = sort(@files_ok);

    is_deeply(\@files, \@files_ok, "Next command"); # test 6

    my @has_text = grep {@{$_}} @texts;
    is(@has_text, @texts, "Has lines"); # test 7

    $command = shift @commands;
    @args = split(' ', $command);
    shift @args;

    $text = shift @texts;
    my $file = shift @files;

    App::Followme::Initialize::copy_file('one-full', $text, @args);
    ok(-e $file, 'Copy file'); #test 8
};
