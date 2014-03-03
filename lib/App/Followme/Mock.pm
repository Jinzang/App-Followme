package App::Followme::Mock;

use 5.008005;
use strict;
use warnings;

use lib '../..';

use File::Spec::Functions qw(abs2rel catfile);
use base qw(App::Followme::HandleSite);

our $VERSION = "1.00";

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
# Return a list of all files in a directory

sub run {
    my ($self, $directory) = @_;

    my @list = $self->list_files($directory);
    my $page = join("\n", @list);
    
    my $filename = catfile($directory, 'index.dat');
    $self->write_page($filename, $page);
   
    return;
}

#----------------------------------------------------------------------
# Return a list of all files in a directory

sub list_files {
    my ($self, $directory) = @_;

    my @list;
    my ($filenames, $directories) =  $self->visit($directory);
    foreach my $filename (@$filenames) {
        $filename = abs2rel($filename, $self->{base_directory});
        push(@list, $filename);
    }

    if ($self->{subdir}) {
        foreach my $subdirectory (@$directories) {
            push(@list, $self->list_files($subdirectory));
        }
    }
   
    return @list;
}

#----------------------------------------------------------------------
# Get the list of included files

sub get_included_files {
    my ($self) = @_;
    return "*.$self->{extension}";
}

1;
__END__

=encoding utf-8

=head1 NAME

App::Followme::Mock - Mock object for unit tests

=head1 SYNOPSIS

    use App::Followme::Mock;
    my $mock = App::Followme::Mock->new();
    my @list = $mock->run($directory);

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
