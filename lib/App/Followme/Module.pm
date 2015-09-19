package App::Followme::Module;

use 5.008005;
use strict;
use warnings;
use integer;
use lib '../..';

use base qw(App::Followme::ConfiguredObject);

use File::Spec::Functions qw(abs2rel catfile splitdir);
use App::Followme::FIO;

our $VERSION = "1.16";

use constant MONTHS => [qw(January February March April May June July
                           August September October November December)];

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($self) = @_;

    return (
            body_tag => 'content',
            web_extension => 'html',
            template_directory => 'templates',
            template_pkg => 'App::Followme::Template',
           );
}

#----------------------------------------------------------------------
# Extract a web page's body from between section tags

sub build_body {
    my ($self, $data, $filename) = @_;

    my $page = fio_read_page($filename);

    if ($page) {
        my $sections = $self->{template}->parse_sections($page);
        $data->{body} = $sections->{$self->{body_tag}};
    }

    return $data;
}

#----------------------------------------------------------------------
# Build date fields from time, based on Blosxom 3

sub build_date {
    my ($self, $data, $filename) = @_;

    my $num = '01';
    my $months = MONTHS;
    my %month2num = map {substr($_, 0, 3) => $num ++} @$months;

    my $time = -e $filename ? fio_get_date($filename) : time();
    my $ctime = localtime($time);

    my @names = qw(weekday month day hour24 minute second year);
    my @values = split(/\W+/, $ctime);

    while (@names) {
        my $name = shift @names;
        my $value = shift @values;
        $data->{$name} = $value;
    }

    $data->{day} = sprintf("%02d", $data->{day});
    $data->{monthnum} = $month2num{$data->{month}};

    my $hr = $data->{hour24};
    if ($hr < 12) {
        $data->{ampm} = 'am';
    } else {
        $data->{ampm} = 'pm';
        $hr -= 12;
    }

    $hr = 12 if $hr == 0;
    $data->{hour} = sprintf("%02d", $hr);

    return $data;
}

#----------------------------------------------------------------------
# Set a flag indicating if the the filename is the index file

sub build_is_index {
    my ($self, $data, $filename) = @_;

    my ($directory, $file) = fio_split_filename($filename);
    my ($root, $ext) = split(/\./, $file);

    my $is_index = $root eq 'index' && $ext eq $self->{web_extension};
    $data->{is_index} = $is_index ? 1 : 0;

    return $data;
}

#----------------------------------------------------------------------
# Get the title from the filename root

sub build_title_from_filename {
    my ($self, $data, $filename) = @_;

    my ($dir, $file) = fio_split_filename($filename);
    my ($root, $ext) = split(/\./, $file);

    if ($root eq 'index') {
        my @dirs = splitdir($dir);
        $root = pop(@dirs) || '';
    }

    $root =~ s/^\d+// unless $root =~ /^\d+$/;
    my @words = map {ucfirst $_} split(/\-/, $root);
    $data->{title} = join(' ', @words);

    return $data;
}

#----------------------------------------------------------------------
# Get the title from the first paragraph of the page

sub build_summary {
    my ($self, $data) = @_;

    if ($data->{body}) {
        if ($data->{body} =~ m!<p[^>]*>(.*?)</p[^>]*>!si) {
            $data->{summary} = $1;
        }
    }

    return $data;
}

#----------------------------------------------------------------------
# Get the title from the page header

sub build_title_from_header {
    my ($self, $data) = @_;

    if ($data->{body}) {
        if ($data->{body} =~ s!^\s*<h(\d)[^>]*>(.*?)</h\1[^>]*>!!si) {
            $data->{title} = $2;
        }
    }

    return $data;
}

#----------------------------------------------------------------------
# Build a url from a filename

sub build_url {
    my ($self, $data, $directory, $filename) = @_;

    $data->{url} = fio_filename_to_url($directory,
                                       $filename,
                                       $self->{web_extension});

    $data->{absolute_url} = '/' . fio_filename_to_url($self->{top_directory},
                                                      $filename,
                                                      $self->{web_extension});

    my @path = splitdir(abs2rel($filename, $self->{top_directory}));
    pop(@path);

    my @breadcrumbs;
    for (;;) {
        my $filename = @path ? catfile($self->{top_directory}, @path)
                             : $self->{top_directory};

        my $breadcrumb = {};
        $breadcrumb = $self->build_title_from_filename($breadcrumb, $filename);

        $breadcrumb->{url} = '/' . fio_filename_to_url($self->{top_directory},
                                                       $filename,
                                                       $self->{web_extension});

        push (@breadcrumbs, $breadcrumb);
        last unless @path;
        pop(@path);
    }

    @breadcrumbs = reverse(@breadcrumbs);
    $data->{breadcrumbs} = \@breadcrumbs;

    return $data;
}

#----------------------------------------------------------------------
# Get fields external to file content

sub external_fields {
    my ($self, $data, $directory, $filename) = @_;

    $data = $self->build_date($data, $filename);
    $data = $self->build_title_from_filename($data, $filename);
    $data = $self->build_is_index($data, $filename);
    $data = $self->build_url($data, $directory, $filename);

    return $data;
}

#----------------------------------------------------------------------
# Find an file to serve as a prototype for updating other files

sub find_prototype {
    my ($self, $directory, $uplevel) = @_;

    $uplevel = 0 unless defined $uplevel;
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
# Get the list of excluded files

sub get_excluded_directories {
    my ($self) = @_;
    return [$self->{template_directory}];
}

#----------------------------------------------------------------------
# Get the list of excluded files

sub get_excluded_files {
    my ($self) = @_;
    return '';
}

#----------------------------------------------------------------------
# Get the list of included files

sub get_included_files {
    my ($self) = @_;

    return "*.$self->{web_extension}";
}

#----------------------------------------------------------------------
# Get the full template name

sub get_template_name {
    my ($self, $template_file) = @_;

    my @directories = ($self->{base_directory});

    push(@directories, fio_full_file_name($self->{top_directory},
                                          $self->{template_directory}));

    foreach my $directory (@directories) {
        my $template_name = fio_full_file_name($directory, $template_file);
        return $template_name if -e $template_name;
    }

    die "Couldn't find template: $template_file\n";
}

#----------------------------------------------------------------------
# Get fields from reading the file

sub internal_fields {
    my ($self, $data, $filename) = @_;

    my $ext;
    if (-d $filename) {
        $ext = $self->{web_extension};
        $filename = catfile($filename, "index.$ext");

    } else {
        ($ext) = $filename =~ /\.([^\.]*)$/;
    }

    if (defined $ext) {
        if ($ext eq $self->{web_extension}) {
            $data = $self->build_body($data, $filename);
            $data = $self->build_summary($data);
            $data = $self->build_title_from_header($data);
        }
    }

    return $data;
}

#----------------------------------------------------------------------
# Combine template with prototype and compile to subroutine

sub make_template {
    my ($self, $filename, $template_file) = @_;

    my ($directory, $base) = fio_split_filename($filename);
    undef $filename unless -e $filename;

    my $template_name = $self->get_template_name($template_file);
    my $prototype_name = $self->find_prototype($directory);

    my @filenames = grep {defined $_}
        ($prototype_name, $filename, $template_name);

    my $sub = $self->{template}->compile(@filenames);
    return $sub;
}

#----------------------------------------------------------------------
# Return true if this is an included file

sub match_file {
    my ($self, $filename) = @_;

    $self->{include_patterns} ||= fio_glob_patterns($self->get_included_files());
    $self->{exclude_patterns} ||= fio_glob_patterns($self->get_excluded_files());

    my ($dir, $file) = fio_split_filename($filename);
    return if fio_match_patterns($file, $self->{exclude_patterns});
    return unless fio_match_patterns($file, $self->{include_patterns});

    return 1;
}

#----------------------------------------------------------------------
# Check if directory should be searched

sub search_directory {
    my ($self, $directory) = @_;

    my $excluded_dirs = $self->get_excluded_directories();

    foreach my $excluded (@$excluded_dirs) {
        return if fio_same_file($directory, $excluded);
    }

    return 1;
}

#----------------------------------------------------------------------
# Set the regular expression patterns used to match a command

sub setup {
    my ($self, $configuration) = @_;

    my $template_pkg = $self->{template_pkg};
    eval "require $template_pkg" or die "Module not found: $template_pkg\n";
    $self->{template} = $template_pkg->new($configuration);

    return;
}

#----------------------------------------------------------------------
# Set the data fields for a file

sub set_fields {
    my ($self, $directory, $filename) = @_;

    my $data = {};
    $data = $self->external_fields($data, $directory, $filename);
    $data = $self->internal_fields($data, $filename);

    return $data;
}

#----------------------------------------------------------------------
# Sort pending filenames

sub sort_files {
    my ($self, $files) = @_;

    my @files = sort @$files;
    return \@files;
}

1;

=pod

=encoding utf-8

=head1 NAME

App::Followme::Module - Base class for modules invoked from configuration

=head1 SYNOPSIS

    use App::Followme::FIO;
    use App::Followme::Module;
    my $obj = App::Followme::Module->new($configuration);
    my $prototype = $obj->find_prototype($directory, 0);
    my $test = fio_is_newer($filename, $prototype);
    if ($test) {
        my $data = $obj->set_fields($directory, $filename);
        my $sub = $obj->make_template($filename, $template_name);
        my $webppage = $sub->($data);
        print $webpage;
    }

=head1 DESCRIPTION

This module contains the methods that build variables and perform template
and prototype handling. It serves as the basis of all the computations
performed by App::Followme, and thus is used as the base class for all its
modules.

=head1 METHODS

Packages loaded as modules get a consistent behavior by subclassing
App::Foolowme:Module. It is not invoked directly. It provides methods for i/o,
handling templates, and prototypes, and building the variables that are inserted
into templates.

A template is a file containing commands and variables for making a web page.
First, the template is compiled into a subroutine and then the subroutine is
called with a hash as an argument to fill in the variables and produce a web
page. A prototype is the most recently modified web page in a directory. It is
combined with the template so that the web page has the same look as the other
pages in the directory.

=over 4

=item my $data = $self->build_date($data, $filename);

The variables calculated from the modification time are: C<weekday, month,>
C<monthnum, day, year, hour24, hour, ampm, minute,> and C<second.>

=item my $data = $self->build_is_index($data, $filename);

The variable C<is_flag> is one of the filename is an index file and zero if
it is not.

=item my $data = $self->build_title_from_filename($data, $filename);

The title of the page is derived from the file name by removing the filename
extension, removing any leading digits,replacing dashes with spaces, and
capitalizing the first character of each word.

=item $data = $self->build_url($data, $filename);

Build the relative and absolute urls of a web page from a filename.

=item $filename = $self->find_prototype($directory, $uplevel);

Return the name of the most recently modified web page in a directory. If
$uplevel is defined, search that many directory levels up from the directory
passed as the first argument.

=item my $data = $self->internal_fields($data, $filename);

Compute the fields that you must read the file to calculate: title, body,
and summary

=item $test = $self->is_newer($target, @sources);

Compare the modification date of the target file to the modification dates of
the source files. If the target file is newer than all of the sources, return
1 (true).

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

=item $data = $self->set_fields($directory, $filename);

The main method for getting variables. This method calls the build methods
defined in this class. Filename is the file that the variables are being
computed for. Directory is used to compute the relative url. The url computed is
relative to it.

=item fio_write_page($filename, $str);

Write a file from a string. An the entire file is written from a string, there
is no line at a time IO. This is because files are typically small.

=item ($filenames, $directories) = $self->visit($top_directory);

Return a list of filenames and directories in a directory,

=back

=head1 CONFIGURATION

The following fields in the configuration file are used in this class and every
class based on it:

=over 4

=item base_directory

The directory the class is invoked from. This controls which files are returned. The
default value is the current directory.

=item web_extension

The extension used by web pages. This controls which files are returned. The
default value is 'html'.

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut
