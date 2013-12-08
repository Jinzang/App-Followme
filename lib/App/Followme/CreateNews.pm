package App::Followme::CreateNews;
use 5.008005;
use strict;
use warnings;

use lib '../..';

use base qw(App::Followme::HandleSite);

use File::Spec::Functions qw(abs2rel catfile no_upwards rel2abs splitdir);

our $VERSION = "0.93";

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($pkg) = @_;
    
    my %parameters = (
                      news_file => '../blog.html',
                      news_index_file => 'index.html',
                      news_index_length => 5,
                      body_tag => 'content',
                      news_template => 'news.htm',
                      news_index_template => 'news_index.htm',
                     );

    my %base_params = $pkg->SUPER::parameters();
    %parameters = (%base_params, %parameters);

    return %parameters;
}

#----------------------------------------------------------------------
# Return all the files in a subtree (example)

sub run {
    my ($self, $directory) = @_;

    my $news_file = $self->full_file_name($directory, $self->{news_file});
    eval {$self->create_recent_news()};
    die "$news_file: $@\n" if $@;
    
    $self->create_all_indexes();    
    return;
}

#----------------------------------------------------------------------
# Create index pages for all directories under news file, if needed

sub create_all_indexes {
    my ($self) =  @_;

    my $directory = $self->{base_directory};
    my ($visit_folder, $visit_file) = $self->visit($self->{base_directory});

    while (my $directory = &$visit_folder) {
        my $index_name =
            $self->full_file_name($directory, $self->{news_index_file});

        if ($self->is_newer($directory, $index_name)) {
            eval {$self->create_an_index($visit_file, $directory, $index_name)};
            warn "$index_name: $@" if $@;
        }
    }

    return;
}

#----------------------------------------------------------------------
# Create an index file

sub create_an_index {
    my ($self, $visit_file, $directory, $index_name) = @_;
    
    my $data = $self->set_fields($directory, $index_name);
    $data->{loop} = $self->index_data($visit_file, $directory);

    my $template =
        $self->make_template($directory, $self->{news_index_template});
    my $render = $self->compile_template($template);
    my $page = $render->($data);

    $self->write_page($index_name, $page);
    return;
}

#----------------------------------------------------------------------
# Create the file containing recent news

sub create_recent_news {
    my ($self, $news_file) = @_;
    
    # Get the names of the more recent files

    my $recent_files = $self->recent_files($self->{base_directory}); 

    return unless @$recent_files;
    return unless $self->is_newer($recent_files->[0], $news_file);
    
    # Get the data for these files
    my $data =
        $self->recent_data($recent_files, $self->{base_directory}, $news_file);

    # interpolate the data into thr trmplate and write the file
    
    my $template =
        $self->make_template($self->{base_directory}, $self->{news_template});

    my $render = $self->compile_template($template);
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
# Get data to be interpolated into index template

sub index_data {
    my ($self, $visit_file, $directory) = @_;
    
    my @index_data;
    while (my $filename = &$visit_file) {
        push(@index_data, $self->set_fields($directory, $filename));
    }

    return \@index_data;
}

#----------------------------------------------------------------------
# Get the body field from the file

sub internal_fields {
    my ($self, $data, $filename) = @_;   
    
    my $page = $self->read_page($filename);
    
    if ($page) {
        my $blocks = $self->parse_page($page);    
        $data->{body} = $blocks->{$self->{body_tag}};
    }
    
    return $data;
}

#----------------------------------------------------------------------
# Return 1 if filename passes test

sub match_file {
    my ($self, $filename) = @_;

    my $flag;
    if (-d $filename) {
        $flag = 1;

    } else {
        $flag = $self->include_file($filename);
    }

    return  $flag;
}

#----------------------------------------------------------------------
# Get the more recently changed files

sub more_recent_files {
    my ($self, $directory, $filename, $augmented_files) = @_;
       
    # Add file to list of recent files if modified more recently than others
    
    my @stats = stat($filename);
    my $limit = $self->{news_index_length};
    
    if (@$augmented_files < $limit || $stats[9] > $augmented_files->[0][0]) {

        shift(@$augmented_files) if @$augmented_files >= $limit;
        push(@$augmented_files, [$stats[9], $filename]);
        
        @$augmented_files = sort {$a->[0] <=> $b->[0]} @$augmented_files;
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
    
    my ($visit_folder, $visit_file) = $self->visit($directory);

    my $augmented_files = [];
    while (my $dir = &$visit_folder) {
        while (my $file = &$visit_file) {
            next if -d $file;
            $augmented_files =
                $self->more_recent_files($dir, $file, $augmented_files);
        }
    }

    my @recent_files = map {$_->[1]} @$augmented_files;
    @recent_files = reverse @recent_files if @recent_files > 1;

    return \@recent_files;
}

#----------------------------------------------------------------------
# Sort a list of files so that directories are first

sub sort_files {
    my ($self, $pending_files) = @_;

    my @augmented_files;
    foreach my $filename (@$pending_files) {
        my $dir = -d $filename ? 1 : 0;
        push(@augmented_files, [$filename, $dir]);
    }

    @augmented_files = sort {$b->[1] <=> $a->[1] ||
                             $a->[0] cmp $b->[0]   } @augmented_files;
    
    @$pending_files = map {$_->[0]} @augmented_files;
    return $pending_files;
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

    <!-- loop -->
    <!-- endloop -->

and indicate the section of the template that is repeated for each file
contained in the index. The following variables may be used in the template:

=over 4

=item body

All the text inside the content tags in an page.

=item title

The title of the page is derived from the file name by removing the filename
extension, removing any leading digits,replacing dashes with spaces, and
capitalizing the first character of each word.

=item url

The relative url of an html page. 

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

