#!/usr/bin/env perl
use strict;

use IO::File;
use Test::More tests => 12;

#----------------------------------------------------------------------
# Load package

my @path = split(/\//, $0);
pop(@path);

my $bin = join('/', @path);
my $lib = "$bin/../lib";
unshift(@INC, $lib);

require App::Followme;

my $test_dir = "$bin/../test";
system("/bin/rm -rf $test_dir");
mkdir $test_dir;
chdir $test_dir;

#----------------------------------------------------------------------
# Test parse_blocks

do {
    my $blocks = {};
    my $block_handler = sub {
        my ($blockname, $blocktext) = @_;
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
                "<!-- begin first -->",
                "First block",
                "<!-- end first -->",
                "Middle line",
                "<!-- begin second -->",
                "Second block",
                "<!-- end second -->",
                "Last line",
               );

    my $page = join("\n", @page) . "\n";
    
    App::Followme::parse_blocks($page, $block_handler, $template_handler);

    my $ok_blocks = {
        first => "\nFirst block\n",
        second => "\nSecond block\n",
    };

    my $ok_template = [
                        "Top line\n",
                        "<!-- begin first -->",
                        "<!-- end first -->",
                        "\nMiddle line\n",
                        "<!-- begin second -->",
                        "<!-- end second -->",
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
        App::Followme::parse_blocks($page, $block_handler, $template_handler);
    };
    is($@, "Unmatched block (<!-- begin second -->)\n", 'Missing end'); # test 3

    @bad_page = @page;
    shift(@bad_page); shift(@bad_page);
    $page =join("\n", @bad_page) . "\n";

    eval {
        App::Followme::parse_blocks($page, $block_handler, $template_handler);
    };
    is($@, "Unmatched (<!-- end first -->)\n", 'Missing begin'); # test 4

    @bad_page = @page;
    splice(@bad_page, 3, 1);
    $page =join("\n", @bad_page) . "\n";

    eval {
        App::Followme::parse_blocks($page, $block_handler, $template_handler);
    };
    is($@, "Improperly nested block (<!-- begin second -->)\n",
       'Begin inside of begin'); # test 5

    @bad_page = @page;
    splice(@bad_page, 3, 3);
    $page =join("\n", @bad_page) . "\n";

    eval {
        App::Followme::parse_blocks($page, $block_handler, $template_handler);
    };
    is($@, "Unmatched (<!-- end second -->)\n",
       'Begin does not match end'); # test 6
};

#----------------------------------------------------------------------
# Test parse_page

do {
    my @page = (
                "Top line",
                "<!-- begin first -->",
                "First block",
                "<!-- end first -->",
                "Middle line",
                "<!-- begin second -->",
                "Second block",
                "<!-- end second -->",
                "Last line",
               );

    my $page = join("\n", @page) . "\n";
    my $blocks = App::Followme::parse_page($page);

    my $ok_blocks = {
        first => "\nFirst block\n",
        second => "\nSecond block\n",
    };

    is_deeply($blocks, $ok_blocks, 'Parse blocks'); # test 7

    my $bad_page = $page;
    $bad_page =~ s/second/first/g;
    $blocks = eval {App::Followme::parse_page($bad_page)};
    
    is($@, "Duplicate block name (first)\n", 'Duplicate block names'); # test 8
};

#----------------------------------------------------------------------
# Test checksum_template

do {
    my @page = (
                "Top line",
                "<!-- begin first -->",
                "First block",
                "<!-- end first -->",
                "Middle line",
                "<!-- begin second -->",
                "Second block",
                "<!-- end second -->",
                "Last line",
               );

    my $page_one = join("\n", @page) . "\n";
    my $checksum_one = App::Followme::checksum_template($page_one);

    my $page_two = $page_one;
    $page_two =~ s/block/mock/g;
    my $checksum_two = App::Followme::checksum_template($page_two);
    is($checksum_one, $checksum_two, 'Checksum same template'); # test 9    

    my $page_three = $page_one;
    $page_three =~ s/line/part/g;
    my $checksum_three = App::Followme::checksum_template($page_three);
    isnt($checksum_one, $checksum_three,
         'Checksum different template'); # test 10   
};

#----------------------------------------------------------------------
# Test update_page

do {
    my @template = (
                "Top line",
                "<!-- begin first -->",
                "First block",
                "<!-- end first -->",
                "Middle line",
                "<!-- begin second -->",
                "Second block",
                "<!-- end second -->",
                "Last line",
               );

    my $template = join("\n", @template) . "\n";

    my $page = $template;
    $page =~ s/line/portion/g;
    $page =~ s/block/section/g;
    
    my $output = App::Followme::update_page($template, $page);
    my @output = split(/\n/, $output);
    
    my @output_ok = @template;
    $output_ok[2] =~ s/block/section/;
    $output_ok[6] =~ s/block/section/;

    is_deeply(\@output, \@output_ok, 'Update page'); # test 11

    my $bad_page = $page;
    $bad_page =~ s/second/third/g;

    $output = eval{App::Followme::update_page($template, $bad_page)};
    is($@, "Unused blocks (third)\n", 'Update page bad block'); # test 12
};

