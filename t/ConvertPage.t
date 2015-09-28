#!/usr/bin/env perl
use strict;

use File::Path qw(rmtree);
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

use Test::Requires 'Text::Markdown';
use Test::More tests => 5;

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
mkdir catfile($test_dir, "sub");
chdir $test_dir;

#----------------------------------------------------------------------
# Test

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
<!-- section content -->
<h1>Home</h1>
<!-- endsection content -->

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
<!-- section content -->
<h1>$title</h1>

$body
<!-- endsection content -->
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

    my %configuration = (page_template => 'template.htm');
    my $cvt = App::Followme::ConvertPage->new(%configuration);

    fio_write_page('index.html', $index);
    fio_write_page('template.htm', $template);

    foreach my $count (qw(four three two one)) {
        sleep(1);
        my $output = $text;
        $output =~ s/%%/$count/g;

        my $filename = "$count.md";
        fio_write_page($filename, $output);
    }

    my $prototype_file = $cvt->find_prototype($test_dir);
    my $prototype_file_ok = catfile($test_dir, 'index.html');
    is($prototype_file, $prototype_file_ok, 'Find page template'); # test 1

    my $data = $cvt->internal_fields({}, 'three.md');
    ok(index($data->{body}, "<li>third three</li>") > 0,'Convert Text'); # test 2
    $cvt->convert_a_file($test_dir, 'four.md');

    my $page = fio_read_page('four.html');
    like($page, qr/<h1>Page four<\/h1>/, 'Convert a file'); # test 3

    $cvt->run($test_dir);
    $page = fio_read_page('one.html');
    like($page, qr/<h1>Page one<\/h1>/, 'Convert text file one'); # test 4
    $page = fio_read_page('two.html');
    like($page, qr/<h1>Page two<\/h1>/, 'Convert text file two'); # test 5
};
