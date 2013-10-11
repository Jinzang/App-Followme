package App::Followme::CreateNews;
use 5.008005;
use strict;
use warnings;

use lib '../..';

use Cwd;
use IO::Dir;
use File::Spec::Functions qw(abs2rel splitdir catfile);
use App::Followme::Common qw(compile_template make_template read_page 
                             set_variables sort_by_date write_page);

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
            news_file => 'index.html',
            news_index_length => 5,
            web_extension => 'html',
            body_tag => 'content',
            news_template => catfile('templates', 'news.htm'),
           );
}

#----------------------------------------------------------------------
# Convert text files into web pages

sub run {
    my ($self) = @_;

    if ($self->{options}{noop}) {
        print "$self->{news_file}\n";
    } else {
        eval {$self->create_news_index($self->{news_file})};
        warn "$self->{news_file}: $@" if $@;
    }
    return;
}

#----------------------------------------------------------------------
# Create the index of most recent additions to the news

sub create_news_index {
    my ($self, $news_index) = @_;

    my $data = $self->recent_news_data($news_index);

    my $template = make_template($news_index);
    my $sub = compile_template($template);
    my $page = $sub->($data);
 
    write_page($news_index, $page);
    return;
}

#----------------------------------------------------------------------
# Get the more recently changed files

sub more_recent_files {
    my ($limit) = @_;
    
    my @dated_files;
    my $visitor = visitor_function();
    
    while (defined (my $filename = &$visitor)) {
        my ($dir, $root, $ext) = parse_filename($filename);

        next if $root eq 'index';
        next if $root =~ /template$/;

        my @stats = stat($filename);
        if (@dated_files < $limit || $stats[9] > $dated_files[0]->[0]) {
            shift(@dated_files) if @dated_files >= $limit;
            push(@dated_files, [$stats[9], $filename]);
            @dated_files = sort {$a->[0] <=> $b->[0]} @dated_files;
        }
    }
    
    my @recent_files = map {$_->[1]} @dated_files;
    @recent_files = reverse @recent_files if @recent_files > 1;
    return @recent_files;
}

#----------------------------------------------------------------------
# Get the data to put in the news index

sub recent_news_data {
    my ($self, $news_index) = @_;

    my @loop;
    my $limit = $self->{news_index_length};
    my $data = set_variables($news_index);

    my ($index_dir, $root, $ext) = parse_filename($news_index);
    $data->{url} = build_url($news_index, $index_dir);

    my @filenames = more_recent_files($limit);
   
    foreach my $filename (@filenames) {
        my $loopdata = set_variables($filename);
        $loopdata->{url} = build_url($filename, $index_dir);
        
        my $page = read_page($filename);
        my $blocks = parse_page($page);

        $loopdata->{body} = $blocks->{$self->{body_tag}};
        push(@loop, $loopdata);
    }

    $data->{loop} = \@loop;
    return $data;
}

#----------------------------------------------------------------------
# Return a closure that returns each file name with a specific extension

sub visitor_function {
    my ($self) = @_;
    
    my @dirlist;
    my @filelist;
    push(@dirlist, getcwd());

    return sub {
        for (;;) {
            my $file = shift(@filelist);
            return $file if defined $file;
        
            return unless @dirlist;
            my $dir = shift(@dirlist);
    
            my $dd = IO::Dir->new($dir);
            die "Couldn't open $dir: $!\n" unless $dd;
    
            # Find matching files and directories
            while (defined (my $file = $dd->read())) {
                my $path = catfile($dir, $file);
                
                if (-d $path) {
                    next if $file    =~ /^\./;
                    push(@dirlist, $path);
                    
                } else {
                    next unless $file =~ /^[^\.]+\.$self->{web_extension}$/;
                    push(@filelist, $path);
                }
            }

            $dd->close;

            @dirlist = sort(@dirlist);
            @filelist = reverse sort_by_date(@filelist);
        }
    };
}

1;
__END__

=encoding utf-8

=head1 NAME

App::Followme - Simple static web site maintenance

=head1 SYNOPSIS

    use App::Followme qw(followme);
    followme();

=head1 DESCRIPTION

Followme does three things. First, it updates the constant portions of each web
page when it is changed on any page. Second, it converts text files into html
using a template. Third, it creates indexes for files when they are placed in a
special directory, the news directory. This simplifies keeping a blog on a
static site. Each of these three actions are explained in turn.

Each html page has sections that are different from other pages and other
sections that are the same. The sections that differ are enclosed in html
comments that look like

    <!-- section name-->
    <!-- endsection name -->

and indicate where the section begins and ends. When a page is changed, followme
checks the text outside of these comments. If that text has changed. the other
pages on the site are also changed to match the page that has changed. Each page
updated by substituting all its named blocks into corresponding block in the
changed page. The effect is that all the text outside the named blocks are
updated to be the same across all the html pages.

Block text will be synchronized over all files in the folder if the begin
comment has "in folder" after the name. For example:

    <!-- section name in folder -->
    <!-- endsection name -->

Text in "in folder" blocks can be used for navigation or other sections of the
page that are constant, but not constant across the entire site.

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

=item url

The relative url of the resulting html page. 

=item time fields

The variables calculated from the modification time are: C<weekday, month,>
C<monthnum, day, year, hour24, hour, ampm, minute,> and C<second.>

=back

The template for the text file is selected by first looking for a file in
the same directory starting with the same name as the file, e.g.,
index_template.html for index.html. If not found, then a file named
template.html in the same directory is used. If neither is found, the same
search is done in the directory above the file, up to the top directory of
the site.

As a final step, followme builds indexes for each directory in the news
directory. Each directory gets an index containing links to all the files and
directories contained in it. And one index is created from all the most
recently changed files in the news directory. This index thus serves as a
weblog. Both kinds of index are built using a template. The variables are
the same as mentioned above, except that the body variable is set to the
block inside the content comment. Loop comments that look like

    <!-- loop -->
    <!-- endloop -->

indicate the section of the template that is repeated for each file contained
in the index. 

=head1 CONFIGURATION

Followme is called with the function followme, which takes one or no argument.

    followme($directory);
    
The argument is the name of the top directory of the site. If no argument is
passed, the current directory is taken as the top directory. Before calling
this function, it can be configured by calling the function configure_followme.

    configure_followme($name, $value);

The first argument is the name and the second the value of the configuration
parameter. All parameters have scalar values except for page-converter and
variable_setter, whose values are references to a function. The configuration
parameters all have default values, which are listed below with each parameter.

=over 4

=item absolute_url (C<0>)

If Perl-true, urls on generated index pages are absolute (start with a slash.)
If not, they are relative to the index page. Typically, you want absolute urls
if you have a base tag in your template and relative otherwise.

=item text_extension (C<txt>)

The extension of files that are converted to html.

=item news_index_length (C<5>)

The number of recent files to include in the weblog index.

=item news_index (C<blog.html>)

The filename of the weblog index.

=item body_tag (C<content>)

The comment name surrounding the weblog entry content.

=item variable (C<{{*}}>)

The string which indicates a variable in a template. The variable name replaces
the star in the pattern.

=item page_converter (C<add_tags>)

A reference to a function use to convert text to html. The function should
take one argument, a string containing the text to be converted and return one
value, the converted text.

=item variable_setter (C<set_variables>)

A reference to a function that sets the variables that will be substituted
into the templates, with the exception of body, which is set by page_converter.
The function takes one argument, the name of the file the variables are
generated from, and returns a reference to a hash containing the variables and
their values.

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut

