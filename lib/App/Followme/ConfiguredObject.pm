package App::Followme::ConfiguredObject;

use 5.008005;
use strict;
use warnings;

use Cwd;
our $VERSION = "1.03";

#----------------------------------------------------------------------
# Create object that returns files in a directory tree

sub new {
    my ($package, $configuration) = @_;
    no strict 'refs';

    my $self = {};
    my @pkgs = ($package, @{"${package}::ISA"});
    $configuration = {} unless defined $configuration;

    foreach my $pkg (reverse @pkgs) {
        $self = bless($self, $pkg);

        $self->update_parameters($configuration)
            if defined &{"${pkg}::parameters"};    

        $self->setup($configuration)   
            if defined &{"${pkg}::setup"};    
    }

    return $self;
}

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($self) = @_;
    
    return (
            quick_update => 0,
            top_directory => getcwd(),
            base_directory => getcwd(),
           );
}

#----------------------------------------------------------------------
# Run the object on a directory (stub)

sub run {
    my ($self, $directory) = @_;    
    die "Run method not defined";
}

#----------------------------------------------------------------------
# Set up object fields (stub)

sub setup {
    my ($self, $configuration) = @_;
    return;
}

#----------------------------------------------------------------------
# Update a module's parameters

sub update_parameters {
    my ($self, $configuration) = @_;
        
    my %parameters = $self->parameters();
    foreach my $field (keys %parameters) {
        if (exists $configuration->{$field}) {
            $self->{$field} = $configuration->{$field};
        } else {
            $self->{$field} = $parameters{$field};            
        }
    }
    
    return;
}

1;
__END__

=encoding utf-8

=head1 NAME

App::Followme::ConfiguredObject - Base class for App::Followme classes

=head1 SYNOPSIS

    use App::Followme::ConfiguredObject;
    my $fo = App::Followme::ConfiguredObjects->new($configuration);

=head1 DESCRIPTION

This class contains the methods create a new configured object. The following
methods are noteworthy:

=over 4

=item $obj = ConfiguredObject->new($configuration);

Create a new object from the configuration. The configuration is a reference to
a hash containing fields with the same names as the object parameters. Fields
in the configuration whose name does not match an object parameter are ignored.

=item %parameters = $self->parameters();

Returns a hash of the default values of the object's parameters

=item $self->run($directory);

Run the object on a directory.

=item $self->setup($configuration);

Sets computed parameters of the object.

=back

=head1 CONFIGURATION

The following fields in the configuration file are used in this class and every
class based on it:

=over 4

=item base_directory

The directory the class is loaded in. The default value is the current directory.

=item quick_mode

A flag indicating application is run in quick mode.

=item top_directory

The top directory of the website The default value is the current directory.

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut
