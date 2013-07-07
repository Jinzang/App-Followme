#!/usr/bin/env perl
use strict;

use IO::File;
use Test::More tests => 2;

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
# Test parsing

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
};
