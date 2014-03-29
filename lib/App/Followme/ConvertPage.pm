package App::Followme::ConvertPage;
use 5.008005;
use strict;
use warnings;

use lib '../..';

use base qw(App::Followme::Module);

use Text::Markdown;
use File::Spec::Functions qw(catfile);

our $VERSION = "1.03";

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($self) = @_;
    
    return (
            text_extension => 'md',
            page_template => 'page.htm',
            empty_element_suffix => '/>',
            tab_width => 4,
            trust_list_start_value => 0,
    );
}

#----------------------------------------------------------------------
# Return all the files in a subtree (example)

sub run {
    my ($self, $directory) = @_;

    my $render = $self->make_template($directory, $self->{page_template});
    my ($filenames, $directories) = $self->visit($directory);
    
    foreach my $filename (@$filenames) {
        next unless $self->match_file($filename);

        eval {$self->convert_a_file($render, $directory, $filename)};
        warn "$filename: $@" if $@;
    }

    return if $self->{quick_update};
    
    foreach my $directory (@$directories) {
        next unless $self->search_directory($directory);
        $self->run($directory);
    }
    
    return;
}

#----------------------------------------------------------------------
# Convert a single file

sub convert_a_file {
    my ($self, $render, $directory, $filename) = @_;
    
    my $data = $self->set_fields($directory, $filename);
    my $page = $render->($data);
    
    my $new_file = $filename;
    $new_file =~ s/\.[^\.]*$/.$self->{web_extension}/;

    $self->write_page($new_file, $page);
    unlink($filename);

    return;
}

#----------------------------------------------------------------------
# Get the list of included files

sub get_included_files {
    my ($self) = @_;
    return "*.$self->{text_extension}";
}

#----------------------------------------------------------------------
# Get fields from reading the file

sub internal_fields {
    my ($self, $data, $filename) = @_;   

    my $text = $self->read_page($filename);
    die "Couldn't read\n" unless defined $text;

    $data->{body} = $self->{md}->markdown($text);
    $data = $self->build_title_from_header($data);

    return $data;
}

#----------------------------------------------------------------------
# Create markdown object and add it to self

sub setup {
    my ($self, $configuration) = @_;

    my %params;
    for my $field (qw(empty_element_suffix tab_width
                      trust_list_start_value)) {
        $params{$field} = $self->{$field};
    }

    $self->{md} = Text::Markdown->new(%params);

    return;
}

1;
__END__

=encoding utf-8

=head1 NAME

App::Followme::ConvertPage - Convert Markdown files to html

=head1 SYNOPSIS

    use App::Followme::ConvertPage;
    my $converter = App::Followme::ConvertPage->new($configuration);
    $converter->run($directory);

=head1 DESCRIPTION

If there are any markdown files in the directory, they are converted into html
files by substituting the content into a template. After the conversion the
original file is deleted. Markdown files are identified by their extension,
which by default is 'md'.

Along with the content, other variables are calculated from the file name and
modification date. Variables in the template are preceded by a sigil, most usually
a dollar sign. Thus a link would look like:

    <li><a href="$url">$title</a></li>

The variables that are calculated for each markdown file are:

=over 4

=item body

All the contents of the file, minus the title if there is one. Markdown is
called on the file's content to generate html before being stored in the body
variable. 

=item title

The title of the page is derived from the header, if one is at the front of the
file content, or the filename, if it is not.

=item time fields

The variables calculated from the modification time are: C<weekday, month,>
C<monthnum, day, year, hour24, hour, ampm, minute,> and C<second.>

=item url

The url of the html file built from the Markdown file.

=back

=head1 CONFIGURATION

The following parameters are used from the configuration:

=over 4

=item page_template

The name of the template file. The template file is either in the same
directory as the configuration file used to invoke this method, or if not
there, in the templates subdirectory.

=item text_extension 

The extension of files that are converted to web pages. The default value
is md.

The remaining parameters are passed unchanged to L<Text::Markdown>. You
should not need to change them.

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut
