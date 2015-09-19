package App::Followme::CreateGallery;
use 5.008005;
use strict;
use warnings;

use lib '../..';

use base qw(App::Followme::Module);

use GD;
use Cwd;
use IO::Dir;
use File::Spec::Functions qw(abs2rel rel2abs splitdir catfile);
use App::Followme::FIO;

our $VERSION = "1.16";

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($self) = @_;

    return (
                      gallery_file => 'index.html',
                      gallery_include => '*.jpg',
                      gallery_template => 'gallery.htm',
                      thumb_suffix => '-thumb',
                      thumb_width => 0,
                      thumb_height => 0,
                      photo_width => 0,
                      photo_height => 0,
                     );
}

#----------------------------------------------------------------------
# Return all the files in a subtree (example)

sub run {
    my ($self, $directory) = @_;

    my $gallery_name = fio_full_file_name($directory, $self->{gallery_file});

    eval {
       $self->create_a_gallery($directory, $gallery_name)
    };

    warn "$gallery_name: $@" if $@;

    return;
}

#----------------------------------------------------------------------
# Build the name of the photo file

sub build_photo_name {
    my ($self, $filename) = @_;
    return $filename;
}

#----------------------------------------------------------------------
# Build a url from a photo name

sub build_photo_url {
    my ($self, $data, $directory, $filename) = @_;

    for my $field (qw(thumb photo)) {
        my $name = $field . '_url';
        my $sub = "build_${field}_name";

        my $photoname = $self->$sub($filename, $field);
        $data->{$name} = fio_filename_to_url($directory, $photoname);

        $name = 'absolute_' . $name;
        $data->{$name} = '/' . fio_filename_to_url($self->{top_directory},
                                                   $photoname);
    }

    return $data;
}

#----------------------------------------------------------------------
# Build the name of the thumb file

sub build_thumb_name {
    my ($self, $filename) = @_;

    my ($dir, $file) = fio_split_filename($filename);
    my ($root, $ext) = split(/\./, $file);
    $file = join('', $root, $self->{thumb_suffix}, '.', $ext);
    my $photoname = catfile($dir, $file);

    return $photoname;
}

#----------------------------------------------------------------------
# Create the photo gallery for a directory

sub create_a_gallery {
    my ($self, $directory, $gallery_name) = @_;

    my ($filenames, $directories) = fio_visit($directory);
    @$filenames = grep {$self->match_file($_)} @$filenames;

    my $template_name = $self->get_template_name($self->{gallery_template});
    return if fio_is_newer($gallery_name, $template_name, @$filenames);

    my $data = $self->SUPER::set_fields($directory, $gallery_name);
    $data->{loop} = $self->gallery_data($directory, $filenames);

    my $render = $self->make_template($gallery_name,
                                      $self->{gallery_template});
    my $page = $render->($data);

    fio_write_page($gallery_name, $page);
    return;
}

#----------------------------------------------------------------------
# Get data to be interpolated into template

sub gallery_data {
    my ($self, $directory, $filenames) = @_;

    my @index_data;
    foreach my $filename (@$filenames) {
        push(@index_data, $self->set_fields($directory, $filename));
    }

    return \@index_data;
}

#----------------------------------------------------------------------
# Get the dimensions of an image and its thumbnail, resize if needed

sub get_dimensions {
    my ($self, $data, $directory, $filename) = @_;

    my $gallery_name = fio_full_file_name($directory, $self->{gallery_file});

    my $old_photo = $self->read_photo($filename);
    my ($old_width, $old_height) = $old_photo->getBounds();

    for my $field (qw(thumb photo)) {
        my ($width, $height) = $self->new_size($field, $old_width, $old_height);
        if ($width && $height) {
            $data->{"${field}_width"} = $width;
            $data->{"${field}_height"} = $height;

            my $sub = "build_${field}_name";
            my $photoname = $self->$sub($filename);
            next unless fio_is_newer($photoname, $gallery_name);

            my $photo = $self->resize_a_photo($old_photo, $width, $height,
                                              $old_width, $old_height);

            $self->write_photo($photoname, $photo);

        } else {
            $data->{"${field}_width"} = $old_width;
            $data->{"${field}_height"} = $old_height;
        }
    }

    return $data;
}

#----------------------------------------------------------------------
# Get the list of excluded files

sub get_excluded_files {
    my ($self) = @_;

    my ($dir, $file) = fio_split_filename($self->{gallery_include});
    $file = $self->build_thumb_name($file);
    ($dir, $file) = fio_split_filename($file);

    return $file;
}

#----------------------------------------------------------------------
# Get the list of included files

sub get_included_files {
    my ($self) = @_;
    return $self->{gallery_include};
}

#---------------------------------------------------------------------------
# Calculate the new width and height of a photo

sub new_size {
    my($self, $field, $old_width, $old_height) = @_;

    my $width_field = "${field}_width";
    my $height_field = "${field}_height";

    my $factor;
    if ($self->{$width_field} && $self->{$height_field}) {
        my $width_factor = $self->{$width_field} / $old_width;
        my $height_factor = $self->{$height_field} / $old_height;
        $factor = ($height_factor < $width_factor ? $height_factor : $width_factor);

    } elsif ($self->{$width_field}) {
       $factor = $self->{$width_field} / $old_width;

    } elsif ($self->{$height_field}) {
        $factor = $self->{$height_field} / $old_height;

    } else {
        $factor = 0.0;
    }

    my $height = int($factor * $old_height);
    my $width  = int($factor * $old_width);

    return ($width, $height);
}

#---------------------------------------------------------------------------
# Read a photo

sub read_photo {
    my ($self, $photoname) = @_;

    GD::Image->trueColor(1);
    my $photo = GD::Image->new($photoname);
    die "Couldn't read $photoname" unless $photo;

    return $photo;
}

#---------------------------------------------------------------------------
# Resize a photo

sub resize_a_photo {
    my ($self, $old_photo, $width, $height, $old_width, $old_height) = @_;

    my $photo = GD::Image->new($width, $height);
    $photo->copyResampled($old_photo,
                          0, 0, 0, 0,
                          $width, $height,
                          $old_width, $old_height);

    return $photo;
}

#----------------------------------------------------------------------
# Set the data fields for a file

sub set_fields {
    my ($self, $directory, $filename) = @_;

    my $data = {};
    $data = $self->build_date($data, $filename);
    $data = $self->build_title_from_filename($data, $filename);
    $data = $self->build_photo_url($data, $directory, $filename);
    $data = $self->get_dimensions($data, $directory, $filename);

    return $data;
}

#----------------------------------------------------------------------
# Save a photo

sub write_photo {
    my ($self, $photoname, $photo) = @_;

    my $fd = IO::File->new($photoname, 'w');
    die "Couldn't write $photoname" unless $fd;

    my $data = $photo->jpeg();

    binmode($fd);
    print $fd $data;
    close($fd);

    return;
}

1;
__END__

=encoding utf-8

=head1 NAME

App::Followme::CreateGallery - Create a photo gallery page

=head1 SYNOPSIS

    use App::Followme::CreateGallery;
    my $gallery = App::Followme::CreateGallery->new($configuration);
    $gallery->run($directory);

=head1 DESCRIPTION

This package builds an index for a directory which serves as a photo gallery.
The variables described below are substituted into a template to produce the
gallery. Loop comments that look like

    <!-- loop -->
    <!-- endloop -->

indicate the section of the template that is repeated for each photo contained
in the directory. The following variables may be used in the template:

=over 4

=item absolute_photo_url

The absolute url of the photo

=item absolute_thumb_url

The absolute url of the photo thumbnail

=item photo_height

The height of the photo

=item photo_url

The relative url of the photo

=item photo_width

The width of the photo

=item thumb_height

The height of the photo thumbnail

=item thumb_url

The relative url of the photo thumbnail

=item thumb_width

The width of the photo thumbnail

=item title

The photo tile, derived from the photo filename.

=item time fields

The variables calculated from the modification time are: C<weekday, month,>
C<monthnum, day, year, hour24, hour, ampm, minute,> and C<second.>

=back

=head1 CONFIGURATION

The following fields in the configuration file are used:

=over 4

=item gallery_file

The name of the file containing the photo gallery. By default, this name
is index.html.

=item gallery_include

A wild card expression indicating the files that are photos to be included in
the gallery. The default is '*.jpg',

=item gallery_template

The name of the template used to produce the photo gallery. The default is
'gallery.htm'.

=item thumb_suffix

The suffix added to the photo name to produce the thumb photo name. The default
is '-thumb'.

=item thumb_width

The width of the thumb photos. Leave at 0 if the width is defined to be
proportional to the height.

=item thumb_height

The height of the thumb photos. Leave at 0 if the height is defined to be
proportional to the width. If both thumb_width and thumb_height are 0, no
thumb photo will be created.

=item photo_width

The width of the photo after resizing. Leave at 0 if the width is defined to be
proportional to the height.

=item photo_height

The height of the photo after resizing. Leave at 0 if the height is defined to
be proportional to the width. If both photo_width and photo_height are zero,
the image will not be resized.

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut
