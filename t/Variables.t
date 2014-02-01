#!/usr/bin/env perl
use strict;

use IO::File;
use File::Path qw(rmtree);
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

use Test::More tests => 11;

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

require App::Followme::Variables;

my $test_dir = catdir(@path, 'test');

rmtree($test_dir);
mkdir $test_dir;
mkdir catfile($test_dir, 'sub');
chdir $test_dir;

#----------------------------------------------------------------------
# Test file name conversion

do {
    my $var = App::Followme::Variables->new;

    my $filename = 'foobar.txt';
    my $filename_ok = catfile($test_dir, $filename);
    my $test_filename = $var->full_file_name($test_dir, $filename);
    is($test_filename, $filename_ok, 'Full file name relative path'); # test 1
    
    $filename = $filename_ok;
    $test_filename = $var->full_file_name($test_dir, $filename);
    is($test_filename, $filename_ok, 'Full file name absolute path'); # test 2
};

#----------------------------------------------------------------------
# Test builders

do {
    chdir($test_dir);
    
    my $data = {};
    my $var = App::Followme::Variables->new;
    my $text_name = catfile('watch','this-is-only-a-test.txt');
    
    $data = $var->build_title_from_filename($data, $text_name);
    my $title_ok = 'This Is Only A Test';
    is($data->{title}, $title_ok, 'Build file title'); # test 3

    my $index_name = catfile('watch','index.html');
    $data = $var->build_title_from_filename($data, $index_name);
    $title_ok = 'Watch';
    is($data->{title}, $title_ok, 'Build directory title'); # test 4
    
    $data = $var->build_url($data, $test_dir, $text_name);
    my $url_ok = 'watch/this-is-only-a-test.html';
    is($data->{url}, $url_ok, 'Build a relative file url'); # test 5

    $url_ok = '/' . $url_ok;
    is($data->{absolute_url}, $url_ok, 'Build an absolute file url'); # test 6

    mkdir('watch');
    $data = $var->build_url($data, $test_dir, 'watch');
    is($data->{url}, 'watch/index.html', 'Build directory url'); #test 7
       
    $data = {};
    my $date = $var->build_date($data, 'two.html');
    my @date_fields = grep {/\S/} sort keys %$date;
    my @date_ok = sort qw(day month monthnum  weekday hour24 hour 
                   minute second year ampm);
    is_deeply(\@date_fields, \@date_ok, 'Build date'); # test 8
    
    $data = {};
    $data = $var->external_fields($data, $test_dir, 'two.html');
    my @keys = sort keys %$data;
    my @keys_ok = sort(@date_ok, 'absolute_url', 'title', 'url');
    is_deeply(\@keys, \@keys_ok, 'Get data for file'); # test 9
    
    my $body = <<'EOQ';
    <h2>The title</h2>
    
    <p>The body
</p>
EOQ

    $data = {body => $body};
    $data = $var->build_title_from_header($data);
    is($data->{title}, 'The title', 'Get title from header'); # test 10
    
    my $summary = $var->build_summary($data);
    is($summary, "The body\n", 'Get summary'); # test 11
};
