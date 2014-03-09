#!/usr/bin/env perl
use strict;

use Test::More tests => 21;

use File::Path qw(rmtree);
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

require App::Followme::HandleSite;

my $test_dir = catdir(@path, 'test');

rmtree($test_dir);
mkdir $test_dir;

#----------------------------------------------------------------------
# Test file name conversion

do {
    my $hs = App::Followme::HandleSite->new;

    my $filename = 'foobar.txt';
    my $filename_ok = catfile($test_dir, $filename);
    my $test_filename = $hs->full_file_name($test_dir, $filename);
    is($test_filename, $filename_ok, 'Full file name relative path'); # test 1
    
    $filename = $filename_ok;
    $test_filename = $hs->full_file_name($test_dir, $filename);
    is($test_filename, $filename_ok, 'Full file name absolute path'); # test 2
};

#----------------------------------------------------------------------
# Test builders

do {
    chdir($test_dir);
    
    my $data = {};
    my $hs = App::Followme::HandleSite->new;
    my $text_name = catfile('watch','this-is-only-a-test.txt');
    
    $data = $hs->build_title_from_filename($data, $text_name);
    my $title_ok = 'This Is Only A Test';
    is($data->{title}, $title_ok, 'Build file title'); # test 3

    my $index_name = catfile('watch','index.html');
    $data = $hs->build_title_from_filename($data, $index_name);
    $title_ok = 'Watch';
    is($data->{title}, $title_ok, 'Build directory title'); # test 4
    
    $data = $hs->build_is_index($data, $text_name);
    is($data->{is_index}, 0, 'Regular file in not index'); # test 5
    
    $data = $hs->build_is_index($data, $index_name);
    is($data->{is_index}, 1, 'Index file is index'); # test 6
    
    $data = $hs->build_url($data, $test_dir, $text_name);
    my $url_ok = 'watch/this-is-only-a-test.html';
    is($data->{url}, $url_ok, 'Build a relative file url'); # test 7

    $url_ok = '/' . $url_ok;
    is($data->{absolute_url}, $url_ok, 'Build an absolute file url'); # test 8

    mkdir('watch');
    $data = $hs->build_url($data, $test_dir, 'watch');
    is($data->{url}, 'watch/index.html', 'Build directory url'); #test 9
       
    $data = {};
    my $date = $hs->build_date($data, 'two.html');
    my @date_fields = grep {/\S/} sort keys %$date;
    my @date_ok = sort qw(day month monthnum  weekday  
                          hour24 hour minute second year ampm);
    is_deeply(\@date_fields, \@date_ok, 'Build date'); # test 10
    
    $data = {};
    $data = $hs->external_fields($data, $test_dir, 'two.html');
    my @keys = sort keys %$data;
    my @keys_ok = sort(@date_ok, 'absolute_url', 'title', 'url', 'is_index');
    is_deeply(\@keys, \@keys_ok, 'Get data for file'); # test 11
    
    my $body = <<'EOQ';
    <h2>The title</h2>
    
    <p>The body
</p>
EOQ

    $data = {body => $body};
    $data = $hs->build_title_from_header($data);
    is($data->{title}, 'The title', 'Get title from header'); # test 12
    
    my $summary = $hs->build_summary($data);
    is($summary, "The body\n", 'Get summary'); # test 13
};

#----------------------------------------------------------------------
# Test is newer?

do {
   my $code = <<'EOQ';
<html>
<head>
<meta name="robots" content="archive">
<!-- section meta -->
<title>%%</title>
<!-- endsection meta -->
</head>
<body>
<!-- section content -->
<h1>%%</h1>
<!-- endsection content -->
<!-- section navigation in folder -->
<p><a href="">Link</a></p>
<!-- endsection navigation -->
</body>
</html>
EOQ

    chdir($test_dir);
    my $hs = App::Followme::HandleSite->new;
    
    foreach my $count (qw(four three two one)) {
        sleep(1);
        my $output = $code;
        $output =~ s/%%/Page $count/g;

        my $filename = catfile($test_dir, "$count.html");
        $hs->write_page($filename, $output);

        my $input = $hs->read_page($filename);
        is($input, $output, "Read and write page $filename"); #tests 14-17
    }

    my $newer = $hs->is_newer('three.html', 'two.html', 'one.html');
    is($newer, undef, 'Source is  newer'); # test 18
    
    $newer = $hs->is_newer('one.html', 'two.html', 'three.html');
    is($newer, 1, "Target is newer"); # test 19
    
    $newer = $hs->is_newer('five.html', 'one.html');
    is($newer, undef, 'Target is undefined'); # test 20
    
    $newer = $hs->is_newer('six.html', 'five.html');
    is($newer, 1, 'Source and target undefined'); # test 21
};
