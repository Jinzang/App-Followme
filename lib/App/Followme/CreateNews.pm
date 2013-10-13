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
            absolute => 0,
            base_directory => '',
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

    eval {$self->create_news_index()};
    warn "$self->{news_file}: $@" if $@;

    return;
}

#----------------------------------------------------------------------
# Create the index of most recent additions to the news

sub create_news_index {
    my ($self) = @_;

    my $data = $self->recent_news_data();

    my $template = make_template($self->{news_file});
    my $sub = compile_template($template);
    my $page = $sub->($data);
 
    write_page($self->{news_file}, $page);
    return;
}

#----------------------------------------------------------------------
# Get the more recently changed files

sub more_recent_files {
    my ($self, $limit) = @_;
    
    my @dated_files;
    my $visitor = visitor_function();
    
    while (defined (my $filename = &$visitor)) {
        next if $filename eq $self->{news_file};
        
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
    my ($self) = @_;

    my @loop;
    my $limit = $self->{news_index_length};
    my $data = set_variables($self->{news_file},
                             $self->{web_extension},
                             $self->{absolute});

    my @filenames = $self->more_recent_files($limit);
   
    foreach my $filename (@filenames) {
        my $loopdata = set_variables($filename,
                                     $self->{web_extension},
                                     $self->{absolute});
        
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

App::Followme::CreateNews - Create an index with the more recent files

=head1 SYNOPSIS

    use App::Followme::CreateNew;
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
            news_file => 'index.html',
            news_index_length => 5,


=head1 CONFIGURATION

The following fields in the configuration file are used:

=over 4

=item absolute

If true, urls in a page will be absolute

=item body_tag

The the name of the tag pair containing the body text.

=item base_directory

The directory containig the configuration file. This directory is searched to
create the index.

=item news_file

Name of the news index file to be created, relative to the base directory.

=item news_index_length

The number of pages to include in the index.

=item news_template

The path to the template file, relative to the top directory.

=item web_extension

The extension used for web pages. Pages with this extension are considerd for
inclusion in the index.

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut

