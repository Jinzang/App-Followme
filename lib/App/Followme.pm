package App::Followme;

use 5.008005;
use strict;
use warnings;

use lib '..';

use base qw(App::Followme::HandleSite);

use Cwd;
use IO::File;
use File::Spec::Functions qw(rel2abs splitdir catfile no_upwards rootdir updir);

our $VERSION = "0.93";

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($pkg) = @_;
    
    my %parameters = (
                      quick_update => 0,
                      configuration_file => 'followme.cfg',
                     );

    my %base_params = $pkg->SUPER::parameters();
    %parameters = (%base_params, %parameters);

    return %parameters;
}

#----------------------------------------------------------------------
# Perform all updates on the directory

sub run {
    my ($self, $directory) = @_;

    my %configuration = $self->initialize_configuration($directory);
    $self->update_folder($directory, %configuration);

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
        last if getcwd() eq $root_dir;

        push(@configuration_files, rel2abs($self->{configuration_file}))
            if -e $self->{configuration_file};

        chdir(updir());
    }
    
    chdir($directory);
    @configuration_files = reverse @configuration_files;

    # The topmost configuration file is the top and base directory
    $self->set_directories(@configuration_files);

    # Pop the last directory if equal to the current directory
    # so it won't be double processed when we call update_folder

    my $config_file = pop(@configuration_files);
    my ($dir, $file) = $self->split_filename($config_file);
    push(@configuration_files, $config_file) if $dir ne $directory;
    
    return @configuration_files;
}

#----------------------------------------------------------------------
# Find and read the configuration files

sub initialize_configuration {
    my ($self, $directory) = @_;

    my @configuration_files = $self->find_configuration($directory);
    my %configuration = %$self;

    foreach my $filename (@configuration_files) {
        my ($dir, $file) = $self->split_filename($filename);        
        %configuration = $self->update_configuration($filename, %configuration);
        %configuration = $self->load_and_run_modules($dir, %configuration);
    }

    return %configuration;
}

#----------------------------------------------------------------------
# Load a modeule and then run it

sub load_and_run_modules {
    my ($self, $directory, %configuration) = @_;

    my @modules = @{$configuration{module}};
    delete $configuration{module};

    foreach my $module (@modules) {
        eval "require $module" or die "Module not found: $module\n";

        $configuration{base_directory} = $directory;
        my $object = $module->new(\%configuration);
        $object->run($directory);
    }
    
    return %configuration;
}

#----------------------------------------------------------------------
# Set base and top directories to the topmost configuration file

sub set_directories {
    my ($self, @configuration_files) = @_;

    die "No configuration file found\n" unless @configuration_files;

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

            if ($name eq 'module') {
                push(@modules, $value);
            } else {
                $configuration{$name} = $value;
            }
        }
        
        close($fd);
    }

    $configuration{module} = \@modules;
    return %configuration;
}

#----------------------------------------------------------------------
# Update files in one folder

sub update_folder {
    my ($self, $directory, %configuration) = @_;
    
    # Read any configuration found in this directory
    my $configuration_file = catfile($directory, $self->{configuration_file});

    if (-e $configuration_file) {
        %configuration = $self->update_configuration($configuration_file,
                                                     %configuration);
        %configuration = $self->load_and_run_modules($directory,
                                                     %configuration);
    }

    # Recurse on the subdirectories running the filtered list of modules
    
    unless ($self->{quick_update}) {
        my ($filenames, $directories) = $self->visit($directory);
        
        foreach my $subdirectory (@$directories) {
            $self->update_folder($subdirectory, %configuration);
        }
    }

    return;
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

