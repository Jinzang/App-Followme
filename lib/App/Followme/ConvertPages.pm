package App::Followme::ConvertPages;
use 5.008005;
use strict;
use warnings;

use lib '../..';

use Cwd;
use File::Spec::Functions qw(abs2rel rel2abs splitdir catfile);
use App::Followme::Common qw(compile_template make_template
                             read_page write_page set_variables);

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
            options => {},
            base_dir => '',
            web_extension => 'html',
            text_extension => 'txt',
            page_template => catfile('templates', 'page.htm'),
           );
}

#----------------------------------------------------------------------
# Convert text files into web pages

sub run {
    my ($self) = @_;

    my $template = make_template($self->{page_template},
                                 $self->{base_dir},
                                 $self->{web_extension});
    
    my $sub = compile_template($template);
    my $pattern = "*.$self->{text_extension}";

    foreach my $filename (glob($pattern)) {
        if ($self->{options}{noop}) {
            print "$filename\n";

        } else {
            eval {$self->convert_a_file($filename, $sub)};
            warn "$filename: $@" if $@;
        }
    }

    return ! $self->{options}{quick};    
}

#----------------------------------------------------------------------
# Convert a single page

sub convert_a_file {
    my ($self, $filename, $sub) = @_;
    
    my $text = read_page($filename);
    die "Couldn't read\n" unless defined $text;

    my $data = set_variables($filename);
    $data->{body} = $self->convert_text($text);
    my $page = $sub->($data);

    my $page_name = $filename;
    $page_name =~ s/$self->{text_extension}$/$self->{web_extension}/;
    
    write_page($page_name, $page);
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

1;
__END__

=encoding utf-8

=head1 NAME

App::Followme - Simple static web site maintenance

=head1 SYNOPSIS

    use App::Followme::ConvertPages;
    my $converter = App::Followme::ConvertPages->new($configuration);
    $convertter->run();

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

=item base_dir

The base directory of the website

=item page_template

The path to the template used to create a page, relative to the base directory.

=item options

A hash holding the command line option flags.

=item text_extension 

The extension of files that are converted to web pages.

=item web_extension

The extension uesd by web pages. The default value is html

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut

