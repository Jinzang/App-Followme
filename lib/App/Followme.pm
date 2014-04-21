package App::Followme;

use 5.008005;
use strict;
use warnings;

use lib '..';

use base qw(App::Followme::Module);

use Cwd;
use IO::File;
use File::Spec::Functions qw(splitdir catfile);

our $VERSION = "1.08";

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($pkg) = @_;
    
    return (
            configuration_file => 'followme.cfg',
           );
}

#----------------------------------------------------------------------
# Perform all updates on the directory

sub run {
    my ($self, $directory) = @_;

    my $configuration_files = $self->find_configuration($directory);

    $self->update_folder($directory,
                         $configuration_files,
                         %$self);

    return;
}

#----------------------------------------------------------------------
# Find the configuration files above a directory

sub find_configuration {
    my ($self, $directory) = @_;

    # Push a possibly non-existent configuration file in the current
    # directory onto the list of configuration files
    
    my $config_file = catfile($directory, $self->{configuration_file});
    my @configuration_files = ($config_file);

    my @dirs = splitdir($directory);
    pop(@dirs);

    # Find configuration files in and above directory
    
    while (@dirs) {
        $config_file = catfile(@dirs, $self->{configuration_file});
        push(@configuration_files, $config_file) if -e $config_file;
        pop(@dirs);
    }

    @configuration_files = reverse @configuration_files;

    # The topmost configuration file is the top and base directory
    $self->set_directories(@configuration_files);
    
    return \@configuration_files;
}

#----------------------------------------------------------------------
# Load a modeule and then run it

sub load_and_run_modules {
    my ($self, $modules, $base_directory, $directory, %configuration) = @_;

    foreach my $module (@$modules) {
        eval "require $module" or die "Module not found: $module\n";

        $configuration{base_directory} = $base_directory;
        my $object = $module->new(\%configuration);
        $object->run($directory);
    }
    
    return;
}

#----------------------------------------------------------------------
# Set base and top directories to the topmost configuration file

sub set_directories {
    my ($self, @configuration_files) = @_;

    my ($directory, $file) = $self->split_filename($configuration_files[0]);
    $self->{base_directory} = $directory;
    $self->{top_directory} = $directory;    
    return;
}

#----------------------------------------------------------------------
# Update the configuration from a file

sub update_configuration {
    my ($self, $filename, %configuration) = @_;

    my @modules;
    $configuration{run_before} = [];
    $configuration{run_after} = [];
    
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

            if ($name eq 'run_before' || $name eq 'module') {
                push(@{$configuration{run_before}}, $value);

            } elsif ($name eq 'run_after') {
                push(@{$configuration{run_after}}, $value);

            } else {
                $configuration{$name} = $value;
            }
        }
        
        close($fd);
    }

    return %configuration;
}

#----------------------------------------------------------------------
# Update files in one folder

sub update_folder {
    my ($self, $directory, $configuration_files, %configuration) = @_;

    my $configuration_file = shift(@$configuration_files) ||
                             catfile($directory, $self->{configuration_file});

    my ($base_directory, $filename) = $self->split_filename($configuration_file);

    my ($run_before, $run_after);
    if (-e $configuration_file) {
        %configuration = $self->update_configuration($configuration_file,
                                                     %configuration);
 
        $run_before = $configuration{run_before};
        delete $configuration{run_before};
    
        $run_after = $configuration{run_after};
        delete $configuration{run_after};
    }
    
    $self->load_and_run_modules($run_before,
                                $base_directory,
                                $directory, 
                                %configuration);

    
    if (@$configuration_files) {
        $self->update_folder($directory,
                             $configuration_files,
                             %configuration);

    } elsif (! $self->{quick_update}) {
        my ($filenames, $directories) = $self->visit($directory);
        
        foreach my $subdirectory (@$directories) {
            $self->update_folder($subdirectory,
                                 $configuration_files,
                                 %configuration);
        }
    }
    
    $self->load_and_run_modules($run_after,
                                $base_directory,
                                $directory, 
                                %configuration);
    return;
}

1;
__END__

=encoding utf-8

=head1 NAME

App::Followme - Update a static website

=head1 SYNOPSIS

    use App::Followme;
    my $app = App::Followme->new(\%configuration);
    $app->run($directory);

=head1 DESCRIPTION

See L<App::Followme::Guide> for more information on how to install and configure
followme.

This class reads and processes the configuration files in a website and as a
result of that runs the modules named in them.

The configuration file for followme is followme.cfg in the top directory of
your site. It contains the names of the Perl modules that are run when the
followme command is run:

    run_before = App::Followme::FormatPages
    run_before = App::Followme::ConvertPages

Perl modules are run in the order they appear in the configuration file. If they
are named run_before then they are run before modules in configuration files in
subdirectories. If they are named run_after, they are run after modules in
configuration files in subdirectories. See L<App::Followme::Guide> for an
overview of the available modules.

A larger website will be spread across several folders. Each folder can have its
own configuration file. If they contain modules, they will be run on that folder
and all the subfolders below it.

Followme is run from the folder it is invoked from if it is called with no
arguments, or if it is run with arguments, it will run on the folder passed as
an argument or the folder the file passed as an argument is contained in.
Followme looks for its configuration files in all the directories above the
directory it is run from and runs all the modules it finds in them. But they are
are only run on the folder it is run from and subfolders of it. Followme
only looks at the folder it is run from to determine if other files in the
folder need to be updated. So after changing a file, it should be run from the
directory containing the file.

When followme is run, it searches the directories above it for configuration
files. The topmost file defines the top directory of the website. It reads each
configuration file it finds and then starts updating the directory passed as an
argument to run, or if no directory is passed, the directory the followme script
is run from.

Configuration file lines are organized as lines containing

    NAME = VALUE

and may contain blank lines or comment lines starting with a C<#>. Values in
configuration files are combined with those set in the files in directories
above it.

The run_before and run_after parameters contain the names of modules to be run
on the directory containing the configuration file and possibly its
subdirectories. There may be more than one run_before or run_after parameter in
a configuration file. They are run in order, starting with the modules in the
topmost configuration file. Each module to be run must have new and run methods.
An object of the module's class is created by calling the new method with the a
reference to a hash containing the configuration parameters. The run method is
then called with the directory as its argument.

=head1 CONFIGURATION

The following parameter is used from the configuration:

=over 4

=item configuration_file

The name of the file containing the configuration data. The default value is
followme.cfg. The followme script derives the value of this parameter from
the name of the script, so by adding a link to the script, you can have
different sets of configuration files.

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut

