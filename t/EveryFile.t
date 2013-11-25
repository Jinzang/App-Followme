#!/usr/bin/env perl
use strict;

use IO::File;
use File::Path qw(rmtree);
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

use Test::More tests => 6;

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

require App::Followme::EveryFile;
require App::Followme::MostRecentFile;

my $test_dir = catdir(@path, 'test');

rmtree($test_dir);
mkdir $test_dir;
mkdir catfile($test_dir, "sub");
chdir $test_dir;

#----------------------------------------------------------------------
# Test file visitor

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

    my @ok_filenames;
    foreach my $dir (('sub', '')) {
        foreach my $count (qw(four three two one)) {
            sleep(1);
            my $output = $code;
            $output =~ s/%%/Page $count/g;
            $output =~ s/&&/$dir link/g;

            my @dirs;
            push(@dirs, $test_dir);
            push(@dirs, $dir) if $dir;
            my $filename = catfile(@dirs, "$count.html");
            push(@ok_filenames, $filename);
            
            my $fd = IO::File->new($filename, 'w');
            print $fd $output;
            close $fd;
        }
    }

    my $ef = App::Followme::EveryFile->new();
    is($ef->{base_directory}, $test_dir, 'Set EveryFile base directory');  # test 1
    
    my @filenames;
    while (my $filename = $ef->next()) {
        push(@filenames, $filename);
    }
    
    @ok_filenames = reverse @ok_filenames;    
    is_deeply(\@filenames, \@ok_filenames, 'Everyfile next'); # test 2

    my $mrf = App::Followme::MostRecentFile->new();
    
    my $filename = $mrf->next();
    my $ok_filename = shift(@ok_filenames);
    is($filename, $ok_filename, 'Most recent file next'); #test 3
};

#----------------------------------------------------------------------
# Test file visitor

do {
    my $exclude_files = '*.htm,template_*';
    my $excluded_files_ok = ['\.htm$', '^template_'];
    
    my $ef = App::Followme::EveryFile->new();
    my $excluded_files = $ef->glob_patterns($exclude_files);

    is_deeply($excluded_files, $excluded_files_ok, 'Glob patterns'); # test 4

    my $dir_ok = $test_dir;
    my $file_ok = 'index.html';
    my $filename = catfile($dir_ok, $file_ok);
    my ($dir, $file) = $ef->split_filename($filename);
    is($dir, $dir_ok, 'Split directory'); # test 5
    is($file, $file_ok, 'Split filename'); # test 6
};