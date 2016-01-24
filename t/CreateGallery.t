#!/usr/bin/env perl
use strict;

use IO::File;
use File::Path qw(rmtree);
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

use Test::Requires 'GD';
use Test::More tests => 15;

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

eval "use App::Followme::FIO";
require App::Followme::CreateGallery;

my $test_dir = catdir(@path, 'test');
my $data_dir = catdir(@path, 'tdata');

rmtree($test_dir);
mkdir $test_dir;
chdir $test_dir;

my $template_name = 'gallery_template.htm';

my %configuration = (
                    template_file => $template_name,
                    thumb_suffix => '-thumb',
                    web_extension => 'html',
                    photo_height => 600,
                    thumb_height => 150,
                    );

#----------------------------------------------------------------------
# Test support routines

do {
    my $gal = App::Followme::CreateGallery->new(%configuration);

    my %new_configuration = %configuration;
    $new_configuration{photo_height} = 600;
    $new_configuration{thumb_height} = 150;
    $gal = App::Followme::CreateGallery->new(%new_configuration);
    my ($width, $height) = $gal->new_size('photo', 1800, 1200);
    is($width, 900, 'photo width'); # test 1
    is($height, 600, 'photo height'); # test 2

    %new_configuration = %configuration;
    $new_configuration{photo_width} = 600;
    $new_configuration{thumb_width} = 150;
    $gal = App::Followme::CreateGallery->new(%new_configuration);
    ($width, $height) = $gal->new_size('thumb', 1800, 1200);
    is($width, 150, 'thumb width'); # test 3
    is($height, 100, 'thumb height'); # test 4
};

#----------------------------------------------------------------------
# Create gallery

do {
   my $gallery_template = <<'EOQ';
<html>
<head>
<meta name="robots" content="noarchive,follow">
<!-- section meta -->
<title>$title</title>
<!-- endsection meta -->
</head>
<body>
<!-- section content -->
<h1>$title</h1>

<ul>
<!-- for @loop -->
<li><img src="$thumb_url" width="$thumb_width" height="$thumb_height" /><br />
<a href="$photo_url">$title</a></li>
<!-- endfor -->
</ul>
<!-- endsection content -->
</body>
</html>
EOQ

    my $gal = App::Followme::CreateGallery->new(%configuration);
    fio_write_page($template_name, $gallery_template);

    my $gallery_dir = catfile($test_dir, 'gallery');
    mkdir($gallery_dir);
    chdir($gallery_dir);

    my @photo_files;
    my @thumb_files;
    foreach my $count (qw(first second third)) {
        my $filename = '*-photo.jpg';
        $filename =~ s/\*/$count/g;

        my $input_file = catfile($data_dir, $filename);
        my $output_file = catfile($gallery_dir, $filename);

        my $photo = $gal->{data}->read_photo($input_file);
        $gal->write_photo($output_file, $photo);
        ok(-e $output_file, "read and write photo $count"); # test 5-7

        push(@photo_files, $output_file);
        my $thumb_file = $gal->build_thumb_name($output_file);
        push(@thumb_files, $thumb_file);
    }

    my $data = $gal->gallery_data($gallery_dir, \@photo_files);
    is($data->[0]{title}, 'First Photo', 'First page title'); # test 8
    is($data->[1]{photo_url}, 'second-photo.jpg', 'Second page url'); # test 9
    is($data->[2]{thumb_url}, 'third-photo-thumb.jpg',
       'Third page thumb url'); # test 12

    foreach my $i (1 .. 3) {
        ok(-e $thumb_files[$i-1], "Create thumb $i"); # test 11-13
    }

    my $gallery_name = fio_full_file_name($gallery_dir, $gal->{gallery_file});
    $gal->create_a_gallery($gallery_dir, $gallery_name);

    ok(-e $gallery_name, 'Create index file'); # test 14

    my $page = fio_read_page($gallery_name);
    my @items = $page =~ m/(<li>)/g;
    is(@items, 3, 'Index three photos'); # test 15
};
