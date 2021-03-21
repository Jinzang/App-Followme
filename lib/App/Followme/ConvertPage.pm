package App::Followme::ConvertPage;
use 5.008005;
use strict;
use warnings;

use lib '../..';

use base qw(App::Followme::Module);

use File::Spec::Functions qw(abs2rel rel2abs catfile splitdir);
use App::Followme::FIO;

our $VERSION = "2.01";

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($pkg) = @_;

    return (
            template_file => 'convert_page.htm',
            data_pkg => 'App::Followme::TextData',
    );
}

#----------------------------------------------------------------------
# Convert files to html

sub run {
    my ($self, $folder) = @_;

    $self->update_folder($folder);
    return;
}

#----------------------------------------------------------------------
# Set the date format to iso date format, overriding user

sub setup {
    my ($self) = @_;

    $self->{data}{date_format} = 'yyyy-mm-ddThh:mm:ss';
    return;
}

#----------------------------------------------------------------------
# Construct a filename that represents the title

sub title_to_filename {
    my ($self, $filename) = @_;

    my ($dir, $base) = fio_split_filename($filename);
    return $filename if $base =~ /^index\./;

    my @parts = split(/\./, $base);
    my $ext = pop(@parts);

    my $new_filename = ${$self->{data}->build('title', $filename)};
    return $filename unless $new_filename;

    $new_filename = lc($new_filename);
    $new_filename =~ s/[^\w\-\_]+/ /g;

    $new_filename =~ s/^ +//;
    $new_filename =~ s/ +$//;
    $new_filename =~ s/ +/\-/g;

    $new_filename = catfile($dir, join('.', $new_filename, $ext));

    return $new_filename;
}

#----------------------------------------------------------------------
# Convert a single file

sub update_file {
    my ($self, $folder, $prototype, $file) = @_;

    my $new_file = $self->{data}->convert_filename($file);
    my $page = $self->render_file($self->{template_file}, $file);
    $page = $self->reformat_file($prototype, $new_file, $page);

    $self->write_file($new_file, $page);
    return;
}

#----------------------------------------------------------------------
# Find files in directory to convert and do that

sub update_folder {
    my ($self, $folder) = @_;

    my $index_file = $self->to_file($folder);
    my $source_folder = $self->{data}->convert_source_directory($folder);
    return unless $source_folder;

    my $same_directory = fio_same_file($folder, $source_folder, 
                                       $self->{case_sensitivity});
 
    $index_file = $self->to_file($source_folder);
    my $files = $self->{data}->build('files', $index_file);

    my $prototype;
    foreach my $file (@$files) {
        my $prototype ||= $self->find_prototype($folder, 0);
        eval {$self->update_file($folder, $prototype, $file)};
        if ($self->check_error($@, $file)) {
            unlink($file) if $same_directory;
        }
    }

    my $folders = $self->{data}->build('folders', $index_file);

    foreach my $subfolder (@$folders) {
        $self->update_folder($subfolder);
    }

    return;
}

#----------------------------------------------------------------------
# Write a file, setting folder level metadata

sub write_file {
    my ($self, $filename, $page, $binmode) = @_;

    my $time = ${$self->{data}->build('mdate', $filename)};
    my $new_filename = $self->title_to_filename($filename);

    fio_write_page($new_filename, $page, $binmode);

    unlink($filename) if -e $filename && 
        ! fio_same_file($filename, $new_filename, $self->{case_sensitivity});

    fio_set_date($new_filename, $time);

    return;
}

1;
__END__

=encoding utf-8

=head1 NAME

App::Followme::ConvertPage - Convert text files to html

=head1 SYNOPSIS

    use App::Followme::ConvertPage;
    my $converter = App::Followme::ConvertPage->new($configuration);
    $converter->run($folder);

=head1 DESCRIPTION

This module converts text files into web files by substituting the content into
a template. The type of file converted is determined by the value of the
parameter data_pkg. By default, it converts text files using the methods in
App::Followme::TextData.  After the conversion the original file is deleted.

Along with the content, other variables are calculated from the file name and
modification date. Variables in the template are preceded by a sigil, most
usually a dollar sign. Thus a link would look like:

    <li><a href="$url">$title</a></li>

=head1 CONFIGURATION

The following parameters are used from the configuration:

=over 4

=item template_file

The name of the template file. The template file is either in the current
directory, in the same directory as the configuration file used to invoke this
method, or if not there, in the _templates subdirectory of the top directory.
The default value is 'convert_page.htm'.

=item data_pkg

The name of the module that parses and retrieves data from the text file. The
default value is 'App::Followme::TextData', which by default parses 
Markdown files.

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut
