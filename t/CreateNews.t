#!/usr/bin/env perl
use strict;

use IO::File;
use File::Path qw(rmtree);
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

use Test::More tests => 8;

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

eval "use App::Followme::FIO";
require App::Followme::CreateNews;

my $test_dir = catdir(@path, 'test');

rmtree($test_dir);
mkdir $test_dir;
chdir $test_dir;
my $archive_dir = catfile($test_dir, 'archive');

my $configuration = {
                        absolute => 0,
                        base_directory => $test_dir,
                        news_file => '../blog.html',
                        news_index_file => 'index.html',
                        news_index_length => 3,
                        web_extension => 'html',
                        body_tag => 'content',
                        news_template => 'blog_template.htm',
                        news_index_template => 'news_index_template.htm',
                        template_directory => '.',
                     };

#----------------------------------------------------------------------
# Write templates

do {
    mkdir($archive_dir);
    chdir($test_dir);

   my $page = <<'EOQ';
<html>
<head>
<meta name="robots" content="archive">
<!-- section meta -->
<title>Post %%</title>
<!-- endsection meta -->
</head>
<body>
<!-- section content -->
<h1>Post %%</h1>

<p>All about %%.</p>
<!-- endsection content -->
</body>
</html>
EOQ

   my $archive_template = <<'EOQ';
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

<!-- for @loop -->
<h2>$title</h2>

$body
<p>$month $day $year<a href="$url">Permalink</a></p>
<!-- endfor -->
<!-- endsection content -->
</body>
</html>
EOQ

   my $index_template = <<'EOQ';
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
<li><a href="$url">$title</a></li>
<!-- endfor -->
</ul>
<!-- endsection content -->
</body>
</html>
EOQ

    my $idx = App::Followme::CreateNews->new($configuration);
    fio_write_page('blog_template.htm', $archive_template);
    fio_write_page('news_index_template.htm', $index_template);

    foreach my $count (qw(four three two one)) {
        sleep(2);
        my $output = $page;
        $output =~ s/%%/$count/g;

        my $filename = catfile('archive',"$count.html");
        fio_write_page($filename, $output);
    }
};

#----------------------------------------------------------------------
# Create index files

do {
    chdir($test_dir);
    my $idx = App::Followme::CreateNews->new($configuration);

    my $archive_dir = catfile($test_dir, 'archive');
    my ($filenames, $directories) = fio_visit($archive_dir);
    $idx->create_an_index($archive_dir, $directories, $filenames);

    my $page = fio_read_page(catfile($archive_dir,"index.html"));

    like($page, qr/>Post one<\/a><\/li>/, 'Archive index content'); # test 1
    like($page, qr/<a href="one.html">/, 'Archive index link'); # test 2
};

#----------------------------------------------------------------------
# Test recent_files

do {
    chdir($test_dir);
    my $idx = App::Followme::CreateNews->new($configuration);
    my $filenames = $idx->recent_files($test_dir);

    my @ok_filenames;
    foreach my $file (qw(one.html two.html three.html)) {
        push(@ok_filenames, catfile($archive_dir, $file));
    }

    is_deeply($filenames, \@ok_filenames, 'Recent files'); # test 3
};

#----------------------------------------------------------------------
# Create news file

do {
    my $body_ok = "\n\n<p>All about three.</p>\n";

    my $idx = App::Followme::CreateNews->new($configuration);
    my ($filenames, $directories) = fio_visit($archive_dir);
    my $data = $idx->index_data($archive_dir, $directories, $filenames);

    is($data->[2]{url}, 'three.html', 'Archive news url'); # test 4
    is($data->[2]{body}, $body_ok, "Archive news body"); #test 5

    $idx->create_recent_news($archive_dir);
    my $page = fio_read_page(catfile($test_dir,"blog.html"));

    like($page, qr/All about two/, 'Archive news content'); # test 6
    like($page, qr/<h2>Post two/, 'Archive news title'); # test 7
    like($page, qr/<a href="archive\/one.html">/, 'Archive news link'); # test 8
};
