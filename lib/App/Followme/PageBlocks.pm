package App::Followme::PageBlocks;
use 5.008005;
use strict;
use warnings;

use Digest::MD5 qw(md5_hex);
our $VERSION = "0.90";

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(unchanged_template update_page);

#----------------------------------------------------------------------
# Compute checksum for constant sections of page

sub checksum_template {
    my ($template, $decorated, $template_path) = @_;    

    my $md5 = Digest::MD5->new;

    my $block_handler = sub {
        my ($blockname, $locality, $blocktext) = @_;
        $md5->add($blocktext) if exists $template_path->{$locality};
    };
    
    my $template_handler = sub {
        my ($blocktext) = @_;
        $md5->add($blocktext);
        return;
    };

    parse_blocks($template, $decorated, $block_handler, $template_handler);

    return $md5->hexdigest;
}

#----------------------------------------------------------------------
# Parse fields out of block tag

sub parse_blockname {
    my ($str) = @_;
    
    my ($blockname, $in, $locality) = split(/\s+/, $str);
    
    if ($in) {
        die "Syntax error in block ($str)"
            unless $in eq 'in' && defined $locality;
    } else {
        $locality = '';
    }
    
    return ($blockname, $locality);
}

#----------------------------------------------------------------------
# Break page into template and blocks

sub parse_blocks {
    my ($page, $decorated, $block_handler, $template_handler) = @_;
    
    my $locality;
    my $block = '';
    my $blockname = '';
    my @tokens = split(/(<!--\s*(?:section|endsection)\s+.*?-->)/, $page);
    
    foreach my $token (@tokens) {
        if ($token =~ /^<!--\s*section\s+(.*?)-->/) {
            die "Improperly nested block ($token)\n" if $blockname;
                
            ($blockname, $locality) = parse_blockname($1);
            if ($decorated) {
                $block .= $token
            } else {
                $template_handler->($token);
            }
            
        } elsif ($token =~ /^<!--\s*endsection\s+(.*?)-->/) {
            my ($endname) = parse_blockname($1);
            die "Unmatched ($token)\n"
                if $blockname eq '' || $blockname ne $endname;
                
            if ($decorated) {
                $block .= $token;
                $block_handler->($blockname, $locality, $block);
            } else {
                $block_handler->($blockname, $locality, $block);
                $template_handler->($token);
            }

            $block = '';
            $blockname = '';

        } else {
            if ($blockname) {
                $block .= $token;
            } else {
                $template_handler->($token);
            }            
        }
    }
 
    die "Unmatched block (<!-- section $blockname -->)\n" if $blockname;
    return;
}

#----------------------------------------------------------------------
# Extract named blocks from a page

sub parse_page {
    my ($page, $decorated) = @_;
    
    my $blocks = {};
    my $block_handler = sub {
        my ($blockname, $locality, $blocktext) = @_;
        if (exists $blocks->{$blockname}) {
            die "Duplicate block name ($blockname)\n";
        }
        $blocks->{$blockname} = $blocktext;
        return;
    };
    
    my $template_handler = sub {
        return;
    };

    parse_blocks($page, $decorated, $block_handler, $template_handler);    
    return $blocks;
}

#----------------------------------------------------------------------
# Determine if page matches template or needs to be updated

sub unchanged_template {
    my ($template, $page, $decorated, $template_path) = @_;
    
    my $template_checksum = checksum_template($template,
                                              $decorated,
                                              $template_path);
    my $page_checksum = checksum_template($page,
                                          $decorated,
                                          $template_path);

    my $unchanged;
    if ($template_checksum eq $page_checksum) {
        $unchanged = 1;
    } else {
        $unchanged = 0;
    }
    
    return $unchanged;
}

#----------------------------------------------------------------------
# Parse template and page and combine them

sub update_page {
    my ($template, $page, $decorated, $template_path) = @_;

    my $output = [];
    my $blocks = parse_page($page, $decorated);
    
    my $block_handler = sub {
        my ($blockname, $locality, $blocktext) = @_;
        if (exists $blocks->{$blockname}) {
            if (exists $template_path->{$locality}) {
                push(@$output, $blocktext);          
            } else {
                push(@$output, $blocks->{$blockname});
            }
            delete $blocks->{$blockname};
        } else {
            push(@$output, $blocktext);
        }
        return;
    };

    my $template_handler = sub {
        my ($blocktext) = @_;
        push(@$output, $blocktext);
        return;
    };

    parse_blocks($template, $decorated, $block_handler, $template_handler);

    if (%$blocks) {
        my $names = join(' ', sort keys %$blocks);
        die "Unused blocks ($names)\n";
    }
    
    return join('', @$output);
}

1;
__END__

=encoding utf-8

=head1 NAME

App::Followme::PageBlocks - Update pages from template divided into blocks

=head1 SYNOPSIS

    use App::Followme::PageBlocks qw(unchanged_template update_page);

    $page = update_page($template, $page,
                        $decorated, $template_path);

    my $flag = unchanged_template($template, $page,
                                  $decorated, $template_path);

=head1 DESCRIPTION

App::Followme::PageBlocks exports two functions. The principal one,
update_page, updates the constant portions of a web page from a template. 
Each html page has sections that are different from other pages and other
sections that are the same. The sections that differ are enclosed in html
comments that look like

    <!-- section name-->
    <!-- endsection name -->

and indicate where the section begins and ends. A page is
updated by substituting all its named blocks into corresponding block in the
template. The effect is that all the text outside the named blocks are
updated to be same as the text in the template.

Updates to the named block can also be made conditional by adding an in after
the section name. If the folder name after the "in" is included in the
template_path hash, then the block tags are ignored, it is as if the block does
not exist. The block is considered as part of the constant portion of the
template. If the folder is not in the template_path, the block is treated as
any other block and varies from page to page.

    <!-- section name in folder -->
    <!-- endsection name -->

Text in conditional blocks can be used for navigation or other sections of the
page that are constant, but not constant across the entire site.

=head1 FUNCTIONS

=over 4

=item $page = update_page($template, $page, $decorated, $template_path);

This function combines the contents of a template and page to create a new page,
as described above. Both template and page are strings, not filenames. The
argument decorated controls whether the section comment tags are copied from the
template or page. If decorated is true, the section tags are treated as part of
the block and are copied from the page. If decorated is false, the section tags
are copied from the template. Template_path is a hash containing the directories
from the base directory of the web site down to the directory containing the
template. The hash is treated as a set, that is, the directory names are the
keys and the values of the keys are one/

=item $flag = unchanged_template($template, $page, $decorated, $template_path);

Return true if running update_page would leave the page unchanged, false if it
would change the page. The arguments are the same as update_page.

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut

