#!/usr/bin/env perl
use strict;

use IO::File;
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

require App::Followme::CreateNews;

my $test_dir = catdir(@path, 'test');

rmtree($test_dir);
mkdir $test_dir;
mkdir catfile($test_dir, "sub");
chdir $test_dir;

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

            my @dirs;
            push(@dirs, $test_dir);
            push(@dirs, $dir) if $dir;
            my $filename = catfile(@dirs, "$count.html");
            
            my $fd = IO::File->new($filename, 'w');
            print $fd $output;
            close $fd;
        }
    }
};

#----------------------------------------------------------------------
# Test recent_files 

do {
    my $idx = App::Followme::CreateNews->new($configuration);
    my $filenames = $idx->recent_files($test_dir);

    my @ok_filenames;
    foreach my $file (qw(one.html two.html three.html)) {
        push(@ok_filenames, rel2abs($file));
    }
    
    is_deeply($filenames, \@ok_filenames, 'Recent files'); # test 1
};

#----------------------------------------------------------------------
# Create news file

do {
    my $archive_dir = catfile($test_dir, 'archive');
    mkdir($archive_dir);

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

    my $idx = App::Followme::CreateNews->new($configuration);
    $idx->write_page('blog_template.htm', $archive_template);
    
    my @archived_files;
    foreach my $count (qw(four three two one)) {
        sleep(2);
        my $output = $page;
        $output =~ s/%%/$count/g;
        
        my $filename = catfile('archive',"$count.html");
        $idx->write_page($filename, $output);
        push(@archived_files, $filename);
    }

    $idx = App::Followme::CreateNews->new($configuration);
    my $data = $idx->index_data($archive_dir);

    is($data->[2]{url}, 'three.html', 'Archive news url'); # test 2
    is($data->[2]{body}, $body_ok, "Archive news body"); #test 3

    $idx->create_recent_news($archive_dir);
    $page = $idx->read_page(catfile($test_dir,"blog.html"));

    like($page, qr/All about two/, 'Archive news content'); # test 4
    like($page, qr/<a href="archive\/one.html">/, 'Archive news link'); # test 5
};

#----------------------------------------------------------------------
# Create index files

do {

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
<h1>{{title}}</h1>
<ul>
<!-- loop -->
<li><a href="{{url}}">{{title}}</a></li>
<!-- endloop -->
</ul>
<!-- endsection content -->
</body>
</html>
EOQ

    chdir($test_dir);
    my $idx = App::Followme::CreateNews->new($configuration);
    $idx->write_page('news_index_template.htm', $index_template);
    
    my $archive_dir = catfile($test_dir, 'archive');
    $idx->create_all_indexes($archive_dir);
    
    my $page = $idx->read_page(catfile($archive_dir,"index.html"));

    like($page, qr/>One<\/a><\/li>/, 'Archive index content'); # test 6
    like($page, qr/<a href="one.html">/, 'Archive index link'); # test 7
};
