#!/usr/bin/env perl
use strict;

use Test::More tests => 7;
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

require App::Followme::ConvertPages;
require App::Followme::Common;

my $test_dir = catdir(@path, 'test');
system("/bin/rm -rf $test_dir");
mkdir $test_dir;
mkdir "$test_dir/sub";
chdir $test_dir;

App::Followme::Common::top_directory($test_dir);

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

    App::Followme::Common::write_page('index.html', $index);
    App::Followme::Common::write_page('template.htm', $template);

    foreach my $count (qw(four three two one)) {
        my $output = $text;
        $output =~ s/%%/$count/g;
        
        my $filename = "$count.txt";
        App::Followme::Common::write_page($filename, $output);
    }

    my $prototype_file = App::Followme::Common::find_prototype('html', 0);
    my $prototype_file_ok = catfile($test_dir, 'index.html');
    is($prototype_file, $prototype_file_ok, 'Find page templae'); # test 1

    my $source = App::Followme::Common::make_template('template.htm', 'html');

    like($source, qr/<ul>/, 'Make template links'); # test 2
    like($source, qr/{{body}}/, 'Make template body'); # test 3

    my $configuration = {page_template => 'template.htm'};
    
    my $cvt = App::Followme::ConvertPages->new($configuration);
    my $page = App::Followme::Common::read_page('three.txt');
    my $tagged_text = $cvt->convert_text($page);
    my $tagged_text_ok = $text;
    
    $tagged_text_ok =~ s/Page %%/<p>Page three<\/p>/;
    $tagged_text_ok =~ s/This is a paragraph/<p>This is a paragraph<\/p>/;
    
    is($tagged_text, $tagged_text_ok, 'Convert Text'); # test 4

    my $sub = App::Followme::Common::compile_template($template);    
    $cvt->convert_a_file('four.txt', $sub);
    $page = App::Followme::Common::read_page('four.html');
    like($page, qr/<h1>Four<\/h1>/, 'Convert a file'); # test 5

    $cvt->run();
    $page = App::Followme::Common::read_page('one.html');
    like($page, qr/<h1>One<\/h1>/, 'Convert text file one'); # test 6
    $page = App::Followme::Common::read_page('two.html');
    like($page, qr/<h1>Two<\/h1>/, 'Convert text file two'); # test 7
};
