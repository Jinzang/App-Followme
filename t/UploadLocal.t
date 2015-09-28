#!/usr/bin/env perl
use strict;

use IO::File;
use File::Path qw(rmtree);
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

use Test::More tests => 5;

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

require App::Followme::UploadLocal;

my $test_dir = catdir(@path, 'test');
my $local_dir = catdir($test_dir, 'here');
my $remote_dir = catdir($test_dir, 'there');

rmtree($test_dir);

mkdir $test_dir;
mkdir $local_dir;
mkdir $remote_dir;

chdir $local_dir;

my %configuration = (
                     top_directory => $local_dir,
                     remote_directory => $remote_dir,
                    );

#----------------------------------------------------------------------
# Test

do {
    # Test files

    my $dir = 'subdir';
    my $filename = 'filename.html';

    my $file = <<EOQ;
<html>
<head>
<title>Test File</title>
</head>
<body>
<p>Test file.</p>
</body>
</html>
EOQ

    my $fd = IO::File->new($filename, 'w');
    print $fd $file;
    close($fd);

     # The methods to test

    my $up = App::Followme::UploadLocal->new(%configuration);

    $up->open();
    my $flag =$up->add_directory($dir);
    is($flag, 1, 'Add directory'); # test 1

    $flag = $up->add_file($filename);
    is($flag, 1, 'Add file'); # test 2

    $flag = $up->add_file($filename);
    is($flag, 1, 'Add file again'); # test 3

    $flag = $up->delete_file($filename);
    is($flag, 1, 'Delete file'); # test 4

    $flag = $up->delete_directory($dir);
    is($flag, 1, 'Delete directory'); # test 5

    $up->close();
};
