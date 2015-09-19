#!/usr/bin/env perl
use strict;

use Test::More tests => 12;

use Cwd;
use IO::File;
use File::Path qw(rmtree);
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

eval "use App::Followme::FIO";
require App::Followme::Module;

my $test_dir = catdir(@path, 'test');

rmtree($test_dir);
mkdir $test_dir;
chdir $test_dir;
$test_dir = cwd();

#----------------------------------------------------------------------
# Test builders

do {
    chdir($test_dir);
    mkdir('watch');

    my $data = {};
    my $mo = App::Followme::Module->new;
    my $text_name = catfile('watch','this-is-only-a-test.txt');

    $data = $mo->build_title_from_filename($data, $text_name);
    my $title_ok = 'This Is Only A Test';
    is($data->{title}, $title_ok, 'Build file title'); # test 1

    my $index_name = catfile('watch','index.html');
    $data = $mo->build_title_from_filename($data, $index_name);
    $title_ok = 'Watch';
    is($data->{title}, $title_ok, 'Build directory title'); # test 2

    $data = $mo->build_is_index($data, $text_name);
    is($data->{is_index}, 0, 'Regular file in not index'); # test 3

    $data = $mo->build_is_index($data, $index_name);
    is($data->{is_index}, 1, 'Index file is index'); # test 4

    $data = $mo->build_url($data, $test_dir, $text_name);
    my $url_ok = 'watch/this-is-only-a-test.html';
    is($data->{url}, $url_ok, 'Build a relative file url'); # test 5

    $url_ok = '/' . $url_ok;
    is($data->{absolute_url}, $url_ok, 'Build an absolute file url'); # test 6

    my $breadcrumbs_ok = [{title => 'Test', url => '/index.html'},
                          {title => 'Watch', url => '/watch/index.html'}];

    is_deeply($data->{breadcrumbs}, $breadcrumbs_ok,
              'Build breadcrumbs'); # test 7

    $data = $mo->build_url($data, $test_dir, 'watch');
    is($data->{url}, 'watch/index.html', 'Build directory url'); #test 8

    $data = {};
    my $date = $mo->build_date($data, 'two.html');
    my @date_fields = grep {/\S/} sort keys %$date;
    my @date_ok = sort qw(day month monthnum  weekday
                          hour24 hour minute second year ampm);
    is_deeply(\@date_fields, \@date_ok, 'Build date'); # test 9

    $data = {};
    $data = $mo->external_fields($data, $test_dir, 'two.html');
    my @keys = sort keys %$data;
    my @keys_ok = sort(@date_ok, 'absolute_url', 'breadcrumbs',
                       'title', 'url', 'is_index');
    is_deeply(\@keys, \@keys_ok, 'Get data for file'); # test 10

    my $body = <<'EOQ';
    <h2>The title</h2>

    <p>The body
</p>
EOQ

    $data = {body => $body};
    $data = $mo->build_title_from_header($data);
    is($data->{title}, 'The title', 'Get title from header'); # test 11

    $data = $mo->build_summary($data);
    is($data->{summary}, "The body\n", 'Get summary'); # test 12
};

