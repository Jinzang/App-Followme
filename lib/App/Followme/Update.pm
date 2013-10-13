package App::Followme::Update;

use 5.008005;
use strict;
use warnings;

use lib '../..';

use Cwd;
use IO::Dir;
use IO::File;
use Clone qw(clone);
use File::Spec::Functions qw(rel2abs splitdir catfile no_upwards rootdir updir);

use App::Followme::Common qw(top_directory);

our $VERSION = "0.90";

#----------------------------------------------------------------------
# Create a new object to update a website

sub new {
    my ($pkg, $configuration) = @_;

    my $self = bless({}, $pkg);    
    my %parameters = $self->update_parameters($pkg, $configuration);
    $self->{$_} = $parameters{$_} foreach keys %parameters;
    
    return $self;
}

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($pkg) = @_;
    
    return (
            configuration_file => 'followme.cfg',
            quick_update => 0,
            );
}

#----------------------------------------------------------------------
# Perform all updates on the directory

sub run {
    my ($self, $directory) = @_;

    $directory = $self->set_directory($directory);    
    my $configuration = $self->initialize_configuration($directory);
    $self->update_folder($directory, $configuration);

    return;
}

#----------------------------------------------------------------------
# Find the configuration files above a directory

sub find_configuration {
    my ($self, $directory) = @_;

    chdir($directory);
    my $root_dir = rootdir();
    my @configuration_files;

    for (;;) {
        push(@configuration_files, rel2abs($self->{configuration_file}))
            if -e $self->{configuration_file};

        last if getcwd() eq $root_dir;
        chdir(updir());
    }
    
    chdir($directory);
    return reverse @configuration_files;
}

#----------------------------------------------------------------------
# Get the subdirectories in the current folder

sub get_subdirectories {
    my ($self) = @_;
    
    my @subdirectories;    
    my $dd = IO::Dir->new(getcwd());

    while (defined (my $file = $dd->read())) {
        push(@subdirectories, $file) if -d $file;
    }
    
    $dd->close();
    return no_upwards(@subdirectories);
}

#----------------------------------------------------------------------
# Find and read the configuration files

sub initialize_configuration {
    my ($self, $directory) = @_;

    my $top_dir;
    my $configuration = {};
    %$configuration = %$self;
    $configuration->{module} = [];

    foreach my $filename ($self->find_configuration($directory)) {
        my ($dir, $file) = $self->split_filename($filename);
        $top_dir ||= $dir;
        chdir($dir);
        
        $configuration = $self->update_configuration($filename, $configuration);
    }

    $top_dir ||= $directory;
    top_directory($top_dir);
    
    chdir($directory);
    return $configuration;
}

#----------------------------------------------------------------------
# Load a modeule if it has not already been loaded

sub load_modules {
    my ($self, $configuration) = @_;

    if (exists $configuration->{module}) {
        foreach (reverse @{$configuration->{module}}) {
            last if ref $_;
            
            my $module = $_;
            eval "require $module" or die "Module not found: $module\n";
    
            $configuration->{base_directory} = getcwd();
            my %parameters = $self->update_parameters($module, $configuration);
            my $obj = $module->new(\%parameters);

            $_ = $obj;
        }
    }
    
    return;
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
# If name passed is not directory, set a sensible default

sub set_directory {
    my ($self, $directory) = @_;
    
    if (defined $directory) {
        if (! -d $directory) {
            my $file;
            ($directory, $file) = $self->split_filename($directory);
            $self->{quick_update} = 1;
        }
        
    } else {
        $directory = getcwd();
    }

    return $directory;
}

#----------------------------------------------------------------------
# Split filename from directory

sub split_filename {
    my ($self, $filename) = @_;
    
    my @path = splitdir($filename);
    my $file = pop(@path);
    my $dir = catfile(@path);
    
    return ($dir, $file);
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

    $self->load_modules($configuration);
    return $configuration;
}

#----------------------------------------------------------------------
# Update files in one folder

sub update_folder {
    my ($self, $directory, $configuration) = @_;
    
    # Copy the configuration so all changes are local to this sub
    $configuration = clone($configuration);

    # Save the current directory so we can return when finished
    my $current_directory = getcwd();
    chdir($directory);
     
    # Read any configuration found in this directory
    $configuration = $self->update_configuration($self->{configuration_file},
                                                 $configuration)
                     if -e $self->{configuration_file};
    
    # Run the modules mentioned in the configuration
    # Run any that return true on the subdirectories
    
    my @modules;
    foreach my $module (@{$configuration->{module}}) {
        push(@modules, $module) if $module->run();
        chdir($directory);
    }

    # Recurse on the subdirectories running the filtered list of modules
    
    if (@modules) {
        $configuration->{module} = \@modules;
        my @subdirectories = $self->get_subdirectories();
    
        foreach my $subdirectory (@subdirectories) {
            $self->update_folder($subdirectory, $configuration);
        }
    }

    chdir($current_directory);
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

App::Followme::Update - Update a static website

=head1 SYNOPSIS

    use App::Followme::Update ;
    my $updater = App::Followme::Update->new($options);
    $updater->run(shift @ARGV);

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
containing the configuration file and possibly its subdirectories. It must have
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

