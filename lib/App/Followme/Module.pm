package App::Followme::Module;

use 5.008005;
use strict;
use warnings;
use integer;
use lib '../..';

use Cwd;
use IO::File;
use File::Spec::Functions qw(abs2rel catfile file_name_is_absolute
                             no_upwards rel2abs splitdir updir);
use App::Followme::FIO;
use App::Followme::Web;

use base qw(App::Followme::ConfiguredObject);

our $VERSION = "1.16";

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($self) = @_;

    return (
            template_file => '',
            web_extension => 'html',
            configuration_file => 'followme.cfg',
            template_directory => '_templates',
            data_pkg => 'App::Followme::WebData',
            template_pkg => 'App::Followme::Template',
           );
}

#----------------------------------------------------------------------
# Main method of all module subclasses (stub)

sub run {
    my ($self, $folder) = @_;

    my $pkg = ref $self;
    die "Run method not implemented by $pkg\n";
}

#----------------------------------------------------------------------
# Check for error and warn if found

sub check_error {
    my($self, $error, $folder) = @_;
    return 1 unless $error;

    my $pkg = ref $self;
    my $filename = $self->to_file($folder);
    warn "$pkg $filename: $error";

    return;
}

#----------------------------------------------------------------------
# Find an file to serve as a prototype for updating other files

sub find_prototype {
    my ($self, $directory, $uplevel) = @_;

    $uplevel = 0 unless defined $uplevel;
    ($directory) = fio_split_filename($directory);
    my @path = splitdir(abs2rel($directory, $self->{top_directory}));

    for (;;) {
        my $dir = catfile($self->{top_directory}, @path);

        if ($uplevel) {
            $uplevel -= 1;
        } else {
            my $pattern = "*.$self->{web_extension}";
            my $file = fio_most_recent_file($dir, $pattern);
            return $file if $file;
        }

        last unless @path;
        pop(@path);
    }

    return;
}

#----------------------------------------------------------------------
# Get the full template name

sub get_template_name {
    my ($self, $template_file) = @_;

    my $template_directory = fio_full_file_name($self->{top_directory},
                                                $self->{template_directory});

    my @directories = ($self->{base_directory}, $template_directory);

    foreach my $directory (@directories) {
        my $template_name = fio_full_file_name($directory, $template_file);
        return $template_name if -e $template_name;
    }

    die "Couldn't find template: $template_file\n";
}

#----------------------------------------------------------------------
# Read the configuration from a file

sub read_configuration {
    my ($self, $filename, %configuration) = @_;

    $configuration{''}{run_before} = [];
    $configuration{''}{run_after} = [];

    my $fd = IO::File->new($filename, 'r');
    my $class = '';

    if ($fd) {
        while (my $line = <$fd>) {
            # Ignore comments and blank lines
            next if $line =~ /^\s*\#/ || $line !~ /\S/;

            if ($line =~ /=/) {
                # Split line into name and value, remove leading and
                # trailing whitespace

                my ($name, $value) = split (/\s*=\s*/, $line, 2);
                $value =~ s/\s+$//;

                # Insert the name and value into the hash

                if ($name eq 'run_before') {
                    die "Cannot set run_before inside of $class\n" if $class;
                    push(@{$configuration{''}->{run_before}}, $value);

                } elsif ($name eq 'run_after') {
                    die "Cannot set run_after inside of $class\n" if $class;
                    push(@{$configuration{''}->{run_after}}, $value);

                } else {
                    $configuration{$class}->{$name} = $value;
                }


            } elsif ($line =~ /^\s*\[([\w:]+)\]\s*$/) {
                $class = $1;
                $configuration{$class} = {};

            } else {
                die "Bad line in config file: " . substr($line, 30) . "\n";
            }
        }

        close($fd);
    }

    return %configuration;
}

#----------------------------------------------------------------------
# Reformat the contents of an html file using one or more prototypes

sub reformat_file {
    my ($self, @files) = @_;

    my $page;
    my $section = {};
    foreach my $file (reverse @files) {
        if (defined $file) {
            if ($file =~ /\n/) {
                $page = web_substitute_sections($file, $section);
            } elsif (-e $file) {
                $page = web_substitute_sections(fio_read_page($file), $section);
            }
        }
    }

    return $page;
}

#----------------------------------------------------------------------
# Render the data contained in a file using a template

sub render_file {
    my ($self, $template_file, $file) = @_;

    $template_file = $self->get_template_name($template_file);
    my $template = fio_read_page($template_file);

    my $renderer = $self->{template}->compile($template);
    return $renderer->($self->{data}, $file);
}

#----------------------------------------------------------------------
# Convert filename to index file if it is a directory

sub to_file {
    my ($self, $file) = @_;

    $file = catfile($file, "index.$self->{web_extension}") if -d $file;
    return $file;
}

1;

=pod

=encoding utf-8

=head1 NAME

App::Followme::Module - Base class for modules invoked from configuration

=head1 SYNOPSIS

    use Cwd;
    use App::Followme::Module;
    my $obj = App::Followme::Module->new($configuration);
    my $directory = getcwd();
    $obj->run($directory);

=head1 DESCRIPTION

This module serves as the basis of all the computations
performed by App::Followme, and thus is used as the base class for all its
modules. It contains a few methods used by the modules and is not meant to
be invoked itself.

=head1 METHODS

Packages loaded as modules get a consistent behavior by subclassing
App::Foolowme:Module. It is not invoked directly. It provides methods for i/o,
handling templates and prototypes.

A template is a file containing commands and variables for making a web page.
First, the template is compiled into a subroutine and then the subroutine is
called with a metadata object as an argument to fill in the variables and
produce a web page. A prototype is the most recently modified web page in a
directory. It is combined with the template so that the web page has the same
look as the other pages in the directory.

=over 4

=item $filename = $self->find_prototype($directory, $uplevel);

Return the name of the most recently modified web page in a directory. If
$uplevel is defined, search that many directory levels up from the directory
passed as the first argument.

=item $sub = $self->make_template($filename, $template_name);

Generate a compiled subroutine to render a file by combining a prototype, the
current version of the file, and template. The prototype is the most recently
modified file in the directory containing the filename passed as the first
argument. The method first searches for the template file in the directory
containing the filename and if it is not found there, in the templates folder,
which is an object parameter,

The data supplied to the compiled subroutine should be a hash reference. fields
in the hash are substituted into variables in the template. Variables in the
template are preceded by Perl sigils, so that a link would look like:

    <li><a href="$url">$title</a></li>

The data hash may contain a list of hashes, which by convention the modules in
App::Followme name loop. Text in between for and endfor comments will be
repeated for each hash in the list and each hash will be interpolated into the
text. For comments look like

    <!-- for @loop -->
    <!-- endfor -->

=back

=head1 CONFIGURATION

The following fields in the configuration file are used in this class and every
class based on it:

=over 4


=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut
