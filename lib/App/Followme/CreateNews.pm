package App::Followme::CreateNews;
use 5.008005;
use strict;
use warnings;

use lib '../..';

use base qw(App::Followme::Module);

use File::Spec::Functions qw(abs2rel catfile no_upwards rel2abs splitdir);

our $VERSION = "1.07";

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($self) = @_;
    
    return (
            news_file => '../blog.html',
            news_index_file => 'index.html',
            news_index_length => 5,
            news_template => 'news.htm',
            news_index_template => 'news_index.htm',
           );
}

#----------------------------------------------------------------------
# Create a page of recent news items and indexes in each subdirectory

sub run {
    my ($self, $directory) = @_;

    eval {
        $self->create_news_indexes($self->{base_directory});
        $self->create_recent_news($self->{base_directory});
        };

    if ($@) {
        my $news_file = $self->full_file_name($self->{base_directory},
                                              $self->{news_file});
        die "$news_file: $@\n";
    }

    return;
}

#----------------------------------------------------------------------
# Create an index file

sub create_an_index {
    my ($self, $directory, $directories, $filenames) = @_;
    
    # Don't re-create index if directory and template haven't changed
    
    my $template_name = $self->get_template_name($self->{news_index_template});
    my $index_name = $self->full_file_name($directory, $self->{news_index_file});

    return if $self->is_newer($index_name,
                              $template_name,
                              @$directories,
                              @$filenames);
    
    my $data = $self->set_fields($directory, $index_name);    
    $data->{loop} = $self->index_data($directory, $directories, $filenames);

    my $render = $self->make_template($directory, $self->{news_index_template});
    my $page = $render->($data);

    $self->write_page($index_name, $page);
    return;
}

#----------------------------------------------------------------------
# Create news indexes for directory and its subdirectories

sub create_news_indexes {
    my ($self, $directory) = @_;
    
    my ($filenames, $directories) = $self->visit($directory);
    
    foreach my $subdirectory (@$directories) {
        $self->create_news_indexes($subdirectory);
    }

    $self->create_an_index($directory, $directories, $filenames);
    return;
}

#----------------------------------------------------------------------
# Create the file containing recent news

sub create_recent_news {
    my ($self, $directory) = @_;
    
    # Get the names of the more recent files

    my $file;
    my $recent_files = $self->recent_files($directory); 

    my $news_file = $self->full_file_name($directory, $self->{news_file});
    ($directory, $file) = $self->split_filename($news_file);

    my $template_name = $self->get_template_name($directory,
                                                 $self->{news_template});
    
    # Don't create news if no files have changed

    return if $self->is_newer($news_file, $template_name, @$recent_files);
    return unless @$recent_files;
    
    # Get the data for these files
    my $data = $self->recent_data($recent_files, $directory, $news_file);

    # Interpolate the data into the template and write the file
    my $render = $self->make_template($directory, $self->{news_template});
    my $page = $render->($data);

    $self->write_page($news_file, $page);
    return;
}

#----------------------------------------------------------------------
# Get the list of excluded files

sub get_excluded_files {
    my ($self) = @_;
    
    my @excluded;
    foreach my $filename ($self->{news_file}, $self->{news_index_file}) {
        my ($dir, $file) = $self->split_filename($filename);
        push(@excluded, $file);
    }
    
    return join(',', @excluded);
}

#----------------------------------------------------------------------
# Get data to be interpolated into template

sub index_data {
    my ($self, $directory, $directories, $filenames) = @_;
    
    my @index_data;
    foreach my $filename (@$directories) {
        next unless $self->search_directory($filename);
        push(@index_data, $self->set_fields($directory, $filename));
    }

    foreach my $filename (@$filenames) {
        next unless $self->match_file($filename);
        push(@index_data, $self->set_fields($directory, $filename));
    }

    return \@index_data;
}

#----------------------------------------------------------------------
# Get the more recently changed files

sub more_recent_files {
    my ($self, $directory, $filenames, $augmented_files) = @_;
           
    # Skip chcking the directory if it is older than the oldest recent file

    my $limit = $self->{news_index_length};    
    return $augmented_files if @$augmented_files >= $limit &&
        $self->is_newer($augmented_files->[0][1], $directory);

    # Add file to list of recent files if modified more recently than others

    foreach my $filename (@$filenames) {
        next unless $self->match_file($filename);

        my @stats = stat($filename);        
        if (@$augmented_files < $limit || $stats[9] > $augmented_files->[0][0]) {
    
            shift(@$augmented_files) if @$augmented_files >= $limit;
            push(@$augmented_files, [$stats[9], $filename]);
            
            @$augmented_files = sort {$a->[0] <=> $b->[0]} @$augmented_files;
        }
    }
    
    return $augmented_files;
}

#----------------------------------------------------------------------
# Get the data used to construct the index to the more recent files

sub recent_data {
    my ($self, $recent_files, $directory, $news_file) = @_;
    
   my @recent_data;
    for my $file (@$recent_files) {
        push(@recent_data, $self->set_fields($directory, $file));        
    }

    my $data = $self->set_fields($directory, $news_file);
    $data->{loop} = \@recent_data;
    return $data;
}

#----------------------------------------------------------------------
# Get a list of recently modified files

sub recent_files {
    my ($self, $directory) = @_;
    
    my $augmented_files = [];
    $augmented_files = $self->update_filelist($directory, $augmented_files);

    my @recent_files = map {$_->[1]} @$augmented_files;
    @recent_files = reverse @recent_files if @recent_files > 1;

    return \@recent_files;
}

#----------------------------------------------------------------------
# Return most recent files

sub update_filelist {
    my ($self, $directory, $augmented_files) = @_;
    
    my ($filenames, $directories) = $self->visit($directory);
    
    $augmented_files = $self->more_recent_files($directory,
                                                $filenames,
                                                $augmented_files);
    
    foreach my $subdirectory (@$directories) {
        $augmented_files = $self->update_filelist($subdirectory,
                                                  $augmented_files);
    }

    return $augmented_files;
}

1;
__END__

=encoding utf-8

=head1 NAME

App::Followme::CreateNews - Create an index with the more recent files

=head1 SYNOPSIS

    use App::Followme::CreateNews;
    my $indexer = App::Followme::CreateNews->new($configuration);
    $indexer->run($directory);

=head1 DESCRIPTION

This package creates an index for files in the current directory that contains
the text of the most recently modified files together with links to the files,
It can be used to create a basic weblog. The index is built using a template.
The template has Loop comments that look like

    <!-- for @loop -->
    <!-- endfor -->

and indicate the section of the template that is repeated for each file
contained in the index. The following variables may be used in the template:

=over 4

=item absolute_url

The absolute_url of the web page.

=item body

All the text inside the content tags in an page.

=item title

The title of the page is derived from the file name by removing the filename
extension, removing any leading digits,replacing dashes with spaces, and
capitalizing the first character of each word.

=item url

The relative url of a web page. 

=item time fields

The variables calculated from the modification time are: C<weekday, month,>
C<monthnum, day, year, hour24, hour, ampm, minute,> and C<second.>

=back

=head1 CONFIGURATION

The following fields in the configuration file are used:

=over 4

=item news_file

Name of the file containing recent news items, relative to the base directory.

=item news_index_file

Name of the index files to be created in each directory.

=item news_index_length

The number of pages to include in the index.

=item news_template

The path to the template file, relative to the top directory.

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut

