package App::Followme;
use 5.008005;
use strict;
use warnings;

use IO::Dir;
use IO::File;
use Digest::MD5;

our $VERSION = "0.20";

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(configure_followme followme);

our %configuration = (checksum_file => 'followme.md5',
                      default_extension => 'html',
                     );

#----------------------------------------------------------------------
# Detrmine if template has changes

sub changed_template {
    my ($template) = @_;
    
    my $new_checksum = checksum_template($template);
    my $old_checksum = read_page($configuration{checksum_file}) || '';
    chomp $old_checksum;

    my $changed = $new_checksum ne $old_checksum;
    write_page($configuration{checksum_file}, "$new_checksum\n") if $changed;

    return $changed;
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

sub configure_followme {
    my ($name, $value) = @_;
    
    die "Bad configuration field ($name)\n" unless exists $configuration{$name};
    
    $configuration{$name} = $value if defined $value;
    return $configuration{$name};
}

#----------------------------------------------------------------------
# Update a website based on changes to a file

sub followme {
    my ($dir) = @_;
    $dir = '.' unless defined $dir;
    
    my $template;
    my $ext = $configuration{default_extension};
    my ($visit_dirs, $visit_files) = visitors($dir, $ext);
    
    while (defined $visit_dirs->()) {
        while (defined (my $filename = $visit_files->())) {        
    
            if (defined $template) {
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

            } else {
                $template = read_page($filename);
                die "Couldn't read $filename" unless defined $template;    
                return unless changed_template($template);                
            }
        }
    }
    
    return;
}

#----------------------------------------------------------------------
# Return a list of files most recently modified

sub most_recent_files {
    my ($dir, $n) = @_;
    
    my $ext = $configuration{default_extension};
    my ($visit_dirs, $visit_files) = visitors($dir, $ext);

    my @recent;
    $visit_dirs->();

    foreach my $i (1 .. $n) {
        my $filename = $visit_files->();
        last unless $filename;
        
        push(@recent, $filename);
    }

    return @recent;
}

#----------------------------------------------------------------------
# Break page into template and blocks

sub parse_blocks {
    my ($page, $block_handler, $template_handler) = @_;
    
    my $blockname = '';
    my @tokens = split(/(<!--\s*(?:begin|end).*?-->)/, $page);
    
    foreach my $token (@tokens) {
        if ($token =~ /^<!--\s*begin\s+(\S+)/) {
            die "Improperly nested block ($token)\n" if $blockname;
                
            $blockname = $1;
            $template_handler->($token);
            
        } elsif ($token =~ /^<!--\s*end\s+(\S+)/) {
            die "Unmatched ($token)\n"
                if $blockname eq '' || $blockname ne $1;
                
            $blockname = '';
            $template_handler->($token);

        } else {
            if ($blockname) {
                $block_handler->($blockname, $token);
            } else {
                $template_handler->($token);
            }            
        }
    }
 
    die "Unmatched block (<!-- begin $blockname -->)\n" if $blockname;
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
            die "Duplicate block name ($blockname)\n";
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
    foreach my $filename (@filenames) {
        my @stats = stat($filename);
        push(@augmented, [$stats[9], $filename]);
    }

    @augmented = sort {$b->[0] <=> $a->[0]} @augmented;
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

    parse_blocks($template, $block_handler, $template_handler);

    if (%$blocks) {
        my $names = join(' ', sort keys %$blocks);
        die "Unused blocks ($names)\n";
    }
    
    return join('', @$output);
}

#----------------------------------------------------------------------
# Return a closure that returns each file name

sub visitors {
    my ($top_dir, $ext) = @_;

    my @dirlist;
    my @filelist;
    push(@dirlist, $top_dir);

    my $visit_dirs = sub {
        my $dir = shift(@dirlist);
        return unless defined $dir;

        my $dd = IO::Dir->new($dir) or die "Couldn't open $dir: $!\n";

        # Find matching files and directories
        while (defined (my $file = $dd->read())) {
            my $path = "$dir/$file";
            
            if (-d $path) {
                next if $file    =~ /^\./;
                push(@dirlist, $path);
                
            } else {
                next unless $file =~ /^[^\.]+\.$ext$/;
                push(@filelist, $path);
            }
        }

        $dd->close;

        @dirlist = sort_by_date(@dirlist);
        @filelist = sort_by_date(@filelist);

        return $dir;
    };
    
    my $visit_files = sub {
        return shift(@filelist);
    };
    
    return $visit_dirs, $visit_files;
}

#----------------------------------------------------------------------
# Write the page back to the file

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

App::Followme - A template-less html templating system

=head1 SYNOPSIS

    use App::Followme qw(followme);
    followme();

=head1 DESCRIPTION

Followme is an html template processsor where every file is the template. It
takes the most recently changed html file in the current directory as the
template and modifies the other html files in the directory to match it. Every
file has blocks of code surrounded by comments that look like

    <!-- begin name-->
    <!-- end name -->

The new page is the template file with all the named blocks replaced by the
corresponding block in the old page. The effect is that all the code outside 
the named blocks are updated to be the same across all the html pages.

This module exports one function, followme. It takes one or no arguments. If
an argument is given, it is the extension used on all the html files. If no
argument is given, the extension is taken to be html.

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut

