#!/usr/bin/env perl
use strict;

use IO::File;
use File::Path qw(rmtree);
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

use Test::More tests => 1;

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

require App::Followme::CreateSitemap;

my $test_dir = catdir(@path, 'test');

rmtree($test_dir);
mkdir $test_dir;
mkdir catfile($test_dir, "sub");
chdir $test_dir;

#----------------------------------------------------------------------
# Create pages to list in sitemap

do {
   my $page = <<'EOQ';
<html>
<head>
<meta name="robots" content="archive">
<!-- section meta -->
<title>Page %%</title>
<!-- endsection meta -->
</head>
<body>
<!-- section content -->
<h1>Page %%</h1>

<p>All about %%.</p>
<!-- endsection content -->
</body>
</html>
EOQ

    my $configuration = {
            site_url => 'http://www.example.com',
            sitemap => 'sitemap.txt',
            web_extension => 'html',
            };

    my $map = App::Followme::CreateSitemap->new($configuration);

    my @webpages;
    foreach my $count (qw(first second third)) {
        my $output = $page;
        $output =~ s/%%/$count/g;
        
        my $filename = "$count.html";
        $map->write_page($filename, $output);

        my $data = {};
        $map->build_url($data, $test_dir, $filename);

        my $webpage = $configuration->{site_url} . $data->{absolute_url};
        push(@webpages, $webpage);
    }

    @webpages = sort @webpages;
    my @urls = sort $map->list_urls($test_dir);
    is_deeply(\@urls, \@webpages, 'create sitemap'); # test 1
};
