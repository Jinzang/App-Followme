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

require App::Followme::CreateIndexes;
require App::Followme::TopDirectory;

my $test_dir = catdir(@path, 'test');

rmtree($test_dir);
mkdir $test_dir;
mkdir catfile($test_dir, "sub");
chdir $test_dir;

App::Followme::TopDirectory->name($test_dir);

#----------------------------------------------------------------------
# Create indexes

do {
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

   my $index_template = <<'EOQ';
<html>
<head>
<meta name="robots" content="noarchive,follow">
<!-- section meta -->
<title>{{title}}</title>
<!-- endsection meta -->
</head>
<body>
<!-- section content -->
<h1>$title</h1>

<ul>
<!-- loop -->
<li><a href="{{url}}">{{title}}</a></li>
<!-- endloop -->
</ul>
<!-- endsection content -->
</body>
</html>
EOQ

my $body_ok = <<'EOQ';

<h1>Post three</h1>

<p>All about three.</p>
EOQ

    my $index_name = 'index_template.htm';

    my $configuration = {
            include_directories => 1,
            include_files => '*.html',
            index_template => $index_name,
            index_file => 'index.html',
            web_extension => 'html',
            };

    my $idx = App::Followme::CreateIndexes->new($configuration);
    $idx->write_page($index_name, $index_template);

    mkdir('archive');    
    chdir('archive');
    
    my @archived_files;
    foreach my $count (qw(four three two one)) {
        my $output = $page;
        $output =~ s/%%/$count/g;
        
        my $filename = "$count.html";
        $idx->write_page($filename, $output);
        push(@archived_files, $filename);
    }


    $idx = App::Followme::CreateIndexes->new($configuration);
    my $data = $idx->index_data();

    is($data->{title}, 'Archive', 'Index title'); # test 1
    is($data->{url}, 'index.html', 'Index url'); # test 2
    is($data->{loop}[0]{title}, 'Four', 'Index first page title'); # test 3
    is($data->{loop}[3]{title}, 'Two', 'Index last page title'); # test 4
    
    $idx = App::Followme::CreateIndexes->new($configuration);
    $idx->create_an_index();
    $page = $idx->read_page('index.html');
    
    like($page, qr/<title>Archive<\/title>/, 'Write index title'); # test 5
    like($page, qr/<li><a href="two.html">Two<\/a><\/li>/,
       'Write index link'); #test 6

    $idx = App::Followme::CreateIndexes->new($configuration);
    $idx->create_an_index();
    $page = $idx->read_page('index.html');

    my $pos = index($page, 'index.html');
    is($pos, -1, 'Exclude index file'); # test 7
    
    chdir($test_dir);
    $idx = App::Followme::CreateIndexes->new($configuration);
    $idx->create_an_index();
    $page = $idx->read_page('index.html');

    like($page, qr/<li><a href="archive\/index.html">Archive<\/a><\/li>/,
       'Index with directory'); #test 8
};
