package App::Followme::NewCreateIndexes;
use 5.008005;
use strict;
use warnings;

use lib '../..';

use base qw(App::Followme::PageHandler);

use Cwd;
use IO::Dir;
use File::Spec::Functions qw(abs2rel rel2abs splitdir catfile no_upwards);
use App::Followme::TopDirectory;

our $VERSION = "0.93";

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($pkg) = @_;
    
    my %parameters = (
                      include_directories => 1,
                      index_file => 'index.html',
                      include_files => '*.html',
                      exclude_files => 'index.html',
                      index_template => catfile('templates', 'index.htm'),
                     );

    my %base_params = $pkg->SUPER::parameters();
    %parameters = (%base_params, %parameters);

    return %parameters;
}

#----------------------------------------------------------------------
# Convert text files into web pages

sub run {
    my ($self) = @_;

    if ($self->changed_directory()) {
        eval {$self->create_an_index()};
        warn "$self->{index_file}: $@" if $@;
    }
    
    return ! $self->{quick_update};
}

#----------------------------------------------------------------------
# Has the directory changed since the index was last created

sub changed_directory {
    my ($self) = @_;
    
    my $changed;
    if (-e $self->{index_file}) {
        my @stats = stat(getcwd());  
        my $dir_date = $stats[9];

        @stats = stat($self->{index_file});
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
    my ($self) = @_;
    
    my $data = $self->index_data();
    my $template = $self->make_template($self->{index_template});

    my $sub = $self->compile_template($template);
    my $page = $sub->($data);
 
    $self->write_page($self->{index_file}, $page);
    return;
}

#----------------------------------------------------------------------
# Return true if this is an excluded file

sub exclude_file {
    my ($self, $filename) = @_;
    
    foreach my $pattern (@{$self->{exclude_files}}) {
        return 1 if $filename =~ /$pattern/;
    }
    
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
        next unless -d $file && no_upwards($file);
        push(@filenames, catfile($file, $index_name));
    }
    
    $dd->close;
    return sort_by_name(@filenames);
}

#----------------------------------------------------------------------
# Get the full template name (stub)

sub get_template_name {
    my ($self) = @_;
    
    my $top_directory = App::Followme::TopDirectory->name;
    return catfile($top_directory, $self->{index_template});
}

#----------------------------------------------------------------------
# Map filename globbing metacharacters onto regexp metacharacters

sub glob_pattern {
    my ($self, $pattern) = @_;

    return '' if $pattern eq '*';

    my $start;
    if ($pattern =~ s/^\*//) {
        $start = '';
    } else {
        $start = '^';
    }

    my $finish;
    if ($pattern =~ s/\*$//) {
        $finish = '';
    } else {
        $finish = '$';
    }

	$pattern =~ s/\./\\./g;
	$pattern =~ s/\*/\.\*/g;
	$pattern =~ s/\?/\.\?/g;

    return $start . $pattern . $finish;
}

#----------------------------------------------------------------------
# Retrieve the data needed to build an index

sub index_data {
    my ($self) = @_;        

    my $data = $self->set_fields(rel2abs($self->{index_file}));

    my @loop_data;
    my $index_name = "index.$self->{web_extension}";
    
    while (defined(my $filename = $self->next)) {
        $filename = catfile($filename, $index_name) if -d $filename;
        my $data = $self->set_fields($filename);
        push(@loop_data, $data);
    }

    $data->{loop} = \@loop_data;
    return $data;
}

#----------------------------------------------------------------------
# Return 1 if filename passes test

sub match_file {
    my ($self, $filename) = @_;

    my $flag;
    if (-d $filename) {
        $flag = $self->{include_directories};

    } else {
        my $dir;
        ($dir, $filename) = $self->split_filename($filename);
        my $pattern = $self->glob_pattern($self->{include_files});

        $flag = $filename =~ /$pattern/ && ! $self->exclude_file($filename);
    }

    return  $flag;
}

#----------------------------------------------------------------------
# Return 1 if folder passes test

sub match_folder {
    my ($self, $path) = @_;
    return;
}

#----------------------------------------------------------------------
# Set up non-configured fields in the object

sub setup {
    my ($self) = @_;
    
    $self->SUPER::setup();
    my @excluded_files = split(/\s*,\s*/, $self->{exclude_files});

    my @patterns;
    foreach my $excluded_file (@excluded_files) {
        my $pattern = $self->glob_pattern($excluded_file);
        push(@patterns, $pattern);
    }

    $self->{exclude_files} = \@patterns;
    return;
}

#----------------------------------------------------------------------
# Sort a list of files so that directories are first

sub sort_files {
    my ($self) = @_;

    my @augmented_files;
    foreach my $filename (@{$self->{pending_files}}) {
        my $dir = -d $filename ? 1 : 0;
        push(@augmented_files, [$filename, $dir]);
    }

    @augmented_files = sort {$b->[1] <=> $a->[1] ||
                             $a->[0] cmp $b->[0]   } @augmented_files;
    
    @{$self->{pending_files}} = map {$_->[0]} @augmented_files;
    return;
}

#----------------------------------------------------------------------
# Split filename from directory

sub split_filename {
    my ($self, $filename) = @_;
    
    $filename = rel2abs($filename);
    my @path = splitdir($filename);
    my $file = pop(@path);
    
    my @new_path;
    foreach my $dir (@path) {
        if (no_upwards($dir)) {
            push(@new_path, $dir);
        } else {
            pop(@new_path);
        }
    }
    
    my $new_dir = catfile(@new_path);
    return ($new_dir, $file);
}

1;
__END__

=encoding utf-8

=head1 NAME

App::Followme::CreateIndexes - Create index file for a directory

=head1 SYNOPSIS

    use App::Followme::CreateIndexes;
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

The following fields in the configuration file are used:

=over 4

=item absolute

If true, urls in a page will be absolute

=item exclude_files

One or more filenames or patterns to exclude from the index

=item include_directories

If true, subdirectories will be included in the index

=item include_files

A space delimited list of expressions used to create the index

=item index_file

Name of the index file to be created

=item index_template

The path to the template file, relative to the base directory.

=item quick_update

Only create index for current directory

=item web_extension

The extension used for web pages.

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut

