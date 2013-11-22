package App::Followme::IndexHandler;
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
                      exclude_files => 'index.html',
                     );

    my %base_params = $pkg->SUPER::parameters();
    %parameters = (%base_params, %parameters);

    return %parameters;
}

#----------------------------------------------------------------------
# Convert text files into web pages (example)

sub run {
    my ($self) = @_;

    my $index_name = "index.$self->{web_extension}";
    my $data = $self->set_fields($index_name);

    my @loop_data;
    while (defined(my $filename = $self->next)) {
        next if $filename eq $index_name;
        my $data = $self->set_fields($filename);
        push(@loop_data, $data);
    }

    $data->{loop} = \@loop_data;

    my $template = $self->make_template(rel2abs('template.htm'));

    my $sub = $self->compile_template($template);
    my $page = $sub->($data);

    $self->write_page($self->{index_file}, $page);
    
    return ! $self->{quick_update};
}

#----------------------------------------------------------------------
# Return true if this is an excluded file

sub exclude_file {
    my ($self, $filename) = @_;
    
    my $dir;
    ($dir, $filename) = $self->split_filename($filename);
    
    foreach my $pattern (@{$self->{exclude_files}}) {
        return 1 if $filename =~ /$pattern/;
    }
    
    return;
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
# Return 1 if filename passes test

sub match_file {
    my ($self, $path) = @_;
 
    return if -d $path;
    return if $path !~ /\.$self->{web_extension}$/;
    return if $self->exclude_file($path);
    
    return 1;
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

App::Followme::IndexHandler - Base class for index creation

=head1 SYNOPSIS

    use App::Followme::IndexHandler;
    my $indexer = App::Followme::CreateIndexes->new($configuration);
    $indexer->run();

=head1 DESCRIPTION

This package builds an index for a directory containing links to all the html
files contained in it. template. The variables described below are substituted
into a template to produce the index. Loop comments that look like

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

=item exclude_files

One or more filenames or patterns to exclude from the index

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut

