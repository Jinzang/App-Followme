#!/usr/bin/env perl
use strict;

use IO::File;
use Test::More tests => 21;
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

require App::Followme::FormatPages;
require App::Followme::PageIO;

my $test_dir = catdir(@path, 'test');
system("/bin/rm -rf $test_dir");
mkdir $test_dir;
mkdir "$test_dir/sub";
chdir $test_dir;

#----------------------------------------------------------------------
# Write test pages

do {
   my $code = <<'EOQ';
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
<!-- endsection content -->
<ul>
<li><a href="">&& link</a></li>
<!-- section nav -->
<li><a href="">link %%</a></li>
<!-- endsection nav -->
</ul>
</body>
</html>
EOQ

    my $up = App::Followme::FormatPages->new({});

    foreach my $dir (('sub', '')) {
        foreach my $count (qw(four three two one)) {
            sleep(1);
            my $output = $code;
            my $dir_name = $dir ? $dir : 'top';
            
            $output =~ s/%%/$count/g;
            $output =~ s/&&/$dir_name/g;
            $output =~ s/section nav/section nav in $dir/ if $dir;

            my $filename = $dir ? "$dir/$count.html" : "$count.html";
            App::Followme::PageIO::write_page($filename, $output);
        }
    }
};

#----------------------------------------------------------------------
# Test get template path and find template

do {
    my $bottom = "$test_dir/sub";
    chdir($bottom);

    my $up = App::Followme::FormatPages->new({base_dir => $test_dir});
    my $template_path = $up->get_template_path('one.html');
    
    is_deeply($template_path, {sub => 1}, 'Get template path'); # test 1
    
    my $template_file = $up->find_template();
    is($template_file, catfile($test_dir, 'one.html'),
       'Find template'); # test 2
};

#----------------------------------------------------------------------
# Test run

do {
    my $up = App::Followme::FormatPages->new({base_dir => $test_dir,
                                              options => {all => 1}});
    foreach my $dir (('', 'sub')) {
        my $path = $dir ? catfile($test_dir, $dir) : $test_dir;
        chdir ($path);
        $up->run();

        foreach my $count (qw(two one)) {
            my $filename = "$count.html";
            my $input = App::Followme::PageIO::read_page($filename);

            ok($input =~ /Page $count/,
               "Format block in $dir/$count"); # test 3, 7, 11, 15
            
            ok($input =~ /top link/,
               "Format template $dir/$count"); # test 4, 8, 12 16

            if ($dir) {
                ok($input =~ /section nav in sub --/,
                   "Format section tag in $dir/$count"); # test 13, 17
                ok($input =~ /link one/,
                   "Format folder block $dir/$count"); # test 14, 18
                
            } else {
                ok($input =~ /section nav --/, 
                   "Format section tag in $dir/$count"); # test 5, 9
                ok($input =~ /link $count/, 
                   "Format folder block in $dir/$count"); # test 6, 12
            }
        }
    }
}