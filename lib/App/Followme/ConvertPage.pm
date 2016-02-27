package App::Followme::ConvertPage;
use 5.008005;
use strict;
use warnings;

use lib '../..';

use base qw(App::Followme::Module);

use Text::Markdown;
use File::Spec::Functions qw(catfile);
use App::Followme::FIO;

our $VERSION = "1.16";

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($pkg) = @_;

    return (
            template_file => 'convert_page.htm',
            data_pkg => 'App::Followme::MarkdownData',
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
# Convert a single file

sub update_file {
    my ($self, $prototype, $file) = @_;

    ##my $date = $self->{data}->build('date', $file);

    my $new_file = $file;
    $new_file =~ s/\.[^\.]*$/.$self->{web_extension}/;

    my $page = $self->render_file($self->{template_file}, $file);
    $page = $self->reformat_file($prototype, $new_file, $page);

    fio_write_page($new_file, $page);
    ##fio_set_date($new_file, $$date);
    unlink($file);

    return;
}

#----------------------------------------------------------------------
# Find files in directory to convert and do that

sub update_folder {
    my ($self, $folder) = @_;

    my $index_file = $self->to_file($folder);
    my $files = $self->{data}->build('files', $index_file);

    my $prototype;
    foreach my $file (@$files) {
        my $prototype ||= $self->find_prototype($folder, 0);
        eval {$self->update_file($prototype, $file)};
        $self->check_error($@, $file);
    }

    if (! $self->{quick_update}) {
        my $folders = $self->{data}->build('folders', $folder);
        foreach my $subfolder (@$folders) {
            $self->update_folder($subfolder);
        }
    }

    return;
}

1;
__END__

=encoding utf-8

=head1 NAME

App::Followme::ConvertPage - Convert Markdown files to html

=head1 SYNOPSIS

    use App::Followme::ConvertPage;
    my $converter = App::Followme::ConvertPage->new($configuration);
    $converter->run($folder);

=head1 DESCRIPTION

If there are any markdown files in the directory, they are converted into html
files by substituting the content into a template. After the conversion the
original file is deleted. Markdown files are identified by their extension,
which by default is 'md'.

Along with the content, other variables are calculated from the file name and
modification date. Variables in the template are preceded by a sigil, most usually
a dollar sign. Thus a link would look like:

    <li><a href="$url">$title</a></li>

=head1 CONFIGURATION

The following parameters are used from the configuration:

=over 4

=item template_file

The name of the template file. The template file is either in the current
directory, in the same directory as the configuration file used to invoke this
method, or if not there, in the templates subdirectory.

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut
