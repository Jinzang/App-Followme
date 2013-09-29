#!/usr/bin/env perl
use strict;

use IO::File;
use Test::More tests => 4;
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

require App::Followme::PageIO;

my $test_dir = catdir(@path, 'test');
system("/bin/rm -rf $test_dir");
mkdir $test_dir;
mkdir "$test_dir/sub";
chdir $test_dir;

#----------------------------------------------------------------------
# Test read and write pages

do {
   my $code = <<'EOQ';
<html>
<head>
<meta name="robots" content="archive">
<!-- section meta -->
<title>Page %%</title>
<!-- endsection meta -->
</head>
<body>
<!-- section content -->
<h1>Page %%</h1>
<!-- endsection content -->
<!-- section navigation  -->
<p><a href="">%% link</a></p>
<!-- endsection navigation -->
</body>
</html>
EOQ

    foreach my $count (qw(four three two one)) {
        my $output = $code;
        $output =~ s/%%/$count/g;

        my $filename = "$count.html";
        App::Followme::PageIO::write_page($filename, $output);

        my $input = App::Followme::PageIO::read_page($filename);
        is($input, $output, "Read and write page $filename"); #tests 1-4
    }
};

