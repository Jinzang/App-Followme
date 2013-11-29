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

require App::Followme::ConvertPages;

my $test_dir = catdir(@path, 'test');

rmtree($test_dir);
mkdir $test_dir;
mkdir catfile($test_dir, "sub");
chdir $test_dir;

App::Followme::TopDirectory->name($test_dir);

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

This is a paragraph

<pre>
This is preformatted text.
</pre>
EOQ

    my $configuration = {page_template => 'template.htm'};
    my $cvt = App::Followme::ConvertPages->new($configuration);
    
    $cvt->write_page('index.html', $index);
    $cvt->write_page('template.htm', $template);

    foreach my $count (qw(four three two one)) {
        sleep(1);
        my $output = $text;
        $output =~ s/%%/$count/g;
        
        my $filename = "$count.txt";
        $cvt->write_page($filename, $output);
    }

    my $prototype_file = $cvt->find_prototype($test_dir);
    my $prototype_file_ok = catfile($test_dir, 'index.html');
    is($prototype_file, $prototype_file_ok, 'Find page templae'); # test 1

    my $source = $cvt->make_template($test_dir);

    like($source, qr/<ul>/, 'Make template links'); # test 2
    like($source, qr/{{body}}/, 'Make template body'); # test 3

    my $page = $cvt->read_page('three.txt');
    my $tagged_text = $cvt->convert_text($page);
    my $tagged_text_ok = $text;
    
    $tagged_text_ok =~ s/Page %%/<p>Page three<\/p>/;
    $tagged_text_ok =~ s/This is a paragraph/<p>This is a paragraph<\/p>/;
    
    is($tagged_text, $tagged_text_ok, 'Convert Text'); # test 4

    my $sub = $cvt->compile_template($template);    
    $cvt->convert_a_file($test_dir, 'four.txt', $sub);
    $page = $cvt->read_page('four.html');
    like($page, qr/<h1>Four<\/h1>/, 'Convert a file'); # test 5

    $cvt->run($test_dir);
    $page = $cvt->read_page('one.html');
    like($page, qr/<h1>One<\/h1>/, 'Convert text file one'); # test 6
    $page = $cvt->read_page('two.html');
    like($page, qr/<h1>Two<\/h1>/, 'Convert text file two'); # test 7
};
