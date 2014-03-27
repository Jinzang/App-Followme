package App::Followme::UploadSite;

use 5.008005;
use strict;
use warnings;

use lib '../..';

use base qw(App::Followme::Module);

use Cwd;
use IO::File;
use Digest::MD5 qw(md5_hex);
use File::Spec::Functions qw(abs2rel splitdir catfile);

our $VERSION = "1.03";

use constant SEED => 96;

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($self) = @_;
    
    return (
            verbose => 0,
            no_upload => 0,
            max_errors => 5,
            hash_file => 'upload.hash',
            credentials => 'upload.cred',
            upload_pkg => 'App::Followme::UploadFtp',
           );

}

#----------------------------------------------------------------------
# Perform all updates on the directory

sub run {
    my ($self, $directory) = @_;

    my ($hash, $local) = $self->get_state();

    my ($user, $pass) = $self->get_word();
    $self->{uploader}->open($user, $pass);

    eval {
        $self->update_folder($self->{top_directory}, $hash, $local);
        $self->clean_files($hash, $local);    
        $self->{uploader}->close();
    };
    
    my $error = $@;
    $self->write_hash_file($hash);

    die $error if $error;    
    return;
}

#----------------------------------------------------------------------
# ASK_WORD -- Ask for user name and password if file not found

sub ask_word {
    my ($self) = @_;

    print "\nUser name: ";
    my $user = <STDIN>;
    chomp ($user);

    print "Password: ";
    my $pass = <STDIN>;
    chomp ($pass);

    return ($user, $pass);
}

#----------------------------------------------------------------------
# Compute checksum for a file

sub checksum_file {
    my ($self, $filename) = @_;    

    my $fd = IO::File->new($filename, 'r');
    return '' unless $fd;
    
    my $md5 = Digest::MD5->new;
    foreach my $line (<$fd>) {
        $md5->add($line);        
    }

    close($fd);
    return $md5->hexdigest;
}

#----------------------------------------------------------------------
# Write a file to the remote site, creating any directories needed

sub clean_files {
    my ($self, $hash, $local) = @_;
    
    my @filenames = sort {length($b) <=> length($a)} keys(%$local);
    
    foreach my $filename (@filenames) {
        my $flag;
        if ($hash->{$filename} eq 'dir') {
            $flag = $self->{uplader}->delete_directory($filename);            
        } else {
            $flag = $self->{uplader}->delete_file($filename);                        
        }

        if ($flag) {
            delete $hash->{$filename};
            print "delete $filename\n" if $self->{verbose};

        } else {
            die "Too many upload errors\n" if $self->{max_errors} == 0;
            $self->{max_errors} --;
        }
    }
    
    return;    
}

#----------------------------------------------------------------------
# Get the list of excluded files

sub get_excluded_files {
    my ($self) = @_;

    return '*.cfg';
}

#----------------------------------------------------------------------
# Get the list of included files

sub get_included_files {
    my ($self) = @_;

    return '*';
}

#----------------------------------------------------------------------
# Get the state of the site, contained in the hash file

sub get_state {
    my ($self) = @_;

    my $hash_file = catfile($self->{top_directory},
                            $self->{template_directory},
                            $self->{hash_file});

    if (-e $hash_file) {
        my @stats = stat($hash_file);  
        $self->{target_date} = $stats[9];
    }

    my $hash = $self->read_hash_file($hash_file);
    my %local = map {$_ => 1} keys %$hash;
    
    return ($hash, \%local);
}

#----------------------------------------------------------------------
# GET_WORD -- Say the secret word, the duck comes down and you win $100

sub get_word {
    my ($self) = @_;

    my $filename = catfile(
                            $self->{top_directory},
                            $self->{template_directory},
                            $self->{credentials}
                           );

    my ($user, $pass);
    if (-e $filename) {
        ($user, $pass) = $self->read_word($filename);
    } else {
        ($user, $pass) = $self->ask_word();
        $self->write_word($filename, $user, $pass);
    }

    return ($user, $pass);
}

#----------------------------------------------------------------------
# Add obfuscation to string

sub obfuscate {
    my ($self, $user, $pass) = @_;

    my $obstr = '';
    my $seed = SEED;
    my $str = "$user:$pass";

    for (my $i = 0; $i < length($str); $i += 1) {
        my $val = ord(substr($str, $i, 1));
        $seed = $val ^ $seed;
        $obstr .= sprintf("%02x", $seed);
    }

    return $obstr;
}

#----------------------------------------------------------------------
# Read the hash for each file on the site from a file

sub read_hash_file {
    my ($self, $filename) = @_;

    my %hash;
    my $fd = IO::File->new($filename, 'r');
    
    if ($fd) {
        while (my $line = <$fd>) {
            chomp $line;
            my ($name, $value) = split (/\t/, $line, 2);
            die "Bad line in hash file: ($name)" unless defined $value;

            $hash{$name} = $value;
        }
        close($fd);
    }

    return \%hash;
}

#----------------------------------------------------------------------
# Read the user name and password from a file

sub read_word {
    my ($self, $filename) = @_;
    
    my $fd = IO::File->new ($filename, 'r') || die "Cannot read $filename\n";

    my $obstr = <$fd>;
    chomp($obstr);
    close($fd);

    my ($user, $pass) = $self->unobfuscate($obstr);
    return ($user, $pass);
}

#----------------------------------------------------------------------
# Load the modules that will upload the file and convert the filename

sub setup {
    my ($self, $configuration) = @_;

    # Add the remote user name and password to the configuration
    # They are not stored in the configuration, so they will not
    #  be in the clear

    my $upload_pkg = $self->{no_upload} ? 'App::Followme::UploadNone'
                                 : $self->{upload_pkg};

    eval "require $upload_pkg" or die "Module not found: $upload_pkg\n";
    $self->{uploader} = $upload_pkg->new($configuration);
    
    # Turn off messages when in quick mode
    $self->{verbose} = 0 if $self->{quick_mode};
    
    # The target date is the date of the hash file, used in quick mode
    # to select which files to test
    $self->{target_date} = 0;

    return;
}

#----------------------------------------------------------------------
# Remove obfuscation from string

sub unobfuscate {
    my ($self, $obstr) = @_;

    my $str = '';
    my $seed = SEED;
    
    for (my $i = 0; $i < length($obstr); $i += 2) {
        my $val = hex(substr($obstr, $i, 2));
        $str .= chr($val ^ $seed);
        $seed = $val;
    }

    return split(/:/, $str, 2);
}

#----------------------------------------------------------------------
# Update files in one folder

sub update_folder {
    my ($self, $directory, $hash, $local) = @_;
    
    my ($filenames, $directories) = $self->visit($directory);
        
    # Check if folder is new

    if ($directory ne $self->{top_directory}) {
        $directory = abs2rel($directory, $self->{top_directory});
        delete $local->{$directory} if exists $local->{$directory};
        
        if (! exists $hash->{$directory} ||
            $hash->{$directory} ne 'dir') {
            
            if ($self->{uploader}->add_directory($directory)) {
                $hash->{$directory} = 'dir';
                print "add $directory\n" if $self->{verbose};

            } else {
                die "Too many upload errors\n" if $self->{max_errors} == 0;
                $self->{max_errors} --;
            }
        }
    }

    # Check each of the files in the directory
    
    foreach my $filename (@$filenames) {
        next unless $self->match_file($filename);

        # Skip check if in quick mode and modification date is old
        
        if ($self->{quick_update}) {
            my @stats = stat($filename);  
            next if $self->{target_date} > $stats[9];
        }

        $filename = abs2rel($filename, $self->{top_directory});
        delete $local->{$filename} if exists $local->{$filename};

        my $value = $self->checksum_file($filename);

        # Add file if new or changed
        
        if (! exists $hash->{$filename} || $hash->{$filename} ne $value) {
            if ($self->{uploader}->add_file($filename)) {
                $hash->{$filename} = $value;
                print "add $filename\n" if $self->{verbose};

            } else {
                die "Too many upload errors\n" if $self->{max_errors} == 0;
                $self->{max_errors} --;
            }
        }
    }
    
    # Recursively check each of the subdirectories
    
    foreach my $subdirectory (@$directories) {
        next unless $self->search_directory($subdirectory);
        $self->update_folder($subdirectory, $hash, $local);
    }

    return;
}

#----------------------------------------------------------------------
# Write the hash back to a file

sub write_hash_file {
    my ($self, $hash) = @_;

    my $filename = catfile($self->{top_directory},
                           $self->{template_directory},
                           $self->{hash_file});
    
    my $fd = IO::File->new($filename, 'w');
    die "Couldn't write hash file: $filename" unless $fd;
    
    while (my ($name, $value) = each(%$hash)) {
        print $fd "$name\t$value\n";
    }
    
    close($fd);
    return;
}

#----------------------------------------------------------------------
# WRITE_WORD -- Write the secret word to a file

sub write_word {
    my ($self, $filename, $user, $pass) = @_;

    my $obstr = $self->obfuscate ($user, $pass);

    my $fd = IO::File->new ($filename, 'w') || die "Cannot write $filename: $!";
    print $fd $obstr, "\n";
    close($fd);

    chmod (0600, $filename);
    return;
}

1;
__END__

=encoding utf-8

=head1 NAME

App::Followme::Uploadme - Upload changed and new files

=head1 SYNOPSIS

    my $app = App::Followme::UploadSite->new(\%configuration);
    $app->run($directory);

=head1 DESCRIPTION

This module uploads changed files to a remote site. The default method to do the
uploads is ftp, but that can be changed by changing the parameter upload_pkg.
This package computes a checksum for every file in the site. If the checksum has
changed since the last time it was run, the file is uploaded to the remote site.
If there is a checksum, but no local file, the file is deleted from the remote
site. If this module is run in quick mode, only files whose modification date is
later then the last time it was run are checked.

=head1 CONFIGURATION

The following fields in the configuration file are used:

=over 4

=item credentials

The name of the file which holds the user name and password for the remote site
in obfuscated form. It is in the templates directory and the default name is
'upload.cred'.

=item hash_file

The name of the file containing all the checksums for files on the site. It
is in the templates directory and the default name is 'upload.hash'.

=item max_errors

The number of upload errors the module tolerate before quitting. The default
value is 5.

=item no_upload

If the site has been uploaded by another program and is up to date, set this
variable to 1. It will recompute the hash file, but not upload any files.

=item upload_pkg

The name of the package with methods that add and delete files on the remote
site. The default is L<App::Followme::UploadFtp>. Other packages can be
written, the methods a package must support can be found in
L<App::Followme::None>.

=item verbose

Print names of uploaded files when not in quick mode

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut

