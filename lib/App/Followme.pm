package App::Followme;
use 5.008005;
use strict;
use warnings;

use IO::File;
use Digest::MD5;

our $VERSION = "0.01";

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(followme);

use constant CHECKSUM_FILE => 'followme.md5';
use constant DEFAULT_EXTENSION => 'html';

#----------------------------------------------------------------------
# Update a website based on changes to a file

sub followme {
    my ($template_name) = @_;
    
    my $ext;
    if (defined $template_name) {
        my $base;
        ($base, $ext) = split(/\./, $template_name);
    } else {
        $ext = DEFAULT_EXTENSION;
    }
    
    my @filenames = sort_by_date(glob("*.$ext"));
    unshift(@filenames, $template_name) if defined $template_name;
    
    update_site(@filenames);
    return;
}

#----------------------------------------------------------------------
# Detrmine if template has changes

sub changed_template {
    my ($template) = @_;
    
    my $new_checksum = checksum_template($template);
    my $old_checksum = read_page(CHECKSUM_FILE) || '';
    chomp $old_checksum;
    
    write_page(CHECKSUM_FILE, "$new_checksum\n");
    return $new_checksum ne $old_checksum;
}

#----------------------------------------------------------------------
# Compute checksum for template

sub checksum_template {
    my ($template) = @_;    

    my $md5 = Digest::MD5->new;

    my $block_handler = sub {
        return;
    };
    
    my $template_handler = sub {
        my ($blocktext) = @_;
        $md5->add($blocktext);
        return;
    };

    parse_blocks($template, $block_handler, $template_handler);    
    return $md5->hexdigest;
}

#----------------------------------------------------------------------
# Break page into template and blocks

sub parse_blocks {
    my ($page, $block_handler, $template_handler) = @_;
    
    my $blockname = '';
    my $blocktext = '';
    my @tokens = split(/(<!--\s*(?:begin|end).*?-->)/, $page);
    
    foreach my $token (@tokens) {
        if ($token =~ /^<!--\s*begin\s+(\S+)/) {
            die "Improperly nested block $token\n" if $blockname;
                
            $blockname = $1;
            $template_handler->($token);
            
        } elsif ($token =~ /^<!--\s*end\s+(\S+)/) {
            die "Unmatched $token\n"
                if $blockname eq '' || $blockname ne $1;
                
            $block_handler->($blockname, $blocktext);
            $template_handler->($token);
            $blockname = '';
            $blocktext = '';
             
        } else {
            if ($blockname) {
                $blocktext = $token;
            } else {
                $template_handler->($token);
            }            
        }
    }
 
    die "Unmatched block <!-- begin $blockname -->\n" if $blockname;
    return;
}

#----------------------------------------------------------------------
# Extract named blocks from a page

sub parse_page {
    my ($page) = @_;
    
    my $blocks = {};
    my $block_handler = sub {
        my ($blockname, $blocktext) = @_;
        if (exists $blocks->{$blockname}) {
            die "Duplicate block name $blockname\n";
        }
        $blocks->{$blockname} = $blocktext;
        return;
    };
    
    my $template_handler = sub {
        return;
    };

    parse_blocks($page, $block_handler, $template_handler);    
    return $blocks;
}

#----------------------------------------------------------------------
# Read a file into a string

sub read_page {
    my ($filename) = @_;

    local $/;
    my $fd = IO::File->new($filename, 'r');
    return unless $fd;
    
    my $page = <$fd>;
    close($fd);
    
    return $page;
}

#----------------------------------------------------------------------
# Sort a list of files by modification date

sub sort_by_date {
    my @filenames = @_;

    my @augmented;
    foreach (@filenames) {
        push(@augmented, [-M, $_]);
    }

    @augmented = sort {$a->[0] <=> $b->[0]} @augmented;
    @filenames =  map {$_->[1]} @augmented;

    return @filenames;    
}

#----------------------------------------------------------------------
# Parse template and page and combine them

sub update_page {
    my ($template, $page) = @_;

    my $output = [];
    my $blocks = parse_page($page);
    
    my $block_handler = sub {
        my ($blockname, $blocktext) = @_;
        if (exists $blocks->{$blockname}) {
            push(@$output, $blocks->{$blockname});
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

    parse_blocks($template, $block_handler, $template_handler);    
    return join('', @$output);
}

#----------------------------------------------------------------------
# Update a list of pages to match a changed template

sub update_site {
    my ($template_name, @filenames) = @_;
    
    my $template = read_page($template_name);
    die "Couldn't read $template_name" unless defined $template;
    
    return unless changed_template($template);
    
    foreach my $filename (@filenames) {
        next if $filename eq $template_name;
        
        my $page = read_page($filename);
        if (! defined $page) {
            warn "Couldn't read $filename";
            next;
        }
        
        if (! unlink($filename)) {
            warn "Can't remove old $filename";
            next;
        }

        my $new_page = eval {update_page($template, $page)};
    
        if ($@) {
            warn "$filename: $@";
            undef $new_page;
        }

        if (defined $new_page) {
            write_page($filename, $new_page);
        } else {
            write_page($filename, $page);
        }
    }
    
    return;
}

#----------------------------------------------------------------------
# Read a file into a string

sub write_page {
    my ($filename, $page) = @_;

    my $fd = IO::File->new($filename, 'w');
    die "Couldn't write $filename" unless $fd;
    
    print $fd $page;
    close($fd);
    
    return;
}

1;
__END__

=encoding utf-8

=head1 NAME

App::Followme - A template-less html templating script

=head1 SYNOPSIS

    use App::Followme;
    followme();

=head1 DESCRIPTION

Followme is an html template processor. It produces a new html file
from a template and an old html file. The purpose if this script is to
keep html files in synch with a template. One changes the template and
then runs this script to propogate the changes in the template to the
other html files.

Followme works by combining text from a template and an input page to
build the ouput page. Both files have blocks of code surrounded by
comments that look like

    <!-- begin name-->
    <!-- end name -->

The output file is the template file with all the named blocks
replaced by the corresponding block in the input file. The effect is
that all code outside the named blocks are updated.


=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut

