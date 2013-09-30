#!/usr/bin/env perl
use strict;

use IO::File;
use Test::More tests => 5;
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

require App::Followme::SortPages;
require App::Followme::PageIO;

my $test_dir = catdir(@path, 'test');
system("/bin/rm -rf $test_dir");
mkdir $test_dir;
mkdir "$test_dir/sub";
chdir $test_dir;

#----------------------------------------------------------------------
# Sort files by depth

do {
    my $level = App::Followme::SortPages::get_level();
    is($level, 0, 'Level of root directory'); # test 1
    
    $level = App::Followme::SortPages::get_level('archive/topic/post.html');
    is($level, 3, 'Level of archived post'); # test 2

    my @indexes = qw(a/b/c/four.html a/b/three.html a/two.html one.html);
    my @indexes_ok = reverse @indexes;
    @indexes = App::Followme::SortPages::sort_by_depth(@indexes);
    is_deeply(\@indexes, \@indexes_ok, 'Sort by depth'); # test 3
    
};

#----------------------------------------------------------------------
# Sort files by name

do {
    my @files = qw (third.html second.html first.html index.html);
    my @files_ok = reverse @files;
    
    @files = App::Followme::SortPages::sort_by_name(@files);
    is_deeply(\@files, \@files_ok, "Sort by name"); # test 4    
};

#----------------------------------------------------------------------
# Sort files by modification date

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
<ul>
<li><a href="">&& link</a></li>
<!-- section nav -->
<li><a href="">link %%</a></li>
<!-- endsection nav -->
</ul>
</body>
</html>
EOQ

    my @filenames;
    foreach my $count (qw(four three two one)) {
        sleep(1);
        my $output = $code;
        $output =~ s/%%/$count/g;

        my $filename = "$count.html";
        unshift(@filenames, $filename);
        
        App::Followme::PageIO::write_page($filename, $output);
    }
    
    my @filenames_ok = reverse @filenames;
    @filenames = App::Followme::SortPages::sort_by_date(@filenames);
    is_deeply(\@filenames, \@filenames_ok, 'Sort by date'); #test 5
};
