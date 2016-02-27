package App::Followme::WebData;

use 5.008005;
use strict;
use warnings;
use integer;
use lib '../..';

use base qw(App::Followme::FileData);
use App::Followme::FIO;
use App::Followme::Web;

our $VERSION = "1.16";

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($self) = @_;

    return (
            body_tag => 'primary',
            metadata_tag => 'meta',
            web_extension => 'html',
           );
}

#----------------------------------------------------------------------
# Get the html metadata from the page header

sub fetch_metadata {
    my ($self, $metadata_block) = @_;
    my $metadata = [];

    my $global = 0;
    my $title_parser = sub {
        my ($metadata, @tokens) = @_;
        my $text = web_only_text(@tokens);
        push(@$metadata, 'title', $text);
        return;
    };

    web_match_tags('<title></title>', $metadata_block,
                   $title_parser, $metadata, $global);

    $global = 1;
    my $metadata_parser = sub  {
        my ($metadata, @tokens) = @_;
        foreach my $tag (web_only_tags(@tokens)) {
            push(@$metadata, $tag->{name}, $tag->{content});
        }
        return;
    };

    web_match_tags('<meta name=* content=*>', $metadata_block,
                   $metadata_parser, $metadata, $global);

    my %metadata = @$metadata;
    return %metadata;
}

#----------------------------------------------------------------------
# Split text into metadata and content sections

sub fetch_sections {
    my ($self, $text) = @_;

    my $section = web_parse_sections($text);

    my %section;
    foreach my $section_name (qw(metadata body)) {
        my $tag = $self->{$section_name . '_tag'};
        die "Couldn't find $section_name\n" unless exists $section->{$tag};

        $section{$section_name} = $section->{$tag};
    }

    return \%section;
}

1;

=pod

=encoding utf-8

=head1 NAME

App::Followme::WebData - Read metadatafrom a web file

=head1 SYNOPSIS

    use App::Followme::WebData;
    my $obj = App::Followme::WebData->new();
    my $prototype = $obj->find_prototype($directory, 0);
    my $test = $obj->is_newer($filename, $prototype);
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

=item $str = $self->read_page($filename);

Read a fie into a string. An the entire file is read from a string, there is no
line at a time IO. This is because files are typically small and the parsing
done is not line oriented.

=item $data = $self->set_fields($directory, $filename);

The main method for getting variables. This method calls the build methods
defined in this class. Filename is the file that the variables are being
computed for. Directory is used to compute the relative url. The url computed is
relative to it.

=item $self->write_page($filename, $str);

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
