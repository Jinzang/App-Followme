#!/usr/bin/env perl
use strict;

use IO::File;
use Test::More tests => 25;
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

require App::Followme::FormatPages;

my $test_dir = catdir(@path, 'test');
system("/bin/rm -rf $test_dir");
mkdir $test_dir;
mkdir "$test_dir/sub";
chdir $test_dir;

#----------------------------------------------------------------------
# Test parse_blocks

do {
    my $blocks = {};
    my $block_handler = sub {
        my ($blockname, $in, $blocktext) = @_;
        $blocks->{$blockname} = $blocktext;
        return;
    };
    
    my $template = [];
    my $template_handler = sub {
        my ($blocktext) = @_;
        push(@$template, $blocktext);
        return;
    };
    
    my @page = (
                "Top line",
                "<!-- section first in folder -->",
                "First block",
                "<!-- endsection first -->",
                "Middle line",
                "<!-- section second -->",
                "Second block",
                "<!-- endsection second -->",
                "Last line",
               );

    my $page = join("\n", @page) . "\n";
    
    my $up = App::Followme::FormatPages->new({});
    $up->parse_blocks($page, $block_handler, $template_handler);

    my $ok_blocks = {
        first => "\nFirst block\n",
        second => "\nSecond block\n",
    };

    my $ok_template = [
                        "Top line\n",
                        "<!-- section first in folder -->",
                        "<!-- endsection first -->",
                        "\nMiddle line\n",
                        "<!-- section second -->",
                        "<!-- endsection second -->",
                        "\nLast line\n",
                           ];

    is_deeply($blocks, $ok_blocks, 'Parse blocks'); # test 1
    is_deeply($template, $ok_template, 'Parse template'); # test 2
    
    $blocks = {};
    $template = [];
    my @bad_page = @page;
    pop(@bad_page); pop(@bad_page);
    $page =join("\n", @bad_page) . "\n";

    eval {
        $up->parse_blocks($page, $block_handler, $template_handler);
    };
    is($@, "Unmatched block (<!-- section second -->)\n", 'Missing end'); # test 3

    @bad_page = @page;
    shift(@bad_page); shift(@bad_page);
    $page =join("\n", @bad_page) . "\n";

    eval {
        $up->parse_blocks($page, $block_handler, $template_handler);
    };
    is($@, "Unmatched (<!-- endsection first -->)\n", 'Missing begin'); # test 4

    @bad_page = @page;
    splice(@bad_page, 3, 1);
    $page =join("\n", @bad_page) . "\n";

    eval {
        $up->parse_blocks($page, $block_handler, $template_handler);
    };
    is($@, "Improperly nested block (<!-- section second -->)\n",
       'Begin inside of begin'); # test 5

    @bad_page = @page;
    splice(@bad_page, 3, 3);
    $page =join("\n", @bad_page) . "\n";

    eval {
        $up->parse_blocks($page, $block_handler, $template_handler);
    };
    is($@, "Unmatched (<!-- endsection second -->)\n",
       'Begin does not match end'); # test 6
};

#----------------------------------------------------------------------
# Test parse_page

do {
    my @page = (
                "Top line",
                "<!-- section first in folder -->",
                "First block",
                "<!-- endsection first -->",
                "Middle line",
                "<!-- section second -->",
                "Second block",
                "<!-- endsection second -->",
                "Last line",
               );

    my $page = join("\n", @page) . "\n";
    my $up = App::Followme::FormatPages->new({});
    my $blocks = $up->parse_page($page);

    my $ok_blocks = {
        first => "\nFirst block\n",
        second => "\nSecond block\n",
    };

    is_deeply($blocks, $ok_blocks, 'Parse blocks'); # test 7

    my $bad_page = $page;
    $bad_page =~ s/second/first/g;
    $blocks = eval {$up->parse_page($bad_page)};
    
    is($@, "Duplicate block name (first)\n", 'Duplicate block names'); # test 8
};

#----------------------------------------------------------------------
# Test checksum_template

do {
    my @page = (
                "Top line",
                "<!-- section first in folder -->",
                "First block",
                "<!-- endsection first -->",
                "Middle line",
                "<!-- section second -->",
                "Second block",
                "<!-- endsection second -->",
                "Last line",
               );

    my $up = App::Followme::FormatPages->new({});

    my $template_path = {folder => 1};
    my $page_one = join("\n", @page) . "\n";
    my $checksum_one = $up->checksum_template($page_one, $template_path);

    my $page_two = $page_one;
    $page_two =~ s/Second/2nd/g;
    my $checksum_two = $up->checksum_template($page_two, $template_path);
    is($checksum_one, $checksum_two, 'Checksum same template'); # test 9    

    my $page_three = $page_one;
    $page_three =~ s/First/1st/g;
    my $checksum_three = $up->checksum_template($page_three, $template_path);
    isnt($checksum_one, $checksum_three,
         'Checksum different template'); # test 10   
};

#----------------------------------------------------------------------
# Test update_page

do {
    my @template = (
                "Top line",
                "<!-- section first in folder -->",
                "First block",
                "<!-- endsection first -->",
                "Middle line",
                "<!-- section second -->",
                "Second block",
                "<!-- endsection second -->",
                "Last line",
               );

    my $template = join("\n", @template) . "\n";

    my $page = $template;
    $page =~ s/line/portion/g;
    $page =~ s/block/section/g;
    
    my $up = App::Followme::FormatPages->new({});
    my $template_path = {folder => 1};
    my $output = $up->update_page($template, $page, $template_path);
    my @output = split(/\n/, $output);
    
    my @output_ok = @template;
    $output_ok[6] =~ s/block/section/;

    is_deeply(\@output, \@output_ok, 'Update page'); # test 11

    my $bad_page = $page;
    $bad_page =~ s/second/third/g;

    $output = eval{$up->update_page($template, $bad_page, $template_path)};
    is($@, "Unused blocks (third)\n", 'Update page bad block'); # test 12
};

#----------------------------------------------------------------------
# Test read and write pages

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
<p><a href="">&&</a></p>
</body>
</html>
EOQ

    my $up = App::Followme::FormatPages->new({});

    foreach my $dir (('sub', '')) {
        foreach my $count (qw(four three two one)) {
            sleep(1);
            my $output = $code;
            $output =~ s/%%/Page $count/g;
            $output =~ s/&&/$dir link/g;

            my $filename = $dir ? "$dir/$count.html" : "$count.html";
            $up->write_page($filename, $output);
    
            my $input = $up->read_page($filename);
            is($input, $output, "Read and write page $filename"); #tests 13-20
        }
    }
};
#----------------------------------------------------------------------
# Test make template

do {
    my $bottom = "$test_dir/sub";
    chdir($bottom);

    my $up = App::Followme::FormatPages->new({base_dir => $test_dir});
    my $template_path = $up->get_template_path('one.html');
    
    is_deeply($template_path, {sub => 1}, 'Get template path'); # test 21
    
    my $template_file = $up->find_template();
    is($template_file, "$test_dir/one.html", 'Find template'); # test 22

    my $template = $up->make_template('two.html');
    ok($template =~ /Page two/, "Make template top level"); # test 23
    
    $template = $up->make_template('three.html');
    ok($template =~ /Page three/, "Make template body"); # test 24
    ok($template !~ /sub link/, "Make template link"); # test 25
};