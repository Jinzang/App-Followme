package App::Followme::CreateIndex;
use 5.008005;
use strict;
use warnings;

use lib '../..';

use base qw(App::Followme::HandleSite);

use Cwd;
use IO::Dir;
use File::Spec::Functions qw(abs2rel rel2abs splitdir catfile no_upwards);

our $VERSION = "0.93";

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($pkg) = @_;
    
    my %parameters = (
                      index_file => 'index.html',
                      index_include => '*.html',
                      index_template => 'index.htm',
                     );

    my %base_params = $pkg->SUPER::parameters();
    %parameters = (%base_params, %parameters);

    return %parameters;
}

#----------------------------------------------------------------------
# Return all the files in a subtree (example)

sub run {
    my ($self, $directory) = @_;

    my $index_name = $self->full_file_name($directory, $self->{index_file});
    return if $self->is_newer($directory, $index_name);

    eval {$self->create_an_index($directory, $index_name)};
    warn "$index_name: $@" if $@;
    
    return;
}

#----------------------------------------------------------------------
# Create the index file for a directory

sub create_an_index {
    my ($self, $directory, $index_name) = @_;
    
    my $data = $self->set_fields($directory, $index_name);
    $data->{loop} = $self->index_data($directory);

    my $template = $self->make_template($directory, $self->{index_template});
    my $render = $self->compile_template($template);
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
    
    my ($visit_folder, $visit_file) = $self->visit($directory);

    my @index_data;
    $directory = &$visit_folder;        
    while (my $filename = &$visit_file) {
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
and directories contained in it. template. The variables described below are
substituted into a template to produce the index. Loop comments that look like

    <!-- loop -->
    <!-- endloop -->

indicate the section of the template that is repeated for each file contained
in the index. 

=over 4

=item body

All the content of the text file. The content is passed through a subroutine
before being stored in this variable. The subroutine takes one input, the
content stored as a string, and returns it as a string containing html. The
default subroutine, add_tags in this module, only surrounds paragraphs with
p tags, where paragraphs are separated by a blank line. You can supply a
different subroutine by changing the value of the configuration variable
page_converter.

=item title

The title of the page is derived from the file name by removing the filename
extension, removing any leading digits,replacing dashes with spaces, and
capitalizing the first character of each word.

=item url

The relative url of each file. 

=item time fields

The variables calculated from the modification time are: C<weekday, month,>
C<monthnum, day, year, hour24, hour, ampm, minute,> and C<second.>

=back

=head1 CONFIGURATION

The following fields in the configuration file are used:

=over 4

=item absolute

If true, urls in a page will be absolute

=item include_directories

If true, subdirectories will be included in the index

=item index_include

A comma separated list of filename patterns used to create the index

=item index_file

Name of the index file to be created

=item index_template

The path to the template file, relative to the base directory.

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut

