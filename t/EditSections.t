use File::Path qw(rmtree);
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

use Test::More tests => 5;

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

require App::Followme::EditSections;

my $test_dir = catdir(@path, 'test');

rmtree($test_dir);
mkdir $test_dir;
chdir $test_dir;

my $configuration = {
                    remove_comments => 0,
                    };

#----------------------------------------------------------------------
# Write test pages

do {
   my $page = <<'EOQ';
<html>
<head>
<meta name="robots" content="archive">
<!-- begin meta -->
<title>page %%</title>
<!-- end meta -->
</head>
<body>
<!-- begin content -->
<h1>page %%</h1>
<!-- end content -->
<ul>
<li><a href="">&& link</a></li>
<!-- begin nav -->
<li><a href="">link %%</a></li>
<!-- end nav -->
</ul>
</body>
</html>
EOQ

    my $es = App::Followme::EditSections->new($configuration);

    foreach my $count (qw(four three two one)) {
        my $output = $page;

        $output =~ s/%%/$count/g;

        if ($count eq 'one') {
            $output =~ s/begin/section/g;
            $output =~ s/end/endsection/g;
        }

        my $filename = "$count.html";
        $es->write_page($filename, $output);
        sleep(2);
    }
};

#----------------------------------------------------------------------
# Test comment removal

do {
    my $es = App::Followme::EditSections->new($configuration);

    my $output = $es->strip_comments('one.html', 1);
    my $output_ok = $es->read_page('one.html');
    is($output, $output_ok, 'strip comments, keep sections'); # test 1

    $output = $es->strip_comments('one.html', 0);
    $output_ok =~ s/(<!--.*?-->)//g;
    is($output, $output_ok, 'strip comments and sections'); # test 2

    $output = $es->strip_comments('two.html', 0);
    $output_ok = $es->read_page('two.html');
    is($output, $output_ok, 'don\'t strip comments'); # test 3

    $configuration->{remove_comments} = 1;
    $es = App::Followme::EditSections->new($configuration);

    $output = $es->strip_comments('two.html', 0);
    $output_ok =~ s/(<!--.*?-->)//g;
    is($output, $output_ok, 'strip comments'); # test 4
};

#----------------------------------------------------------------------
# Test update page

do {
    my $es = App::Followme::EditSections->new($configuration);

    my $prototype = $es->strip_comments('one.html', 1);
    $es->update_page('two.html', $prototype);

    my $output = $es->read_page('two.html');
    my $output_ok = $es->read_page('one.html');
    $output_ok =~ s/one/two/g;

    is($output, $output_ok, 'update page'); # test 5
};
