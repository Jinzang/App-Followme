package App::Followme::Update;

use 5.008005;
use strict;
use warnings;

use Cwd;
use IO::Dir;
use IO::File;
use File::Spec::Functions qw(rel2abs abs2rel splitdir catfile);

our $VERSION = "0.90";

#----------------------------------------------------------------------
# Create a new object to update a website

sub new {
    my ($pkg, $configuration) = @_;
    
    my %self = ($pkg->parameters(), %$configuration); 
    return bless(\%self, $pkg);
}

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($pkg) = @_;
    
    return (
            configuration_file => 'followme.cfg',
            modules => [
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
    my $dd = IO::Dir->(getcwd());

    while (defined (my $file = $dd->read())) {
        next if $file eq '.' || $file eq '..';
        push(@subdirectories, $file) if -d $file;
    }
    
    return \@subdirectories;
}

#----------------------------------------------------------------------
# Find and read the configuration files

sub initialize_configuration {
    my ($self, $directory) = @_;

    my $configuration = {};
    %$configuration = %$self;
    $directory = rel2abs($directory);
    my @path = splitdir($directory);

    my @dir;
    while (defined(my $path = shift(@path))) {
        push(@dir, $path);
        my $filename = catfile(@dir, $self->{configuration_file});
        next unless -e $filename;

        $self->{base_dir} = catfile(@dir) unless exists $self->{base_dir};
        $configuration = $self->update_configuration($filename, $configuration);
    }

    return $configuration;
}

#----------------------------------------------------------------------
# Load a modeule if it has not already been loaded

sub load_module {
    my ($self, $module, $configuration) = @_;

    my $obj;
    if (ref $module) {
        $obj = $module;
    } else {
        eval "require $module" or die "Module not found: $module\n";
        $obj = $module->new($configuration);
    }
    
    return $obj;
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

            if (! exists $configuration->{$name}) {
                $configuration->{$name} = $value;

            } elsif (ref $configuration->{$name} eq 'ARRAY') {
                push(@{$configuration->{$name}}, $value);

            } else {
                $configuration->{$name} = [$configuration->{$name}, $value];
            }
        }

        close($fd);
    }

    return $configuration;
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
    
    my $modules = $configuration->{modules};
    foreach (@$modules) {
        $_ = $self->load_module($_, $configuration);
        $_->run();
    }
    
    my $subdirectories = $self->get_subdirectories();
    foreach my $subdirectory (@$subdirectories) {
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

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut

