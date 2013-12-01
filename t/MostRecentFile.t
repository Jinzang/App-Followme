#!/usr/bin/env perl
use strict;

use IO::File;
use File::Path qw(rmtree);
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

use Test::More tests => 2;

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

require App::Followme::MostRecentFile;

my $test_dir = catdir(@path, 'test');

rmtree($test_dir);
mkdir $test_dir;
chdir $test_dir;

#----------------------------------------------------------------------
# Create test files and test run method and its submethods

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
</body>
</html>
EOQ

    my $mrf = App::Followme::MostRecentFile->new();
    my $filename = $mrf->run($test_dir);
    is($filename, undef, 'Most recent file no files'); # test 2

    foreach my $count (qw(first second third)) {
        sleep(2);
        my $output = $code;
        $output =~ s/%%/Page $count/g;

        my $filename = catfile($test_dir, "$count.html");
        
        my $fd = IO::File->new($filename, 'w');
        print $fd $output;
        close $fd;
    }

    $mrf = App::Followme::MostRecentFile->new();
    $filename = $mrf->run($test_dir);
    my $filename_ok = catfile($test_dir, 'third.html');
    is($filename, $filename_ok, 'Most recent file with files'); # test 2
};

