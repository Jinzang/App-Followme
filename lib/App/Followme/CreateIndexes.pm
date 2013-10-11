package App::Followme::CreateIndexes;
use 5.008005;
use strict;
use warnings;

use lib '../..';

use Cwd;
use IO::Dir;
use File::Spec::Functions qw(abs2rel splitdir catfile no_upwards);

use App::Followme::Common qw(compile_template make_template read_page 
                             set_variables sort_by_name top_directory
                             write_page);

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
            web_extension => 'html',
            include_directories => 1,
            include_files => '*.html',
            index_template => catfile('templates', 'index.htm'),
           );
}

#----------------------------------------------------------------------
# Convert text files into web pages

sub run {
    my ($self) = @_;

    my $index_file = "index.$self->{web_extension}";
    if ($self->changed_directory($index_file)) {
        if ($self->{options}{noop}) {
            print "$index_file\n";
    
        } else {
            eval {create_an_index($index_file)};
            warn "$index_file: $@" if $@;
        }
    }
    
    return 1;
}

#----------------------------------------------------------------------
# Has the directory changed since the index was last created

sub changed_directory {
    my ($self, $index_file) = @_;
    
    my $changed;
    if (-e $index_file) {
        my @stats = stat(getcwd());  
        my $dir_date = $stats[9];

        @stats = stat($index_file);
        my $index_date = $stats[9];
        $changed = $dir_date > $index_date;
        
    } else {
        $changed = 1;
    }

    return $changed;
}

#----------------------------------------------------------------------
# Create the index file for a directory

sub create_an_index {
    my ($self, $index_file) = @_;
    
    my $data = $self->index_data($index_file);
    my $template = make_template($self->{index_template},
                                 $self->{web_extension});

    my $sub = compile_template($template);
    my $page = $sub->($data);
 
    write_page($index_file, $page);
    return;
}

#----------------------------------------------------------------------
# Find the subdirectories of a directory

sub find_directories {
    my ($self) = @_;

    my $dir = getcwd();
    my $dd = IO::Dir->new($dir);
    die "Couldn't open $dir: $!\n" unless $dd;
        
    my @filenames;
    my $index_name = "index.$self->{web_extension}";
    
    while (defined (my $file = $dd->read())) {                   
        push(@filenames, catfile($file, $index_name));
    }
    
    $dd->close;
    return sort_by_name(no_upwards(@filenames));
}

#----------------------------------------------------------------------
# Get data for each file

sub get_file_data {
    my ($self, @filenames) = @_;
    
    my @loop_data;
    foreach my $filename (@filenames) {
        my $data = set_variables($filename);
        $data->{url} = $filename;
        push(@loop_data, $data); 
    }

    return @loop_data;
}

#----------------------------------------------------------------------
# Retrieve the data needed to build an index

sub index_data {
    my ($self, $index_file) = @_;        

    my @loop_data = $self->get_file_data($index_file);
    my $data = shift(@loop_data);
    
    my @filenames;
    if ($self->{include_directories}) {
        @filenames = $self->find_directories();
        push(@loop_data, $self->get_file_data(@filenames));
    }

    my @patterns = split(' ', $self->{include_files});
    foreach my $pattern (@patterns) {
        @filenames = sort_by_name(glob($pattern));
        push(@loop_data, $self->get_file_data(@filenames));
    }

    $data->{loop} = \@loop_data;
    return $data;
}

1;
__END__

=encoding utf-8

=head1 NAME

App::Followme::CreateIndexes - Create index file for a directory

=head1 SYNOPSIS

    use App::Followme::ConvertPages;
    my $indexer = App::Followme::CreateIndexes->new($configuration);
    $indexer->run();

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

The following fields in the configuration are used:

=over 4

=item options

A hash of the command line options passed to followme

=item web_extension

The extension used for web pages.

=item include_directories

If true, subdirectories will be included in the index

=item include_files

A space delimeted list of expressions used to create the index

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
