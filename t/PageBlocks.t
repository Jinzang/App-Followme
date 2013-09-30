#!/usr/bin/env perl
use strict;

use IO::File;
use Test::More tests => 15;
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

require App::Followme::PageBlocks;

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
    
    my $decorated = 0;
    App::Followme::PageBlocks::parse_blocks($page, $decorated, $block_handler,
                                            $template_handler);

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
        App::Followme::PageBlocks::parse_blocks($page, $decorated,
                                                $block_handler,
                                                $template_handler);
    };
    is($@, "Unmatched block (<!-- section second -->)\n", 'Missing end'); # test 3

    @bad_page = @page;
    shift(@bad_page); shift(@bad_page);
    $page =join("\n", @bad_page) . "\n";

    eval {
        App::Followme::PageBlocks::parse_blocks($page, $decorated,
                                                $block_handler,
                                                $template_handler);
    };
    is($@, "Unmatched (<!-- endsection first -->)\n", 'Missing begin'); # test 4

    @bad_page = @page;
    splice(@bad_page, 3, 1);
    $page =join("\n", @bad_page) . "\n";

    eval {
        App::Followme::PageBlocks::parse_blocks($page, $decorated,
                                                $block_handler,
                                                $template_handler);
    };
    is($@, "Improperly nested block (<!-- section second -->)\n",
       'Begin inside of begin'); # test 5

    @bad_page = @page;
    splice(@bad_page, 3, 3);
    $page =join("\n", @bad_page) . "\n";

    eval {
        App::Followme::PageBlocks::parse_blocks($page, $decorated,
                                                $block_handler,
                                                $template_handler);
    };
    is($@, "Unmatched (<!-- endsection second -->)\n",
       'Begin does not match end'); # test 6
};

#----------------------------------------------------------------------
# Test parse_page

do {
    my @page = (
                "Top line",
                "<!-- section first -->",
                "First block",
                "<!-- endsection first -->",
                "Middle line",
                "<!-- section second -->",
                "Second block",
                "<!-- endsection second -->",
                "Last line",
               );

    my $decorated = 0;
    my $page = join("\n", @page) . "\n";
    my $blocks = App::Followme::PageBlocks::parse_page($page, $decorated);

    my $ok_blocks = {
        first => "\nFirst block\n",
        second => "\nSecond block\n",
    };
    
    is_deeply($blocks, $ok_blocks, 'Parse undecorated blocks'); # test 7

    $decorated = 1;
    $blocks = App::Followme::PageBlocks::parse_page($page, $decorated);

    $ok_blocks = {
        first => "<!-- section first -->\nFirst block\n<!-- endsection first -->",
        second => "<!-- section second -->\nSecond block\n<!-- endsection second -->",
    };

    is_deeply($blocks, $ok_blocks, 'Parse decorated blocks'); # test 8

    my $bad_page = $page;
    $bad_page =~ s/second/first/g;
    $blocks = eval {App::Followme::PageBlocks::parse_page($bad_page, $decorated)};
    
    is($@, "Duplicate block name (first)\n", 'Duplicate block names'); # test 9
};

#----------------------------------------------------------------------
# Test checksum_template and unchanged_template

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

    my $decorated = 0;
    my $template_path = {folder => 1};
    my $page_one = join("\n", @page) . "\n";
    my $checksum_one = App::Followme::PageBlocks::checksum_template($page_one,
                                                                    $decorated,
                                                                    $template_path);

    my $page_two = $page_one;
    $page_two =~ s/Second/2nd/g;
    my $checksum_two = App::Followme::PageBlocks::checksum_template($page_two,
                                                                    $decorated,
                                                                    $template_path);
    is($checksum_one, $checksum_two, 'Checksum same template'); # test 10    

    my $page_three = $page_one;
    $page_three =~ s/First/1st/g;
    my $checksum_three = App::Followme::PageBlocks::checksum_template($page_three,
                                                                      $decorated,
                                                                      $template_path);
    isnt($checksum_one, $checksum_three,
         'Checksum different template'); # test 11   

    my $flag = App::Followme::PageBlocks::unchanged_template($page_one,
                                                             $page_two,
                                                             $decorated,
                                                             $template_path);
                                                             
    is($flag, 1, 'Unchanged template, similar files'); # test 12

    $flag = App::Followme::PageBlocks::unchanged_template($page_one,
                                                          $page_three,
                                                          $decorated,
                                                          $template_path);
                                                             
    is($flag, 0, 'Unchanged template, dissimilar files'); # test 12
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

    my $decorated = 0;
    my $page = $template;
    $page =~ s/line/portion/g;
    $page =~ s/block/section/g;
    
    my $template_path = {folder => 1};
    my $output = App::Followme::PageBlocks::update_page($template, $page,
                                                        $decorated,
                                                        $template_path);
    my @output = split(/\n/, $output);
    
    my @output_ok = @template;
    $output_ok[6] =~ s/block/section/;

    is_deeply(\@output, \@output_ok, 'Update page'); # test 14

    my $bad_page = $page;
    $bad_page =~ s/second/third/g;

    $output = eval{App::Followme::PageBlocks::update_page($template, $bad_page,
                                                        $decorated, $template_path)};
    is($@, "Unused blocks (third)\n", 'Update page bad block'); # test 15
};
