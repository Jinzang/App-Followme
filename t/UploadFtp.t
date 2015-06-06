#!/usr/bin/env perl
use strict;

use IO::File;
use File::Path qw(rmtree);
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

use Test::Requires 'Net::FTP';
use Test::More tests => 5;

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

require App::Followme::UploadFtp;

my $test_dir = catdir(@path, 'test');

rmtree($test_dir);
mkdir $test_dir;
chdir $test_dir;

my $configuration = {
                     top_directory => $test_dir,
                     remote_pkg => 'File::Spec::Unix',
                    };

#----------------------------------------------------------------------
# Test

SKIP: {
    # Site specific configuration

    my $user = '';
    my $password = '';
    $configuration->{ftp_url} = '';
    $configuration->{ftp_directory} = '';

    skip('Ftp connection not configured', 5) unless $configuration->{ftp_url};

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

    my $up = App::Followme::UploadFtp->new($configuration);

    $up->open($user, $password);
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
