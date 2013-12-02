package App::Followme::Mock;

use 5.008005;
use strict;
use warnings;

use Cwd;
use IO::File;

use lib '../..';

use File::Spec::Functions qw(abs2rel);
use base qw(App::Followme::EveryFile);

our $VERSION = "0.93";

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($pkg) = @_;
    
    my %parameters = (
            subdir => 0,
            extension => 'html',
           );

    my %base_params = $pkg->SUPER::parameters();
    %parameters = (%base_params, %parameters);

    return %parameters;
}

#----------------------------------------------------------------------
# Do processing needed at end of folder (stub)

sub finish_folder {
    my ($self, $directory) = @_;

    my @folders = sort(@{$self->{files}});
    $self->{files} = \@folders;
    $self->{done} = $self->{files} unless $self->{subdir};
    
    return;
}

#----------------------------------------------------------------------
# Do processing needed at end of site (stub)

sub finish_site {
    my ($self, $directory) = @_;

    my @files = sort @{$self->{files}};
    $self->{done} = \@files;
    
    return;
}

#----------------------------------------------------------------------
# Get the list of included files

sub get_included_files {
    my ($self) = @_;
    return "*.$self->{extension}";
}

#----------------------------------------------------------------------
# Do processing needed for a file (stub)

sub handle_file {
    my ($self, $dir, $filename) = @_;

    $filename = abs2rel($filename);
    push(@{$self->{files}}, $filename);

    return;
}

#----------------------------------------------------------------------
# Do processing needed at start of folder (stub)

sub start_folder {
    my ($self, $directory) = @_;
    return;
}

#----------------------------------------------------------------------
# Do processing needed at start of site (stub)

sub start_site {
    my ($self, $directory) = @_;

    chdir($directory);
    $self->{files} = [];
    return;
}

1;
__END__

=encoding utf-8

=head1 NAME

App::Followme::Mock - Mock object for unit tests

=head1 SYNOPSIS

    use App::Followme::Mock;
    my $mock = App::Followme::Mock->new();
    $mock->run($directory);

=head1 DESCRIPTION

This is a minimal objects intended for unit tests and not for production use.
It also serves as an example of how to create a module, although modules will
probably be a subclass of App:Followme::HandleSite instead of EveryFile. It
returns a sorted list of relative filenames with the specified extension when
run. If subdir is set to true, it will return all filenames in the
subdirectories.

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut
