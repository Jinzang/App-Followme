# NAME

App::Followme - Simple static web site maintenance

# SYNOPSIS

    use App::Followme qw(followme);
    followme();

# DESCRIPTION

Followme does three things. First, it updates the constant portions of each web
page when it is changed on any page. Second, it converts text files into html
using a template. Third, it creates indexes for files when they are placed in a
special directory, the archive directory. This simplifies keeping a blog on a
static site. Each of these three actions are explained in turn.

Each html page has sections that are different from other pages and other
sections that are the same. The sections that differ are enclosed in html
comments that look like

    <!-- begin name-->
    <!-- end name -->

and indicate where the section begins and ends. When a page is changed, followme
checks the text outside of these comments. If that text has changed. the other
pages on the site are also changed to match the page that has changed. Each page
updated by substituting all its named blocks into corresponding block in the
changed page. The effect is that all the text outside the named blocks are
updated to be the same across all the html pages.

If there are any text files in the directory, they are converted into html files
by substituting the content into a template. After the conversion the original
file is deleted. Along with the content, other variables are calculated from the
file name and modification date. Variables in the template are surrounded by
double braces, so that a link would look like:

    <li><a href="{{url}}">{{title}}</a></li>

The string which indicates a variable is configurable. The variables that are
calculated for a text file are:

- body

    All the content of the text file. The content is passed through a subroutine
    before being stored in this variable. The subroutine takes one input, the
    content stored as a string, and returns it as a string containing html. The
    default subroutine, add\_tags in this module, only surrounds paragraphs with
    p tags, where paragraphs are separated by a blank line. You can supply a
    different subroutine by changing the value of the configuration variable
    page\_converter.

- title

    The title of the page is derived from the file name by removing the filename
    extension, removing any leading digits,replacing dashes with spaces, and
    capitalizing the first character of each word.

- url

    The relative url of the resulting html page. 

- time fields

    The variables calculated from the modification time are: weekday, month,
    monthnum, day, year, hour24, hour, ampm, minute, and second.

The template for the text file is selected by first looking for a file in
the same directory starting with the same name as the file, e.g.,
index\_template.html for index.html. If not found, then a file named
template.html in the same directory is used. If neither is found, the same
search is done in the directory above the file, up to the top directory of
the site.

As a final step, followme builds indexes for each directory in the archive
directory. Each directory gets an index containing links to all the files and
directories contained in it. And one index is created from all the most
recently changed files in the archive directory. This index thus serves as a
weblog. Both kinds of index are built using a template. The variables are
the same as mentioned above, except that the body variable is set to the
block inside the content comment. Loop comments that look like

    <!-- loop -->
    <!-- endloop -->

indicate the section of the template that is repeated for each file contained
in the index. 

# CONFIGURATION

Followme is called with the function followme, which takes one or no argument.

    followme($directory);
    

The argument is the name of the top directory of the site. If no argument is
called, the current directory is taken as the top directory. Before calling
this function, it can be configured by calling the function configure\_followme.

    configure_followme($name, $value);

The first argument is the name and the second the value of the configuration
parameter. All parameters have scalar values except for page-converter, whose
value is a reference to a function. The configuration parameters all have default
values, which are listed below with each parameter.

- checksum\_file (followme.md5)

    The name of the file containing the checksum of the constant parts of an html
    page. It's used to see if the file has changed.

- text\_extension (txt)

    The extension of files that are converted to html.

- archive\_index\_length (5)

    The number of recent files to include in the weblog index.

- archive\_index (blog.html)

    The filename of the weblog index.

- archive\_directory (archive)

    The name of the directory containing the weblog entries.

- body\_tag (content)

    The comment name surrounding the weblog entry content.

- variable ({{\*}})

    The string which indicates a variable in a template. The variable name replaces
    the star in the pattern.

- page\_converter (add\_tags)

    A reference to a function use to convert text to html. The function should
    take one argument, a string containing the text to be converted and return one
    value, the converted text.

- variable\_setter (set\_variables)

    A reference to a function that sets the variables that will be substituted
    into the templates, with the exception of body, which is set by page\_converter.
    The function takes one argument, the name of the file the variables are
    generated from, and returns a reference to a hash containing the variables and
    their values.

# LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

Bernie Simon <bernie.simon@gmail.com>
