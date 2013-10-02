#!/usr/bin/env perl
use strict;

use IO::File;
use Test::More tests => 7;
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

require App::Followme::Variables;
require App::Followme::PageIO;

my $test_dir = catdir(@path, 'test');
system("/bin/rm -rf $test_dir");
mkdir $test_dir;
mkdir "$test_dir/sub";
chdir $test_dir;

#----------------------------------------------------------------------
# Create test files

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
<p><a href="">&&</a></p>
<!-- endsection navigation -->
</body>
</html>
EOQ

    foreach my $dir (('sub', '')) {
        foreach my $count (qw(four three two one)) {
            my $output = $code;
            $output =~ s/%%/Page $count/g;
            $output =~ s/&&/$dir link/g;

            my $filename = $dir ? "$dir/$count.html" : "$count.html";
            App::Followme::PageIO::write_page($filename, $output);
        }
    }
};

#----------------------------------------------------------------------
# Test builders

do {

    my $text_name = catfile('watch','this-is-only-a-test.txt');
    my $page_name = App::Followme::Variables::build_page_name($text_name);
    my $page_name_ok = catfile('watch','this-is-only-a-test.html');
    is($page_name, $page_name_ok, 'Build page'); # test 1
    
    my $title = App::Followme::Variables::build_title($text_name);
    my $title_ok = 'This Is Only A Test';
    is($title, $title_ok, 'Build file title'); # test 2

    my $index_name = catfile('watch','index.html');
    $title = App::Followme::Variables::build_title($index_name);
    $title_ok = 'Watch';
    is($title, $title_ok, 'Build directory title'); # test 3
    
    my $url = App::Followme::Variables::build_url($text_name);
    my $url_ok = 'watch/this-is-only-a-test.html';
    is($url, $url_ok, 'Build file url'); # test 4

    $url = App::Followme::Variables::build_url('watch');
    is($url, 'watch/index.html', 'Build directory url'); #test 5
       
    my $time = 1;
    my $date = App::Followme::Variables::build_date(time());
    my @date_fields = grep {/\S/} sort keys %$date;
    my @date_ok = sort qw(day month monthnum  weekday hour24 hour 
                   minute second year ampm);
    is_deeply(\@date_fields, \@date_ok, 'Build date'); # test 6
    
    my $data = App::Followme::Variables::set_variables('two.html');
    my @keys = sort keys %$data;
    my @keys_ok = sort(@date_ok, 'title');
    is_deeply(\@keys, \@keys_ok, 'Get data for file'); # test 7
};

