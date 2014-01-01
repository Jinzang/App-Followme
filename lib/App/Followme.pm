package App::Followme;

use 5.008005;
use strict;
use warnings;

use lib '..';

use base qw(App::Followme::HandleSite);

use Cwd;
use IO::File;
use File::Spec::Functions qw(splitdir catfile);

our $VERSION = "0.95";

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($pkg) = @_;
    
    my %parameters = (
                      quick_update => 0,
                      configuration_file => 'followme.cfg',
                     );

    my %base_params = $pkg->SUPER::parameters();
    %parameters = (%base_params, %parameters);

    return %parameters;
}

#----------------------------------------------------------------------
# Perform all updates on the directory

sub run {
    my ($self, $directory) = @_;

    my %configuration = $self->initialize_configuration($directory);
    $self->update_folder($directory, %configuration);

    return;
}

#----------------------------------------------------------------------
# Find the configuration files above a directory

sub find_configuration {
    my ($self, $directory) = @_;

    # Find configuration files in and above directory
    
    my @configuration_files;
    my @dirs = splitdir($directory);

    while (@dirs) {
        my $config_file = catfile(@dirs, $self->{configuration_file});
        push(@configuration_files, $config_file) if -e $config_file;
        pop(@dirs);
    }

    @configuration_files = reverse @configuration_files;

    # The topmost configuration file is the top and base directory
    $self->set_directories(@configuration_files);

    # Pop the last directory if equal to the current directory
    # so it won't be double processed when we call update_folder

    my $config_file = pop(@configuration_files);
    my ($dir, $file) = $self->split_filename($config_file);
    push(@configuration_files, $config_file) if $dir ne $directory;
    
    return @configuration_files;
}

#----------------------------------------------------------------------
# Find and read the configuration files

sub initialize_configuration {
    my ($self, $directory) = @_;

    my @configuration_files = $self->find_configuration($directory);
    my %configuration = %$self;

    foreach my $filename (@configuration_files) {
        my ($base_directory, $config_file) = $self->split_filename($filename);
        
        %configuration = $self->update_configuration($filename,
                                                     %configuration);

        %configuration = $self->load_and_run_modules($base_directory,
                                                     $directory,
                                                     %configuration);
    }

    return %configuration;
}

#----------------------------------------------------------------------
# Load a modeule and then run it

sub load_and_run_modules {
    my ($self, $base_directory, $directory, %configuration) = @_;

    my @modules = @{$configuration{module}};
    delete $configuration{module};

    foreach my $module (@modules) {
        eval "require $module" or die "Module not found: $module\n";

        $configuration{base_directory} = $base_directory;
        my $object = $module->new(\%configuration);
        $object->run($directory);
    }
    
    return %configuration;
}

#----------------------------------------------------------------------
# Set base and top directories to the topmost configuration file

sub set_directories {
    my ($self, @configuration_files) = @_;

    die "No configuration file found\n" unless @configuration_files;

    my ($directory, $file) = $self->split_filename($configuration_files[0]);
    $self->{base_directory} = $directory;
    $self->{top_directory} = $directory;    
    return;
}

#----------------------------------------------------------------------
# Update the configuration from a file

sub update_configuration {
    my ($self, $filename, %configuration) = @_;

    my @modules;
    my $fd = IO::File->new($filename, 'r');
    
    if ($fd) {
        while (my $line = <$fd>) {
            # Ignore comments and blank lines
            next if $line =~ /^\s*\#/ || $line !~ /\S/;

            # Split line into name and value, remove leading and
            # trailing whitespace

            my ($name, $value) = split (/\s*=\s*/, $line, 2);

            die "Bad line in config file: ($name)" unless defined $value;
            $value =~ s/\s+$//;

            # Insert the name and value into the hash

            if ($name eq 'module') {
                push(@modules, $value);
            } else {
                $configuration{$name} = $value;
            }
        }
        
        close($fd);
    }

    $configuration{module} = \@modules;
    return %configuration;
}

#----------------------------------------------------------------------
# Update files in one folder

sub update_folder {
    my ($self, $directory, %configuration) = @_;
    
    # Read any configuration found in this directory
    my $configuration_file = catfile($directory, $self->{configuration_file});

    if (-e $configuration_file) {
        %configuration = $self->update_configuration($configuration_file,
                                                     %configuration);

        %configuration = $self->load_and_run_modules($directory,
                                                     $directory,
                                                     %configuration);
    }

    # Recurse on the subdirectories
    unless ($self->{quick_update}) {
        my ($filenames, $directories) = $self->visit($directory);
        
        foreach my $subdirectory (@$directories) {
            $self->update_folder($subdirectory, %configuration);
        }
    }

    return;
}

1;
__END__

=encoding utf-8

=head1 NAME

App::Followme - Update a static website

=head1 SYNOPSIS

    use App::Followme;
    my $app = App::Followme->new(\%configuration);
    $app->run($directory);

=head1 DESCRIPTION

Updates a static website after changes. Constant portions of each page are
updated to match, text files are converted to html, and indexes are created
for new files in the archive.

The followme script is run on the directory or file passed as its argument. If
no argument is given, it is run on the current directory.

If a file is passed, the script is run on the directory the file is in. In
addition, the script is run in quick mode, meaning that only the directory
the file is in is checked for changes. Otherwise not only that directory, but
all directories below it are checked.

=head1 INSTALLATION

First, install the App::Followme script from cpan. It will copy the
followme script to /usr/local/bin, so it will be on your search path.

    sudo cpanm App::Followme

Then create a folder to contain the new website. Run followme with the
init option in that directory

    mkdir website
    cd website
    followme --init

It will install the initial templates and configuration files. The initial
setup is configured to update pages to maintain a consistant look for the site
and to create a weblog from files placed in the archive directory. If you do not
want a weblog, just delete the arcive directory and its contents.

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

Edit the existing pages in your site to heve all the section comments in this
template.

The configuration file for followme is followme.cfg in thr top directory of
your site. It contains the names of the Perl modlues that are run when the
followme command is run:

    module = App::Followme::FormatPages
    module = App::Followme::ConvertPages

FormatPages runs the code that keeps the pages consistent with the prototype.
ConvertPages changes text files to html pages using a template and the
prototype. The modules are run in the order that they appear in the,
configuration file. If you want to change or add to the behavior of followme,
write another module and add it to the file. Other lines in the configuration
file modify the default behavior of the modules by over ridding their default
parameter values. For more information on these parameters, see the
documentation for each of the modules.

ConvertPages changes Markdown files into html files. It builds several variables
and substitutes them into the page template. The most significant variable is
body, which is the text contained in the text file after it has been converted
by Markdown. The title is built from the title of the Markdown file if one is
put at the top of the file. If the file has no title, it is built form the file
name, replacing dashes with blanks and capitalizing each word, The url and
absolute_url are built from the html file name. A number of time variables are
built from the modification date of the text file: weekday, month, monthnum,
day, year, hour24, hour, ampm, minute, and second. To change the look of the
html page, edit the template. Only blocks inside the section comments will be in
the resulting page, editing the text outside it will have no effect on the
resulting page.

A larger website will be spread acrss several folders. Each folder can have its
own configuration file. If they contain modules, they will be run on that folder
and all the subfolders below it. After initialization, the website is configured
with an archive folder containing a configuration file. This file contains to
modules that implement a weblog:

    module = App::Followme::CreateNews
    module = App::Followme::CreateIndexes

CreateNews generates an html file from the most recently updated files in the
archive directory. CreateIndexes builds an index file for each directory with
links for all the subdirectories and html contained in it. Templates are used to
build the html files, just as with individual pages, and the same variables are
available. The template to build the html for each file in the index is
contained between

    <!-- loop -->
    <!--endloop -->

comments. 

In addition to normal section blocks, there are per folder section blocks.
The contents of these blocks is kept constant across all files in a folder and
all subfolders of it. If the block is changed in one file in the folder, it will
be updated in all the other files. Per folder section blocks look like

    <!-- section in folder_name -->
    <!-- endsection -->

where folder_name is the the folder the content is kept constant across. The
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

and may contain blank lines or comment lines starting with a C<#>. Values in
configuration files are combined with those set in the files in directories
above it.

The module parameter contains the name of a module to be run on the directory
containing the configuration file and possibly its subdirectories. There may be
more than one module parameter in a module file. They are run in order, starting
with the module in the topmost configuration file. The module to be run must
have new and run methods. The object is created by calling the new method with
the configuration. The run method is then called with the directory as an
argument.

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut

