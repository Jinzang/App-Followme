#!/usr/bin/env perl
use strict;

use IO::File;
use File::Path qw(rmtree);
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

use Test::More tests => 6;

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

require App::Followme::CreateNews;
require App::Followme::Common;

my $test_dir = catdir(@path, 'test');

rmtree($test_dir);
mkdir $test_dir;
mkdir "$test_dir/sub";
chdir $test_dir;

App::Followme::Common::top_directory($test_dir);

my $configuration = {
                        absolute => 0,
                        base_directory => $test_dir,
                        news_file => 'blog.html',
                        news_index_length => 5,
                        web_extension => 'html',
                        body_tag => 'content',
                        news_template => 'blog_template.htm',
                     };
#----------------------------------------------------------------------
# Write test files

do {
   my $code = <<'EOQ';
<html>
<head>
<meta name="robots" content="archive">
<!-- section meta -->
<title>%%</title>
<!-- endsection meta -->
</head>
<body>
<!-- section content -->
<h1>%%</h1>
<!-- endsection content -->
<!-- section navigation in folder -->
<p><a href="">&&</a></p>
<!-- endsection navigation -->
</body>
</html>
EOQ

    foreach my $dir (('sub', '')) {
        foreach my $count (qw(four three two one)) {
            sleep(1);
            my $output = $code;
            $output =~ s/%%/Page $count/g;
            $output =~ s/&&/$dir link/g;

            my $filename = $dir ? "$dir/$count.html" : "$count.html";
            App::Followme::Common::write_page($filename, $output);
        }
    }
};

#----------------------------------------------------------------------
# Test file visitor

do {
    my $idx = App::Followme::CreateNews->new($configuration);
    my $visitor = $idx->visitor_function();
    
    my @filenames;
    while (my $filename = $visitor->('html')) {
        push(@filenames, $filename);
    }
    
    my @ok_filenames = qw(one.html two.html three.html four.html
                          sub/one.html sub/two.html sub/three.html
                          sub/four.html);
    for (@ok_filenames) {
        my @dirs = split('/', $_);
        $_ = catfile(@dirs);
    }
    
    is_deeply(\@filenames, \@ok_filenames, 'File visitor'); # test 1
};

#----------------------------------------------------------------------
# Test more_recent_files 

do {
    my $idx = App::Followme::CreateNews->new($configuration);
    my @filenames = $idx->more_recent_files(3);

    my @ok_filenames = qw(one.html two.html three.html);
    is_deeply(\@filenames, \@ok_filenames, 'Most recent files'); # test 2
};

#----------------------------------------------------------------------
# Create indexes

do {    
    mkdir('archive');

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
<title>{{title}}</title>
<!-- endsection meta -->
</head>
<body>
<!-- section content -->
<h1>{{title}}</h1>

<!-- loop -->
{{body}}
<p>{{month}} {{day}} {{year}}<a href="{{url}}">Permalink</a></p>
<!-- endloop -->
<!-- endsection content -->
</body>
</html>
EOQ

my $body_ok = <<'EOQ';

<h1>Post three</h1>

<p>All about three.</p>
EOQ

    App::Followme::Common::write_page('blog_template.htm', $archive_template);

    my @archived_files;
    foreach my $count (qw(four three two one)) {
        sleep(2);
        my $output = $page;
        $output =~ s/%%/$count/g;
        
        my $filename = catfile('archive',"$count.html");
        App::Followme::Common::write_page($filename, $output);
        push(@archived_files, $filename);
    }

    chdir('archive');
    my $idx = App::Followme::CreateNews->new($configuration);

    my $data = $idx->recent_news_data();
    is($data->{url}, 'blog.html', 'Archive index url'); # test 3
    is($data->{loop}[2]{body}, $body_ok, "Archive index body"); #test 4

    $idx->create_news_index();
    $page = App::Followme::Common::read_page("$test_dir/blog.html");
    like($page, qr/All about two/, 'Archive index content'); # test 5
    like($page, qr/<a href="one.html">/, 'Archive index link'); # test 6
};
