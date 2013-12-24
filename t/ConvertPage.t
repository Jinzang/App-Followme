#!/usr/bin/env perl
use strict;

use File::Path qw(rmtree);
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

use Test::More tests => 7;

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

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
<title>{{title}}</title>
<!-- endsection meta -->
</head>
<body>
<!-- section content -->
<h1>{{title}}</h1>

{{body}}
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

    my $configuration = {page_template => 'template.htm'};
    my $cvt = App::Followme::ConvertPage->new($configuration);
    
    $cvt->write_page('index.html', $index);
    $cvt->write_page('template.htm', $template);

    foreach my $count (qw(four three two one)) {
        sleep(1);
        my $output = $text;
        $output =~ s/%%/$count/g;
        
        my $filename = "$count.md";
        $cvt->write_page($filename, $output);
    }

    my $prototype_file = $cvt->find_prototype($test_dir);
    my $prototype_file_ok = catfile($test_dir, 'index.html');
    is($prototype_file, $prototype_file_ok, 'Find page template'); # test 1

    my $source = $cvt->make_template($test_dir, 'template.htm');

    like($source, qr/<ul>/, 'Make template links'); # test 2
    like($source, qr/{{body}}/, 'Make template body'); # test 3

    my $data = $cvt->internal_fields({}, 'three.md');
    ok(index($data->{body}, "<li>third three</li>") > 0,'Convert Text'); # test 4

    my $render = $cvt->compile_template($template);    
    $cvt->convert_a_file($render, $test_dir, 'four.md');
    
    my $page = $cvt->read_page('four.html');
    like($page, qr/<h1>Four<\/h1>/, 'Convert a file'); # test 5

    $cvt->run($test_dir);
    $page = $cvt->read_page('one.html');
    like($page, qr/<h2>Page one<\/h2>/, 'Convert text file one'); # test 6
    $page = $cvt->read_page('two.html');
    like($page, qr/<h2>Page two<\/h2>/, 'Convert text file two'); # test 7
};
