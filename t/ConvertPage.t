#!/usr/bin/env perl
use strict;

use File::Path qw(rmtree);
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

use Test::Requires 'Text::Markdown';
use Test::More tests => 7;

use lib '../..';

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

eval "use App::Followme::FIO";
require App::Followme::ConvertPage;

my $test_dir = catdir(@path, 'test');

rmtree($test_dir);
mkdir $test_dir;
my $sub = catfile($test_dir, "sub");
mkdir $sub;
chdir $test_dir;

#----------------------------------------------------------------------
# Create object

my $template_directory = $sub;
my $template_file = 'template.htm';
my $prototype_file = rel2abs('index.html');

my $cvt = App::Followme::ConvertPage->new(template_directory => $template_directory,
                                          template_file => $template_file);

isa_ok($cvt, "App::Followme::ConvertPage"); # test 1
can_ok($cvt, qw(new run)); # test 2

#----------------------------------------------------------------------
# Write test data

do {
   my $index = <<'EOQ';
<html>
<head>
<meta name="robots" content="archive">
<!-- section meta -->
<title>Home</title>
<!-- endsection meta -->
</head>
<body>
<!-- section primary -->
<h1>Home</h1>
<!-- endsection primary -->

<ul>
<li><a href="index.html">Home</a></li>
</ul>
</body>
</html>
EOQ

   my $template = <<'EOQ';
<html>
<head>
<meta name="robots" content="archive">
<!-- section meta -->
<title>$title</title>
<!-- endsection meta -->
</head>
<body>
<!-- section primary -->
<h1>$title</h1>

$body
<!-- endsection primary -->
</body>
</html>
EOQ

   my $text = <<'EOQ';
Page %%
--------

This is a paragraph


    This is preformatted text.

* first %%
* second %%
* third %%
EOQ

    my %configuration = (template_dile => 'template.htm');
    my $cvt = App::Followme::ConvertPage->new(%configuration);

    fio_write_page($prototype_file, $index);
    fio_write_page(catfile($template_directory, $template_file), $template);

    foreach my $count (qw(four three two one)) {
        sleep(1);
        my $output = $text;
        $output =~ s/%%/$count/g;

        my $filename = "$count.md";
        fio_write_page($filename, $output);
    }
};

#----------------------------------------------------------------------
# Get filename from title

do {
   my $filename = rel2abs('one.html');
   my $new_filename = $cvt->title_to_filename($filename);
   is($new_filename, $filename, "Title to filename"); #test 3
};

#----------------------------------------------------------------------
# Test update file and folder
do {
    $cvt->update_file($prototype_file, 'four.md');

    my $page = fio_read_page('four.html');
    like($page, qr/<h1>Four<\/h1>/, 'Update file four'); # test 4

    $cvt->update_folder($prototype_file);
    foreach my $count (qw(three two one)) {
        my $file = "$count.html";
        $page = fio_read_page($file);
        my $kount = ucfirst($count);

        like($page, qr/<h1>$kount<\/h1>/,
             "Update folder file $count"); # test 5-7
    }
};
