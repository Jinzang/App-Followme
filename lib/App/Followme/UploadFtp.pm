package App::Followme::UploadFtp;

use 5.008005;
use strict;
use warnings;

use lib '..';

use base qw(App::Followme::EveryFile);

use Net::FTP;
use File::Spec::Functions qw(abs2rel splitdir catfile);

our $VERSION = "0.98";

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($pkg) = @_;
    
    my %parameters = (
                      ftp_url => '',
                      ftp_directory => '',
                      remote_pkg => 'File::Spec::Unix',
                     );

    my %base_params = $pkg->SUPER::parameters();
    %parameters = (%base_params, %parameters);

    return %parameters;
}

#----------------------------------------------------------------------
# Add a directory to the remote site

sub add_directory {
    my ($self, $dir) = @_;

    $dir = $self->remote_name($dir);

    if ($self->{ftp}->size($dir)) {
        $self->{ftp}->delete($dir);
    }
    
    return $self->{ftp}->mkdir($dir);
}

#----------------------------------------------------------------------
# Add a file to the remote site

sub add_file {
    my ($self, $filename) = @_;
    
    $filename = $self->remote_name($filename);
    
    if ($self->{ftp}->size($filename)) {
        $self->{ftp}->delete($filename);
    }
    
    return $self->{ftp}->put($filename);
}

#----------------------------------------------------------------------
# Close the ftp connection

sub close {
    my ($self) = @_;    

    $self->{ftp}->quit();
    undef $self->{ftp};
    
    return;
}

#----------------------------------------------------------------------
# Delete a directory on the remote site, including contents

sub delete_directory {
    my ($self, $dir) = @_;
    
    $dir = $self->remote_name($dir);
    return $self->{ftp}->rmdir($dir, 1);
}

#----------------------------------------------------------------------
# Delete a file on the remote site

sub delete_file {
    my ($self, $filename) = @_;
    
    $filename = $self->remote_name($filename);
    return $self->{ftp}->delete($filename);    
}

#----------------------------------------------------------------------
# Open the connection to the remote site

sub open {
    my ($self, $user, $password) = @_;

    # Open the ftp connection
    
    my $ftp = Net::FTP->new($self->{ftp_url})
        or die "Cannot connect to $self->{ftp_url}: $@";
 
    $ftp->login($user, $password) or die "Cannot login ", $ftp->message;
 
    $ftp->cwd($self->{ftp_directory})
        or die "Cannot change remote directory ", $ftp->message;

    $self->{ftp} = $ftp;
    return;
}

#----------------------------------------------------------------------
# Get the name of the file on the remote system

sub remote_name {
    my ($self, $filename) = @_;

    my @path = splitdir($filename);
    $filename = $self->{remote_pkg}->catfile(@path);
    return $filename;
}

#----------------------------------------------------------------------
# Set up object parameters

sub setup {
    my ($self, $configuration) = @_;

    # Load the methods that build file names for the remote site,
    # which my be different than thos on this machine
    
    my $remote_pkg = $self->{remote_pkg};
    eval "require $remote_pkg" or die "Module not found: $remote_pkg\n";
    
    return $self;
}

1;
__END__
=encoding utf-8

=head1 NAME

App::Followme::UploadFtp - Upload files using ftp

=head1 SYNOPSIS

    my $ftp = App::Followme::UploadNone->new(\%configuration);
    $ftp->open($user, $password);
    $ftp->add_directory($dir);
    $ftp->add_file($filename);
    $ftp->delete_file($filename);
    $ftp->delete_dir($dir);
    $ftp->close();

=head1 DESCRIPTION

L<App::Followme::UploadSite> splits off methods that do the actual uploading
into a separate package, so it can support more than one method. This package
uploads files using good old ftp.

=head1 METHODS

The following are the public methods of the interface

=over =back

=item $flag = $self->add_directory($dir);

Create a new directory.

=item $flag = $self->add_file($filename);

Upload a file.

=item $flag = $self->delete_directory($dir);

Delete a directory, including its contents

=item $flag = $self->delete_file($filename);

Delete a file on the remote site. .

=item $self->close();

Close the ftp connection to the remote site.

=item $self = $self->setup($configuration);

Open the ftp connection. The configuration is a reference to
a hash, which includes the user name and password used in the connection.

=head1 CONFIGURATION

The follow parameters are used from the configuration. In addition, the package
will prompt for and save the user name and password.

=over 4

=item ftp_url

The url of the remote ftp site.

=item ftp_directory

The top directory of the remote site

=item remote_pkg

The name of the package that manipulates filenames for the remote system. The
default value is 'File::Spec::Unix'. Other possible values are
'File::Spec::Win32' and 'File::Spec::VMS'. Consult the Perl documentation for

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut

