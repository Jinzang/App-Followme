#!/usr/bin/env perl
use strict;

use IO::File;
use Test::More tests => 6;
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

require App::Followme::CreateIndexes;
require App::Followme::Common;

my $test_dir = catdir(@path, 'test');
system("/bin/rm -rf $test_dir");
mkdir $test_dir;
mkdir "$test_dir/sub";
chdir $test_dir;

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
    App::Followme::Common::write_page($index_name, $index_template);

    mkdir('archive');    
    chdir('archive');
    
    my @archived_files;
    foreach my $count (qw(four three two one)) {
        sleep(1);
        my $output = $page;
        $output =~ s/%%/$count/g;
        
        my $filename = "$count.html";
        App::Followme::Common::write_page($filename, $output);
        push(@archived_files, $filename);
    }

    my $configuration = {
            base_dir => $test_dir,
            include_directories => 0,
            include_files => '*.html',
            index_template => $index_name,
            };

    my $idx = App::Followme::CreateIndexes->new($configuration);
    my $data = $idx->index_data('index.html');
    is($data->{title}, 'Archive', 'Index title'); # test 1
    is($data->{url}, 'index.html', 'Index url'); # test 2
    is($data->{loop}[0]{title}, 'Four', 'Index first page title'); # test 3
    is($data->{loop}[3]{title}, 'Two', 'Index last page title'); # test 4
    
    $idx->create_an_index('index.html');
    $page = App::Followme::Common::read_page('index.html');
    
    like($page, qr/<title>Archive<\/title>/, 'Write index title'); # test 5
    like($page, qr/<li><a href="two.html">Two<\/a><\/li>/,
       'Write index link'); #test 6
};
