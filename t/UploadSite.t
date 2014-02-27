#!/usr/bin/env perl
use strict;

use IO::File;
use File::Path qw(rmtree);
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

use Test::More tests => 8;

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

require App::Followme::UploadSite;

my $test_dir = catdir(@path, 'test');

rmtree($test_dir);
mkdir $test_dir;
mkdir catfile($test_dir, 'templates');
chdir $test_dir;

my $configuration = {
                     no_upload => 1,
                     top_directory => $test_dir,
                     template_dir =>'templates',
                     };

#----------------------------------------------------------------------
# Test read and write files

do {
    my $up = App::Followme::UploadSite->new($configuration);

    my $cred_file = catfile(
                            $up->{top_directory},
                            $up->{template_directory},
                            $up->{credentials}
                           );

    my $user_ok = 'gandalf';
    my $password_ok = 'wizzard';
    $up->write_word($cred_file, $user_ok, $password_ok);

    my ($user, $pass) = $up->read_word($cred_file);
    is($user, $user_ok, 'Read user name'); # test 1
    is($pass, $password_ok, 'Read password'); # test 2

    my $hash_file = catfile($up->{top_directory},
                            $up->{template_directory},
                            $up->{hash_file});

    my $hash_ok = {'file1.html' => '014e32',
                   'file2.html' => 'a31571',
                   'sub' => 'dir',
                   'sub/file3.html' => '342611'
                  };

    $up->write_hash_file($hash_ok);

    my $hash = $up->read_hash_file($hash_file);
    is_deeply($hash, $hash_ok, 'read and write hash file'); # test 3

    my $local;
    my %local_ok = map {$_ => 1} keys($hash_ok);

    ($hash, $local) = $up->get_state();
    is_deeply($local, \%local_ok, 'compute local hash'); # test 4
    is_deeply($hash, $hash_ok, 'get hash'); # test 5
    
    unlink($hash_file);
};

#----------------------------------------------------------------------
# Test synchronization

do {

    my $page = <<'EOQ';
<html>
<head>
<meta name="robots" content="archive">
<!-- section meta -->
<title>Post %%</title>
<!-- endsection meta -->
</head>
<body>
<!-- section content -->
<h1>Post %%</h1>

<p>All about !!.</p>
<!-- endsection content -->
</body>
</html>
EOQ

    my $up = App::Followme::UploadSite->new($configuration);

    my $local = {};
    my $hash_ok = {};
    foreach my $dir ('', 'before', 'after') {
        if ($dir) {
            mkdir $dir;
            $local->{$dir} = 1;
            $hash_ok->{$dir} = 'dir';
        }
        
        foreach my $count (qw(one two three)) {
            my $output = $page;
            $output =~ s/!!/$dir/g;
            $output =~ s/%%/$count/g;
        
            my $filename = $dir ? catfile($dir, "$count.html") : "$count.html";
            $up->write_page($filename, $output);

            $local->{$filename} = 1;
            $hash_ok->{$filename} = $up->checksum_file($filename);
        }
    }
    
    my $hash = {};
    my $updates = [];
    my %saved_local = %$local;
    $up->update_folder($up->{top_directory}, $updates, $hash, $local);

    is_deeply($local, {}, 'Find local files'); # test 6
    is_deeply($hash, $hash_ok, 'Compute hash'); # test 7
    
    %$local = %saved_local;
    my @saved_updates = @$updates;
    $up->update_folder($up->{top_directory}, $updates, $hash, $local);
    is_deeply($updates, \@saved_updates, 'Rerun update'); # test 8
};