package App::Followme::Update;

use 5.008005;
use strict;
use warnings;

use Cwd;
use IO::Dir;
use IO::File;
use File::Spec::Functions qw(rel2abs splitdir catfile);

our $VERSION = "0.90";

#----------------------------------------------------------------------
# Create a new object to update a website

sub new {
    my ($pkg, $configuration) = @_;
    $configuration = {} unless defined $configuration;
    
    my %self = ($pkg->parameters(), %$configuration); 
    return bless(\%self, $pkg);
}

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($pkg) = @_;
    
    return (
            configuration_file => 'followme.cfg',
            module => [
                       'App::Followme::FormatPages',
                       'App::Followme::ConvertPages',
                      ],
            );
}

#----------------------------------------------------------------------
# Perform all updates on the directory

sub run {
    my ($self, $directory) = @_;
    $directory = getcwd() unless defined $directory;
    
    my $configuration = $self->initialize_configuration($directory);
    $self->update_folder($directory, $configuration);

    return;
}

#----------------------------------------------------------------------
# Get the subdirectories in a folder

sub get_subdirectories {
    my ($self) = @_;

    my @subdirectories;    
    my $dd = IO::Dir->new(getcwd());

    while (defined (my $file = $dd->read())) {
        # TODO: no_upwards
        next if $file eq '.' || $file eq '..';
        push(@subdirectories, $file) if -d $file;
    }
    
    return @subdirectories;
}

#----------------------------------------------------------------------
# Find and read the configuration files

sub initialize_configuration {
    my ($self, $directory) = @_;

    $directory = rel2abs($directory);
    my @path = splitdir($directory);

    my @dir;
    my $configuration = $self;

    while (defined(my $path = shift(@path))) {
        push(@dir, $path);
        my $filename = catfile(@dir, $self->{configuration_file});
        next unless -e $filename;

        $configuration->{base_dir} = catfile(@dir)
            unless exists $configuration->{base_dir};

        $configuration = $self->update_configuration($filename, $configuration);
    }

    return $configuration;
}

#----------------------------------------------------------------------
# Load a modeule if it has not already been loaded

sub load_module {
    my ($self, $module, $configuration) = @_;

    eval "require $module" or die "Module not found: $module\n";
    my $obj = $module->new($configuration);
    
    return $obj;
}

#----------------------------------------------------------------------
# Set a value in the configuration hash

sub set_configuration {
    my ($self, $configuration, $name, $value) = @_;
    
    if (ref $configuration->{$name} eq 'HASH') {
        $configuration->{$name}{$value} = 1;
        
    } elsif (ref $configuration->{$name} eq 'ARRAY') {
        push(@{$configuration->{$name}}, $value);

    } else {
       $configuration->{$name} = $value;
    }

    return;
}

#----------------------------------------------------------------------
# Update the configuration from a file

sub update_configuration {
    my ($self, $filename, $configuration) = @_;

    my %new_configuration = %$configuration;
    my $fd = IO::File->new($filename, 'r');

    if ($fd) {
        while (my $line = <$fd>) {
            # Ignore comments and blank lines
            next if $line =~ /^\s*\#/ || $line !~ /\S/;

            # Split line into name and value, remove leading and
            # trailing whitespace

            my ($name, $value) = split (/\s*=\s*/, $line, 2);

            die "Bad line in config file: ($name)" unless defined $value;
            $value =~ s/\s+$//;

            # Insert the name and value into the hash

            $self->set_configuration(\%new_configuration, $name, $value);
        }

        close($fd);
    }

    return \%new_configuration;
}

#----------------------------------------------------------------------
# Update files in one folder

sub update_folder {
    my ($self, $directory, $configuration) = @_;
    
    my $current_directory = getcwd();
    chdir($directory);
    
    if (-e $self->{configuration_file}) {
        $configuration =
            $self->update_configuration($self->{configuration_file},
                                        $configuration);
    }
    
    my @modules;
    foreach my $module (@{$configuration->{module}}) {
        my $obj = $self->load_module($module, $configuration);
        push(@modules, $module) if $obj->run();
    }
    
    $configuration->{modules} = \@modules;
    my @subdirectories = $self->get_subdirectories();

    foreach my $subdirectory (@subdirectories) {
        $self->update_folder($subdirectory, $configuration);
    }
    
    chdir($current_directory);
    return;
}

1;
__END__

=encoding utf-8

=head1 NAME

App::Followme::Update - Update a static website

=head1 SYNOPSIS

    use App::Followme::Update ;
    my $updater = App::Followme::Update->new($options);
    $updater->run(shift @ARGV);

=head1 DESCRIPTION

This is the module that is run by the followme script. It loads and runs
all the other modules. When it is run, it searches the directory path for
configuration files. The topmost file defines the base directory of the website.
It reads each configuration file it finds and then starts updating the directory
passed as an argument to run, or if no directory is passed, the directory the
followme script is run from.

Configuration file lines are organized as lines containing

    NAME = VALUE

and may contain blank lines or comment lines starting with a C<#>. Values in
configuration files are combined with those set in the files in directories
above it.

The module parameter contains the name of a module to be run on the directory
containing the configuration file and possibly its subdirectory. It must have
new and run methods. An object is created by calling the new method with the
configuration. The run method is then called without arguments. The run method
returns a value, which if true indicates that module should be run in the
subdirectories of the current directory.

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut

