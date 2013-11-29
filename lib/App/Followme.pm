package App::Followme;

use 5.008005;
use strict;
use warnings;

use lib '..';

use base qw(App::Followme::PageHandler);

use Cwd;
use IO::File;
use File::Spec::Functions qw(rel2abs splitdir catfile no_upwards rootdir updir);
use App::Followme::TopDirectory;

our $VERSION = "0.93";

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($pkg) = @_;
    
    my %parameters = (
                      configuration_file => 'followme.cfg',
                      exclude_folders => 'templates',
                     );

    my %base_params = $pkg->SUPER::parameters();
    %parameters = (%base_params, %parameters);

    return %parameters;
}

#----------------------------------------------------------------------
# Perform all updates on the directory

sub run {
    my ($self, $directory) = @_;

    my $configuration = $self->initialize_configuration($directory);
    $self->update_folder($directory, $configuration);

    return;
}

#----------------------------------------------------------------------
# Perform a deep copy of the configuration

sub copy_config {
    my ($self, $data) = @_;

    my $copied_data;
    my $ref = ref $data;

    if ($ref eq 'ARRAY') {
        my @array;
        foreach my $item (@$data) {
            push(@array, $self->copy_config($item));
        }
        $copied_data = \@array;

    } elsif ($ref eq 'HASH') {
        my %hash;
        while (my ($name, $value) = each(%$data)) {
            $hash{$name} = $self->copy_config($value);
        }
        $copied_data = \%hash;
        
    } else {
        $copied_data = $data;
    }
    
    return $copied_data;
}

#----------------------------------------------------------------------
# Get the list of excluded files

sub get_excluded_files {
    my ($self) = @_;
    return $self->{exclude_folders};
}

#----------------------------------------------------------------------
# Get the list of included files

sub get_included_files {
    my ($self) = @_;
    return '*';
}

#----------------------------------------------------------------------
# Find the configuration files above a directory

sub find_configuration {
    my ($self, $directory) = @_;

    chdir($directory);
    my $root_dir = rootdir();
    my @configuration_files;

    for (;;) {
        chdir(updir());
        last if getcwd() eq $root_dir;

        push(@configuration_files, rel2abs($self->{configuration_file}))
            if -e $self->{configuration_file};
    }
    
    chdir($directory);
    return reverse @configuration_files;
}

#----------------------------------------------------------------------
# Find and read the configuration files

sub initialize_configuration {
    my ($self, $directory) = @_;

    my $configuration = {};
    %$configuration = %$self;
    $configuration->{module} = [];
    
    my $top_dir;
    foreach my $filename ($self->find_configuration($directory)) {
        my ($dir, $file) = $self->split_filename($filename);
        $top_dir ||= $dir;
        
        $configuration = $self->update_configuration($filename, $configuration);
        $configuration = $self->load_modules($dir, $configuration);
    }

    $top_dir ||= $directory;
    App::Followme::TopDirectory->name($top_dir);
    $self->{base_dir} = $top_dir;
    
    return $configuration;
}

#----------------------------------------------------------------------
# Load a modeule and create a new instance

sub load_modules {
    my ($self, $directory, $configuration) = @_;

    my @objects;
    foreach (@{$configuration->{module}}) {
        my $module = $_;

        if (! ref $module) {
            eval "require $module" or die "Module not found: $module\n";

            $configuration->{base_directory} = $directory;
            my %parameters = $self->update_parameters($module, $configuration);
            $_ = $module->new(\%parameters);
        }
    }
    
    return $configuration;
}

#----------------------------------------------------------------------
# Return 1 if filename passes test

sub match_file {
    my ($self, $path) = @_;
    
    return -d $path && $self->include_file($path);
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

            $self->set_configuration($configuration, $name, $value);
        }

        close($fd);
    }

    return $configuration;
}

#----------------------------------------------------------------------
# Update files in one folder

sub update_folder {
    my ($self, $directory, $configuration) = @_;
    
    # Copy the configuration so all changes are local to this sub
    $configuration = $self->copy_config($configuration);

    # Read any configuration found in this directory
    my $configuration_file = catfile($directory, $self->{configuration_file});

    if (-e $configuration_file) {
        $configuration = $self->update_configuration($configuration_file,
                                                     $configuration);
        $configuration = $self->load_modules($directory, $configuration);
    }
    
    # Run the modules mentioned in the configuration
    # Run any that return true on the subdirectories
    
    my @modules;
    foreach my $module (@{$configuration->{module}}) {
        push(@modules, $module) if $module->run($directory);
    }

    # Recurse on the subdirectories running the filtered list of modules
    
    if (@modules) {
        $configuration->{module} = \@modules;
        $self->visit($directory);
        
        while (defined(my $subdirectory = $self->next)) {
            $self->update_folder($subdirectory, $configuration);
        }
    }

    return;
}

#----------------------------------------------------------------------
# Update a module's parameters

sub update_parameters {
    my ($self, $module, $configuration) = @_;
    
    $configuration = {} unless defined $configuration;
    return %$configuration unless $module->can('parameters');
        
    my %parameters = $module->parameters();
    foreach my $field (keys %parameters) {
        $parameters{$field} = $configuration->{$field}
            if exists $configuration->{$field};
    }
    
    return %parameters;
}

1;
__END__

=encoding utf-8

=head1 NAME

App::Followme - Update a static website

=head1 SYNOPSIS

    use App::Followme;
    my $app = App::Followme->new($configuration);
    $app->run($directory);

=head1 DESCRIPTION

This is the module that is run by the followme script. It loads and runs
all the other modules. When it is run, it searches the directory path for
configuration files. The topmost file defines the top directory of the website.
It reads each configuration file it finds and then starts updating the directory
passed as an argument to run, or if no directory is passed, the directory the
followme script is run from.

Configuration file lines are organized as lines containing

    NAME = VALUE

and may contain blank lines or comment lines starting with a C<#>. Values in
configuration files are combined with those set in the files in directories
above it.

The module parameter contains the name of a module to be run on the directory
containing the configuration file and possibly its subdirectories. There may be
more than one module parameter in a module file. They are run in order, starting
with the module in the topmost configuration file. The module to be run must
have new and run methods. The module is created and run from the directory
containing the configuration file. The object is created by calling the new
method with the configuration. The run method is then called without arguments.
The run method returns a value, which if true indicates that module should be
run in the subdirectories of the current directory.

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut

