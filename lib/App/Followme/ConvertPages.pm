package App::Followme::NewConvertPages;
use 5.008005;
use strict;
use warnings;

use lib '../..';

use base qw(App::Followme::PageHandler);

use File::Spec::Functions qw(catfile);
use App::Followme::MostRecentFile;
use App::Followme::TopDirectory;

our $VERSION = "0.93";

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($pkg) = @_;
    
    my %parameters = (
            include_files => '*.txt',
            exclude_files => 'index.html',
            page_template => catfile('templates', 'page.htm'),
           );

    my %base_params = $pkg->SUPER::parameters();
    %parameters = (%base_params, %parameters);

    return %parameters;
}

#----------------------------------------------------------------------
# Create a new page from the old (example)

sub run {
    my ($self) = @_;

    my $template = $self->make_template();
    my $sub = $self->compile_template($template);

    while (defined(my $filename = $self->next)) {
        eval {$self->convert_a_file($filename, $sub)};
        warn "$filename: $@" if $@;
    }

    return ! $self->{quick_update};    
}

#----------------------------------------------------------------------
# Convert a single file

sub convert_a_file {
    my ($self, $filename, $sub) = @_;
    
    my $data = $self->set_fields($filename);
    my $page = $sub->($data);
    
    my $new_file = $filename;
    $new_file =~ s/\.[^\.]*$/.$self->{web_extension}/;

    $self->write_page($new_file, $page);
    unlink($filename);

    return;
}

#----------------------------------------------------------------------
# Add paragraph tags to a text file

sub convert_text {
    my ($self, $text) = @_;

    my @paragraphs = split(/(\n{2,})/, $text);

    my $pre;
    my $page = '';
    foreach my $paragraph (@paragraphs) {
        $pre = $paragraph =~ /<pre/i;            

        if (! $pre && $paragraph =~ /\S/) {
          $paragraph = "<p>$paragraph</p>"
                unless $paragraph =~ /^\s*</ && $paragraph =~ />\s*$/;
        }

        $pre = $pre && $paragraph !~ /<\/pre/i;
        $page .= $paragraph;
    }
    
    return $page;
}

#----------------------------------------------------------------------
# Get the full template name (stub)

sub get_template_name {
    my ($self) = @_;
    
    my $top_directory = App::Followme::TopDirectory->name;
    return catfile($top_directory, $self->{page_template});
}

#----------------------------------------------------------------------
# Get fields from reading the file

sub internal_fields {
    my ($self, $data, $filename) = @_;   

    my $text = $self->read_page($filename);
    die "Couldn't read\n" unless defined $text;

    $data->{body} = $self->convert_text($text);
    return $data;
}

1;
__END__

=encoding utf-8

=head1 NAME

App::Followme - Simple static web site maintenance

=head1 SYNOPSIS

    use App::Followme::ConvertPages;
    my $converter = App::Followme::ConvertPages->new($configuration);
    $converter->run();

=head1 DESCRIPTION

If there are any text files in the directory, they are converted into html files
by substituting the content into a template. After the conversion the original
file is deleted. Along with the content, other variables are calculated from the
file name and modification date. Variables in the template are surrounded by
double braces, so that a link would look like:

    <li><a href="{{url}}">{{title}}</a></li>

The string which indicates a variable is configurable. The variables that are
calculated for a text file are:

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

=item time fields

The variables calculated from the modification time are: C<weekday, month,>
C<monthnum, day, year, hour24, hour, ampm, minute,> and C<second.>

=back

=head1 CONFIGURATION

The following parameters are used from the configuration:

=over 4

=item page_template

The path to the template used to create a page, relative to the top directory.

=item text_extension 

The extension of files that are converted to web pages.

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut
