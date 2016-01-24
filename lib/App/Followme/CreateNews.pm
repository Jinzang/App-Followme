package App::Followme::CreateNews;
use 5.008005;
use strict;
use warnings;

use lib '../..';

use base qw(App::Followme::Module);

use File::Spec::Functions qw(abs2rel catfile no_upwards rel2abs splitdir);
use App::Followme::FIO;

our $VERSION = "1.16";

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($pkg) = @_;

    return (
            news_index_length => 5,
            news_template_file => 'news.htm',
            index_template_file => 'news_index.htm',
           );
}

#----------------------------------------------------------------------
# Create a page of recent news items and indexes in each subdirectory

sub run {
    my ($self, $folder) = @_;

    if ($self->{quick_mode}) {
        eval {$self->update_folder($folder)};
        $self->check_error($@, $folder);

        eval{$self->update_folder($self->{base_directory})};
        $self->check_error($@, $self->{base_directory});

    } else {
        eval{$self->update_folder($folder)};
        $self->check_error($@, $folder);
    }

    return;
}

#----------------------------------------------------------------------
# Update the index files in each directory

sub update_folder {
    my ($self, $folder) = @_;

    my $index_file = $self->to_file($folder);
    my $newest_file = $self->{data}->build('newest_file', $index_file);

    my $template_file;
    if (fio_same_file($folder, $self->{base_directory})) {
        $template_file = $self->get_template_name($self->{news_template_file});
    } else {
        $template_file = $self->get_template_name($self->{index_template_file});
    }

    unless (fio_is_newer($index_file, $template_file, @$newest_file)) {
        my $page = $self->render_file($template_file, $index_file);
        my $prototype_file = $self->find_prototype();

        $page = $self->reformat_file($prototype_file, $index_file, $page);
        fio_write_page($index_file, $page);
    }

    unless ($self->{quick_mode}) {
        my $folders = $self->{data}->build('folders', $index_file);
        foreach my $subfolder (@$folders) {
            eval {$self->update_folder($subfolder)};
            $self->check_error($@, $subfolder);
        }
    }

    return;
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
