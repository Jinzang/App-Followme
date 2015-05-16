package App::Followme::CreateIndex;
use 5.008005;
use strict;
use warnings;

use lib '../..';

use base qw(App::Followme::Module);

use Cwd;
use IO::Dir;
use File::Spec::Functions qw(abs2rel rel2abs splitdir catfile no_upwards);

our $VERSION = "1.12";

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($self) = @_;

    return (
            index_file => 'index.html',
            index_include => 'html',
            index_template => 'index.htm',
           );
}

#----------------------------------------------------------------------
#  Create an index to all files in a directory with a specified extension

sub run {
    my ($self, $directory) = @_;

    my $index_name = $self->full_file_name($directory, $self->{index_file});
    my $template_name = $self->get_template_name($self->{index_template});

    my $pattern = $self->get_included_files();
    my $filename = $self->most_recent_file($directory, $pattern);

    return if $self->is_newer($index_name, $template_name, $filename);

    eval {$self->create_an_index($directory, $index_name)};
    warn "$index_name: $@" if $@;

    return;
}

#----------------------------------------------------------------------
# Build a url from a filename

sub build_url {
    my ($self, $data, $directory, $filename) = @_;

    $data->{url} = $self->filename_to_url($directory,
                                          $filename,
                                        );

    $data->{absolute_url} = '/' . $self->filename_to_url($self->{top_directory},
                                                         $filename,
                                                        );

    return $data;
}

#----------------------------------------------------------------------
# Create the index file for a directory

sub create_an_index {
    my ($self, $directory, $index_name) = @_;

    my $data = $self->set_fields($directory, $index_name);
    $data->{loop} = $self->index_data($directory);

    my $render = $self->make_template($index_name, $self->{index_template});
    my $page = $render->($data);

    $self->write_page($index_name, $page);
    return;
}

#----------------------------------------------------------------------
# Get the list of excluded files

sub get_excluded_files {
    my ($self) = @_;

    my ($dir, $file) = $self->split_filename($self->{index_file});
    return $file;
}

#----------------------------------------------------------------------
# Get the list of included files

sub get_included_files {
    my ($self) = @_;
    return $self->{index_include};
}

#----------------------------------------------------------------------
# Get data to be interpolated into template

sub index_data {
    my ($self, $directory) = @_;

    my ($filenames, $directories) = $self->visit($directory);

    my @index_data;
    foreach my $filename (@$filenames) {
        next unless $self->match_file($filename);
        push(@index_data, $self->set_fields($directory, $filename));
    }

    return \@index_data;
}

1;
__END__

=encoding utf-8

=head1 NAME

App::Followme::CreateIndex - Create index file for a directory

=head1 SYNOPSIS

    use App::Followme::CreateIndex;
    my $indexer = App::Followme::CreateIndex->new($configuration);
    $indexer->run($directory);

=head1 DESCRIPTION

This package builds an index for a directory containing links to all the files
contained in it with the specified extensions. The variables described below are
substituted into a template to produce the index. Loop comments that look like

    <!-- for @loop -->
    <!-- endfor -->

indicate the section of the template that is repeated for each file contained
in the index.

=over 4

=item absolute_url

The absolute_url of the web page.

=item body

If a file is a web (html) file, the body is all the text inside the content tags
in an page.

=item title

If the file is a web (html) file, the title is the text contained in the header
tags at the top of the page. if not, the title of the page is derived from the
file name by removing the filename extension, removing any leading
digits,replacing dashes with spaces, and capitalizing the first character of
each word.

=item url

The relative url of each file.

=item time fields

The variables calculated from the modification time are: C<weekday, month,>
C<monthnum, day, year, hour24, hour, ampm, minute,> and C<second.>

=back

=head1 CONFIGURATION

The following fields in the configuration file are used:

=over 4

=item index_file

Name of the index file to be created

=item index_include

A comma separated list of filename patterns used to create the index

=item index_template

The name of the template file. The template file is either in the same
directory as the configuration file used to invoke this method, or if not
there, in the templates subdirectory.

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut
