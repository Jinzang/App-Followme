package App::Followme::CreateNews;
use 5.008005;
use strict;
use warnings;

use lib '../..';

use base qw(App::Followme::IndexHandler);

use Cwd;
use IO::Dir;
use File::Spec::Functions qw(abs2rel catfile no_upwards rel2abs splitdir);
use App::Followme::TopDirectory;

our $VERSION = "0.93";

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($pkg) = @_;
    
    my %parameters = (
                      news_file => 'index.html',
                      news_index_length => 5,
                      body_tag => 'content',
                      exclude_files => 'index.html',
                      news_template => catfile('templates', 'news.htm'),
                     );

    my %base_params = $pkg->SUPER::parameters();
    %parameters = (%base_params, %parameters);

    return %parameters;
}

#----------------------------------------------------------------------
# Convert text files into web pages

sub run {
    my ($self) = @_;

    chdir($self->{base_directory});
    eval {$self->create_news_index()};
    warn "$self->{news_file}: $@" if $@;

    return;
}

#----------------------------------------------------------------------
# Create the index of most recent additions to the news

sub create_news_index {
    my ($self) = @_;

    my $data = $self->index_data();
    my $template = $self->make_template($self->{news_template});

    my $sub = $self->compile_template($template);
    my $page = $sub->($data);

    my $news_file = $self->news_file_name();
    $self->write_page($news_file, $page);

    return;
}

#----------------------------------------------------------------------
# Get the full template name (stub)

sub get_template_name {
    my ($self) = @_;
    
    my $top_directory = App::Followme::TopDirectory->name;
    return catfile($top_directory, $self->{news_template});
}

#----------------------------------------------------------------------
# Retrieve the data needed to build an index

sub index_data {
    my ($self) = @_;        


    my $limit = $self->{news_index_length};
    my @filenames = $self->more_recent_files($limit);

    my @loop_data;
    my $data = $self->set_fields(rel2abs($self->{news_file}));

    foreach my $filename (@filenames) {
        my $data = $self->set_fields($filename);
        push(@loop_data, $data);
    }

    $data->{loop} = \@loop_data;
    return $data;
}

#----------------------------------------------------------------------
# Get the body field from the file

sub internal_fields {
    my ($self, $data, $filename) = @_;   
    
    my $page = $self->read_page($filename);
    
    if ($page) {
        my $decorated = 0;
        my $blocks = $self->parse_page($page, $decorated);    
        $data->{body} = $blocks->{$self->{body_tag}};
    }
    
    return $data;
}

#----------------------------------------------------------------------
# Return 1 if folder passes test

sub match_folder {
    my ($self, $path) = @_;
    return 1;
}

#----------------------------------------------------------------------
# Get the more recently changed files

sub more_recent_files {
    my ($self, $limit) = @_;
    
    my @dated_files;
    while (defined (my $filename = $self->next)) {
         
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
# Construct news file name. Name is relative to the base directory

sub news_file_name {
    my ($self) = @_;

    my @dirs = splitdir($self->{base_directory});
    push(@dirs, splitdir($self->{news_file}));
    
    return catfile(@dirs);  
}

1;
__END__

=encoding utf-8

=head1 NAME

App::Followme::CreateNews - Create an index with the more recent files

=head1 SYNOPSIS

    use App::Followme::CreateNews;
    my $indexer = App::Followme::CreateNews->new($configuration);
    $indexer->run();

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

=item absolute

If true, urls in a page will be absolute

=item body_tag

The the name of the tag pair containing the body text.

=item base_directory

The directory containing the configuration file. This directory is searched to
create the index.

=item exclude_files

One or more filenames or patterns to exclude from the index

=item news_file

Name of the news index file to be created, relative to the base directory.

=item news_index_length

The number of pages to include in the index.

=item news_template

The path to the template file, relative to the top directory.

=item web_extension

The extension used for web pages. Pages with this extension are considered for
inclusion in the index.

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut

