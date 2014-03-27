# NAME

App::Followme - Update a static website

# SYNOPSIS

    use App::Followme;
    my $app = App::Followme->new(\%configuration);
    $app->run($directory);

# DESCRIPTION

Updates a static website after changes. Constant portions of each page are
updated to match, text files are converted to html, and indexes are created
for new files in the archive.

The followme script is run on the directory or file passed as its argument. If
no argument is given, it is run on the current directory.

If a file is passed, the script is run on the directory the file is in. In
addition, the script is run in quick mode, meaning that only the directory
the file is in is checked for changes. Otherwise not only that directory, but
all directories below it are checked.

# INSTALLATION

First, install the App::Followme script from cpan. It will copy the
followme script to /usr/local/bin, so it will be on your search path.

    sudo cpanm App::Followme

Then create a folder to contain the new website. Run followme with the
init option in that directory

    mkdir website
    cd website
    followme --init

It will install the initial templates and configuration files. The initial
setup is configured to update pages to maintain a consistent look for the site
and to create a weblog from files placed in the archive directory. If you do not
want a weblog, just delete the archive directory and its contents.

To start creating your site, create the index page as a Markdown file, run
followme again, and edit the resulting page:

    vi index.md
    followme
    vi index.html
    

The first page will serve as a prototype for the rest of your site. When you
look at the html page, you will see that it contains comments looking like

    <!-- section content -->
    <!-- endsection content -->

These comments mark the parts of the prototype that will change from page to
page from the parts that are constant across the entire site. Everything
outside the comments is the constant portion of the prototype. When you have
more than one html page in the folder, you can edit any page, run followme,
and the other pages will be updated to match it.

So you should edit your first page and add any other files you need to create
the look of your site.

You can also use followme on an existing site. Run the command

    followme --init
    

in the top directory of your site. The init option will not overwrite any
existing files in your site. Then look at the page template it has
created:

    cat templates/page.htm

Edit the existing pages in your site to have all the section comments in this
template.

The configuration file for followme is followme.cfg in the top directory of
your site. It contains the names of the Perl modules that are run when the
followme command is run:

    run_before = App::Followme::FormatPages
    run_before = App::Followme::ConvertPages

Perl modules are run in the order they appear in the configuration file. If they
are named run\_before then they are run before modules in configuration files in
subdirectories. If they are named run\_after, they are run after modules in
configuration files in subdirectories.

[App::Followme::FormatPages](http://search.cpan.org/perldoc?App::Followme::FormatPages) runs the code that keeps the pages consistent with
the prototype. [App::Followme::ConvertPages](http://search.cpan.org/perldoc?App::Followme::ConvertPages) changes Markdown files to html
pages using a template and the prototype. The modules are run in the order that
they appear in the, configuration file. If you want to change or add to the
behavior of followme, write another module and add it to the file. Other lines
in the configuration file modify the default behavior of the modules by
overriding their default parameter values. For more information on these
parameters, see the documentation for each of the modules.

ConvertPages changes Markdown files into html files. It builds several variables
and substitutes them into the page template. The most significant variable is
body, which is the text contained in the text file after it has been converted
by Markdown. The title is built from the title of the Markdown file if one is
put at the top of the file. If the file has no title, it is built form the file
name, replacing dashes with blanks and capitalizing each word, The url and
absolute\_url are built from the html file name. A number of time variables are
built from the modification date of the text file: weekday, month, monthnum,
day, year, hour24, hour, ampm, minute, and second. To change the look of the
html page, edit the template. Only blocks inside the section comments will be in
the resulting page, editing the text outside it will have no effect on the
resulting page.

A larger website will be spread across several folders. Each folder can have its
own configuration file. If they contain modules, they will be run on that folder
and all the subfolders below it. After initialization, the website is configured
with an archive folder containing a configuration file. This file contains to
modules that implement a weblog:

    run_bedore = App::Followme::CreateNews
    run_before = App::Followme::CreateIndexes

[App::Followme::CreateNews](http://search.cpan.org/perldoc?App::Followme::CreateNews) generates an html file from the most recently
updated files in the archive directory. [App::Followme::CreateIndexes](http://search.cpan.org/perldoc?App::Followme::CreateIndexes) builds
an index file for each directory with links for all the subdirectories and html
contained in it. Templates are used to build the html files, just as with
individual pages, and the same variables are available. The template to build
the html for each file in the index is contained between

    <!-- for @loop -->
    <!--endfor -->

comments. More information on the syntax of template is in the documentation of
the [App::Followme::Module](http://search.cpan.org/perldoc?App::Followme::Module) module.

In addition to normal section blocks, there are per folder section blocks.
The contents of these blocks is kept constant across all files in a folder and
all subfolders of it. If the block is changed in one file in the folder, it will
be updated in all the other files. Per folder section blocks look like

    <!-- section in folder_name -->
    <!-- endsection -->

where folder\_name is the the folder the content is kept constant across. The
folder name is not a full path, it is the last folder in the path.

Followme is run from the folder it is invoked from if it is called with no
arguments, or if it is run with arguments, it will run on the folder passed as
an argument or the folder the file passed as an argument is contained in.
Followme looks for its configuration files in all the directories above the
directory it is run from and runs all the modules it finds in them. But they are
are only run on the folder it is run from and subfolders of it. Followme
only looks at the folder it is run from to determine if other files in the
folder need to be updated. So after changing a file, it should be run from the
directory containing the file.

When followme is run, it searches the directories above it for configuration
files. The topmost file defines the top directory of the website. It reads each
configuration file it finds and then starts updating the directory passed as an
argument to run, or if no directory is passed, the directory the followme script
is run from.

Configuration file lines are organized as lines containing

    NAME = VALUE

and may contain blank lines or comment lines starting with a `#`. Values in
configuration files are combined with those set in the files in directories
above it.

The run\_before and run\_after parameters contain the names of modules to be run
on the directory containing the configuration file and possibly its
subdirectories. There may be more than one run\_before or run\_after parameter in
a configuration file. They are run in order, starting with the modules in the
topmost configuration file. Each module to be run must have new and run methods.
An object of the module's class is created by calling the new method with the a
reference to a hash containing the configuration parameters. The run method is
then called with the directory as its argument.

# LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

Bernie Simon <bernie.simon@gmail.com>
