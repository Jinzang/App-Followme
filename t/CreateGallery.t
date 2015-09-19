#!/usr/bin/env perl
use strict;

use IO::File;
use File::Path qw(rmtree);
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

use Test::Requires 'GD';
use Test::More tests => 17;

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

my $configuration = {
                    gallery_file => 'index.html',
                    gallery_include => '*.jpg',
                    gallery_template => $template_name,
                    thumb_suffix => '-thumb',
                    web_extension => 'html',
                    photo_height => 600,
                    thumb_height => 150,
                    };

#----------------------------------------------------------------------
# Test support routines

do {
    my $gal = App::Followme::CreateGallery->new($configuration);
    my $filename = catfile($test_dir, 'myphoto.jpg');
    my $thumbname = $gal->build_thumb_name($filename);
    is($thumbname, catfile($test_dir, 'myphoto-thumb.jpg'),
       'build thumb name'); # test 1

    my $exclude = $gal->get_excluded_files();
    is($exclude, '*-thumb.jpg', 'excluded files'); # test 2

    my %configuration = %$configuration;
    $configuration{photo_height} = 600;
    $configuration{thumb_height} = 150;
    $gal = App::Followme::CreateGallery->new(\%configuration);
    my ($width, $height) = $gal->new_size('photo', 1800, 1200);
    is($width, 900, 'photo width'); # test 3
    is($height, 600, 'photo height'); # test 4

    %configuration = %$configuration;
    $configuration{photo_width} = 600;
    $configuration{thumb_width} = 150;
    $gal = App::Followme::CreateGallery->new(\%configuration);
    ($width, $height) = $gal->new_size('thumb', 1800, 1200);
    is($width, 150, 'thumb width'); # test 5
    is($height, 100, 'thumb height'); # test 6
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

    my $gal = App::Followme::CreateGallery->new($configuration);
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

        my $photo = $gal->read_photo($input_file);
        $gal->write_photo($output_file, $photo);
        ok(-e $output_file, "read and write photo $count"); # test 7-9

        push(@photo_files, $output_file);
        my $thumb_file = $gal->build_thumb_name($output_file);
        push(@thumb_files, $thumb_file);
    }

    my $data = $gal->gallery_data($gallery_dir, \@photo_files);
    is($data->[0]{title}, 'First Photo', 'First page title'); # test 10
    is($data->[1]{photo_url}, 'second-photo.jpg', 'Second page url'); # test 11
    is($data->[2]{thumb_url}, 'third-photo-thumb.jpg',
       'Third page thumb url'); # test 12

    foreach my $i (1 .. 3) {
        ok(-e $thumb_files[$i-1], "Create thumb $i"); # test 13-15
    }

    my $gallery_name = fio_full_file_name($gallery_dir, $gal->{gallery_file});
    $gal->create_a_gallery($gallery_dir, $gallery_name);

    ok(-e $gallery_name, 'Create index file'); # test 16

    my $page = fio_read_page($gallery_name);
    my @items = $page =~ m/(<li>)/g;
    is(@items, 3, 'Index three photos'); # test 17
};
