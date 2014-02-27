package App::Followme::UploadSite;

use 5.008005;
use strict;
use warnings;

use lib '..';

use base qw(App::Followme::EveryFile);

use Cwd;
use IO::File;
use Digest::MD5 qw(md5_hex);
use File::Spec::Functions qw(abs2rel splitdir catfile);

our $VERSION = "0.97";

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($pkg) = @_;
    
    my %parameters = (
                      hash_file => 'uploadme.hash',
                      state_dir => 'state',
                      target_date => 0,
                      no_ftp => 0,
                      ftp_url => '',
                      ftp_directory => '',
                     );

    my %base_params = $pkg->SUPER::parameters();
    %parameters = (%base_params, %parameters);

    return %parameters;
}

#----------------------------------------------------------------------
# Perform all updates on the directory

sub run {
    my ($self, $directory) = @_;

    $self->ftp_open();
    
    my $remote = {};
    my ($hash, $local) = $self->get_state();
    $self->update_folder($self->{top_dir}, $hash, $local, $remote);
    $self->ftp_delete($local);
    
    $self->write_hash_file($hash);
    $self->ftp_close();
    
    return;
}

#----------------------------------------------------------------------
# Compute checksum for a file

sub checksum_file {
    my ($self, $filename) = @_;    

    my $md5 = Digest::MD5->new;
    
    my $fd = IO::File->new($filename, 'r');
    return '' unless $fd;
    
    foreach my $line (<$fd>) {
        $md5->add($line);        
    }

    close($fd);

    return $md5->hexdigest;
}

#----------------------------------------------------------------------
# Close the ftp connection

sub ftp_close {
    my ($self) = @_;    
    return if $self->{no_ftp};

    $self->{ftp}->quit();
    undef $self->{ftp};
    
    return;
}

#----------------------------------------------------------------------
# Write a file to the remote site, creating any directories needed

sub ftp_delete {
    my ($self, $local) = @_;
    return if $self->{no_ftp};
    
    foreach my $filename (keys %$local) {
        $filename = abs2rel($filename, $self->{top_dir});
        my @path = splitdir($filename);
        $filename = join('/', @path);
        $self->{ftp}->delete($filename);
    }
    
    return;    
}

#----------------------------------------------------------------------
# Open the ftp connection

sub ftp_open {
    my ($self) = @_;
    return if $self->{no_ftp};

    my $ftp = Net::FTP->new($self->{ftp_url})
        or die "Cannot connect to $self->{ftp_url}: $@";
 
    my ($user, $word) = $self->read_word(); #TODO
    $ftp->login($user, $word)
        or die "Cannot login ", $ftp->message;
 
    $ftp->cwd($self->{ftp_directory})
        or die "Cannot change working directory ", $ftp->message;

    $self->{ftp} = $ftp;
    return;
}

#----------------------------------------------------------------------
# Write a file to the remote site, creating any directories needed

sub ftp_write {
    my ($self, $filename, $remote) = @_;
    return if $self->{no_ftp};

    $filename = abs2rel($filename, $self->{top_dir});
    my @path = splitdir($filename);
    $filename = join('/', @path);
    pop(@path);
    
    if ($self->{ftp}->size($filename)) {
        $self->{ftp}->delete($filename);

    } else {
        my $dir = join('/', @path);
        if (! $remote->{$dir}) {
            if (! $self->{ftp}->size($dir)) {
                $self->{ftp}->mkdir($dir, 1);
            }
        }
    }
    
    $self->{ftp}->put($filename);
    
    while (@path) {
        my $dir = join('/', @path);
        $remote->{$dir} = 1;
        pop(@path);
    }

    return;
}

#----------------------------------------------------------------------
# Get the state of the site, contained in the hash file

sub get_state {
    my ($self) = @_;

    my $hash_file = catfile($self->{top_dir},
                            $self->{state_dir},
                            $self->{hash_file});

    if (-e $hash_file) {
        my @stats = stat($hash_file);  
        $self->{target_date} = $stats[9];
    }

    my $hash = $self->read_hash_file($hash_file);
    my %local = map {$_ => 1} keys %$hash;
    
    return ($hash, \%local);
}

#----------------------------------------------------------------------
# Read the hash for each file on the site from a file

sub read_hash_file {
    my ($self, $filename) = @_;

    my %hash;
    my $fd = IO::File->new($filename, 'r');
    
    if ($fd) {
        while (my $line = <$fd>) {
            chomp $line;
            my ($name, $value) = split (/\t/, $line, 2);
            die "Bad line in hash file: ($name)" unless defined $value;

            $hash{$name} = $value;
        }
        
        close($fd);
    }

    return \%hash;
}

#----------------------------------------------------------------------
# Update files in one folder

sub update_folder {
    my ($self, $directory, $hash, $local, $remote) = @_;
    
    my ($filenames, $directories) = $self->visit($directory);
        
    foreach my $filename (@$filenames) {
        my $name = abs2rel($filename, $self->{top_dir});
        $name = join('/', splitdir($name));                
        delete $local->{$name} if exists $local->{$name};

        if ($self->{quick_update}) {
            my @stats = stat($filename);  
            next if $self->{target_date} > $stats[9];
        }

        my $value = $self->checksum_file($filename);

        if (! exists $hash->{$name} || $hash->{$name} eq $value) {
            $hash->{$name} = $value;
            $self->ftp_write($filename, $remote);
        }
    }
    
    foreach my $subdirectory (@$directories) {
        $self->update_folder($subdirectory, $hash, $local, $remote);
    }

    return;
}

#----------------------------------------------------------------------
# Write the hash back to a file

sub write_hash_file {
    my ($self, $hash) = @_;

    my $filename = catfile($self->{top_dir}, $self->{hash_file});
    my $fd = IO::File->new($filename, 'r');
    die "Couldn't write hash file: $filename" unless $fd;
    
    while (my ($name, $value) = each(%$hash)) {
        print $fd "$name\t$value\n";
    }
    
    close($fd);
    return;
}

1;
__END__

=encoding utf-8

=head1 NAME

App::Followme::Uploadme - Upload changed and new files

=head1 SYNOPSIS

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

    module = App::Followme::FormatPages
    module = App::Followme::ConvertPages

L<App::Followme::FormatPages> runs the code that keeps the pages consistent with
the prototype. L<App::Followme::ConvertPages> changes Markdown files to html
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
absolute_url are built from the html file name. A number of time variables are
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

    module = App::Followme::CreateNews
    module = App::Followme::CreateIndexes

L<App::Followme::CreateNews> generates an html file from the most recently
updated files in the archive directory. L<App::Followme::CreateIndexes> builds
an index file for each directory with links for all the subdirectories and html
contained in it. Templates are used to build the html files, just as with
individual pages, and the same variables are available. The template to build
the html for each file in the index is contained between

    <!-- for @loop -->
    <!--endfor -->

comments. More information on the syntax of template is in the documentation of
the L<App::Followme::HandleSite> module.

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

