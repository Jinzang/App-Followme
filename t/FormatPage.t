#!/usr/bin/env perl
use strict;

use IO::File;
use File::Path qw(rmtree);
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

use Test::More tests => 18;

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

require App::Followme::FormatPage;

my $test_dir = catdir(@path, 'test');

rmtree($test_dir);
mkdir $test_dir;
mkdir catfile($test_dir, "sub");
chdir $test_dir;

my $configuration = {};

#----------------------------------------------------------------------
# Write test pages

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

    my $up = App::Followme::FormatPage->new($configuration);

    foreach my $dir (('sub', '')) {
        foreach my $count (qw(four three two one)) {
            sleep(1);
            my $output = $code;
            my $dir_name = $dir ? $dir : 'top';
            
            $output =~ s/%%/$count/g;
            $output =~ s/&&/$dir_name/g;
            $output =~ s/section nav/section nav in $dir/ if $dir;

            my @dirs;
            push(@dirs, $test_dir);
            push(@dirs, $dir) if $dir;
            my $filename = catfile(@dirs, "$count.html");
            
            $up->write_page($filename, $output);
        }
    }
};

#----------------------------------------------------------------------
# Test get prototype path and find prototype

do {
    my $up = App::Followme::FormatPage->new($configuration);
    my $bottom = catfile($test_dir, 'sub');
    chdir($bottom);

    my $prototype_path = $up->get_prototype_path('one.html');
    
    is_deeply($prototype_path, {sub => 1}, 'Get prototype path'); # test 1
    
    my $prototype_file = $up->find_prototype($bottom, 1);
    is($prototype_file, catfile($test_dir, 'one.html'),
       'Find prototype'); # test 2
};

#----------------------------------------------------------------------
# Test run

do {
    chdir ($test_dir);
    my $up = App::Followme::FormatPage->new($configuration);

    foreach my $dir (('sub', '')) {
        my $path = $dir ? catfile($test_dir, $dir) : $test_dir;
        chdir($path);

        $up->run($path);
        foreach my $count (qw(two one)) {
            my $filename = "$count.html";
            my $input = $up->read_page($filename);

            ok($input =~ /Page $count/,
               "Format block in $dir/$count"); # test 3, 7, 11, 15
            
            ok($input =~ /top link/,
               "Format prototype $dir/$count"); # test 4, 8, 12 16

            if ($dir) {
                ok($input =~ /section nav in sub --/,
                   "Format section tag in $dir/$count"); # test 13, 17
                ok($input =~ /link one/,
                   "Format folder block $dir/$count"); # test 14, 18
                
            } else {
                ok($input =~ /section nav --/, 
                   "Format section tag in $dir/$count"); # test 5, 9
                ok($input =~ /link $count/, 
                   "Format folder block in $dir/$count"); # test 6, 12
            }
        }
    }
}
