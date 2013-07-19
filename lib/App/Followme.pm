package App::Followme;
use 5.008005;
use strict;
use warnings;

use IO::Dir;
use IO::File;
use Digest::MD5;

our $VERSION = "0.30";

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(configure_followme followme);

our %config = (
               checksum_file => 'followme.md5',
               index_root => 'index',
               top_title => 'home',
               html_extension => 'html',
               text_extension => 'txt',
               page_conversion => \&add_tags,
              );

use constant MONTHS => [qw(January February March April May June July
			   August September October November December)];

#----------------------------------------------------------------------
# Add paragraph tags to a text file

sub add_tags {
    my ($text) = @_;

    my @paragraphs = split(/(\n{2,})/, $text);

    my $pre;
    my $page = '';
    foreach my $paragraph (@paragraphs) {
        $pre = $paragraph =~ /<pre/i;            

        if (! $pre && $paragraph =~ /\S/) {
          $paragraph = "<p>$paragraph</p>"
                unless $paragraph =~ /^\s*</ && $paragraph =~ />\s*$/;
        }

        $pre = $pre && $paragraph !~ /<\/pre/i;
        $page .= $paragraph;
    }
    
    return $page;
}

#----------------------------------------------------------------------
# Build date fields from time, based on Blosxom 3

sub build_date {
    my ($time) = @_;
    
    my $num = '01';
    my $months = MONTHS;
    my %month2num = map {substr($_, 0, 3) => $num ++} @$months;

    my $ctime = localtime($time);
    my @names = qw(weekday month day hour24 minute second year);
    my @values = split(/\W+/, $ctime);

    my $data = {};
    while (@names) {
        my $name = shift @names;
        my $value = shift @values;
        $data->{$name} = $value;
    }

    $data->{day} = sprintf("%02d", $data->{day});
    $data->{monthnum} = $month2num{$data->{month}};

    my $hr = $data->{hour24};
    if ($hr < 12) {
        $data->{ampm} = 'am';
    } else {
        $data->{ampm} = 'pm';
        $hr -= 12;
    }

    $hr = 12 if $hr == 0;
    $data->{hour} = sprintf("%02d", $hr);

    return $data;
}

#----------------------------------------------------------------------
# Convert text file name to html file name

sub build_page_name {
    my ($filename) = @_;

    my @dirs = split(/\//, $filename);
    my $basename = pop(@dirs);
    my ($root, $ext) = split(/\./, $basename);

    my $page_name = join('.', $root, $config{html_extension});
    return join('/', @dirs, $page_name);
}

#----------------------------------------------------------------------
# Get the title from the filename root

sub build_title {
    my ($filename) = @_;
    
    my @dirs = split(/\//, $filename);
    my $basename = pop(@dirs);
    my ($root, $ext) = split(/\./, $basename);

    if ($root eq $config{index_root}) {
        $root = pop(@dirs) || $config{top_title};
    }
    
    my @words = map {ucfirst $_} split(/\-/, $root);
    return join(' ', @words);
}

#----------------------------------------------------------------------
# Get the url for a file from its name

sub build_url {
    my ($filename) = @_;
    
    my @dirs = split(/\//, $filename);
    my $basename = pop(@dirs);

    my $page_name;
    if ($basename !~ /\./) {
        push(@dirs, $basename);
        $page_name = join('.', $config{index_root}, $config{html_extension});
    } else {
        $page_name = build_page_name($basename);
    }
    
    return join('/', @dirs, $page_name);
}

#----------------------------------------------------------------------
# Detrmine if template has changes

sub changed_template {
    my ($template) = @_;
    
    my $new_checksum = checksum_template($template);
    my $old_checksum = read_page($config{checksum_file}) || '';
    chomp $old_checksum;

    my $changed = $new_checksum ne $old_checksum;
    write_page($config{checksum_file}, "$new_checksum\n") if $changed;

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
# Compile the template into a subroutine

sub compile_template {
    my ($filename) = @_;
    my $template = read_page($filename);
    
    my $code = <<'EOQ';
sub {
my ($data) = @_;
my $text = '';
EOQ

    my @tokens = split(/(<!--\s*(?:loop|endloop).*?-->)/, $template);
    
    foreach my $token (@tokens) {
        if ($token =~ /^<!--\s*loop/) {
            $code .= 'foreach my $data (@{$data->{loop}})' . "\n";

        } elsif ($token =~ /^<!--\s*endloop/) {
            $code .= "}\n";

        } else {
            $token =~ s/\$(\w+)/\$data->{$1}/g;
            $code .= "\$text .= <<\"EOQ\";\n";
            $code .= "${token}EOQ\n";
        }
    }
    
    $code .= <<'EOQ';
return $text;
}
EOQ

    my $sub = eval ($code);
    die $@ unless $sub;
    return $sub;
}

#----------------------------------------------------------------------
# Set or get configuration

sub configure_followme {
    my ($name, $value) = @_;
    
    die "Bad configuration field ($name)\n" unless exists $config{$name};
    
    $config{$name} = $value if defined $value;
    return $config{$name};
}

#----------------------------------------------------------------------
# Convert a text file to html

sub convert_a_file {
    my ($filename) = @_;

    my $converter = $config{page_conversion};
    my $data = get_data_for_file($filename);

    my $text = read_page($filename);
    die "Couldn't read $filename" unless defined $text;
    $data->{body} = $converter->($text);

    my $template = find_template($filename);
    my $sub = compile_template($template);
    my $page = $sub->($data);
 
    my $page_name = build_page_name($filename);
    write_page($page_name, $page);

    unlink($filename);
    return;    
}

#----------------------------------------------------------------------
# Convert all text files under a directory

sub convert_text_files {
    my $ext = $config{text_extension};
    my ($visit_dirs, $visit_files, $most_recent) = visitors($ext);
    
    my @converted_files;
    while (defined ($visit_dirs->())) {
        while (defined (my $filename = $visit_files->())) {
            eval {convert_a_file($filename)};

            if ($@) {
                warn "$filename: $@";
            } else {
                push(@converted_files, $filename);
            }
        }
    }
    
    return \@converted_files;
}

#----------------------------------------------------------------------
# Find the template file for a filename

sub find_template {
    my ($filename) = @_;   

    my @dirs = split(/\//, $filename);
    my $basename = pop(@dirs);
    my ($root, $ext) = split(/\./, $basename);
    $ext = $config{html_extension};

    for (;;) {
        my $template = join('/', @dirs, "${root}_template.$ext");
        return $template if -e $template;
        
        $template = join('/', @dirs, "template.$ext");
        return $template if -e $template;

        last unless @dirs;
        pop(@dirs);
    }

    die "Couldn't find template for $filename\n";
}

#----------------------------------------------------------------------
# Update a website based on changes to a file's template

sub followme {
    my ($top_dir) = @_;
    chdir($top_dir) if defined $top_dir;
    
    update_site();
    my $converted_files = convert_text_files();
    create_indexes($converted_files); # TODO

    return;
}

#----------------------------------------------------------------------
# Get the data used to construct a page

sub get_data_for_file {
    my ($filename) = @_;
    
    my @stats = stat($filename);
    my $data = build_date($stats[9]);

    $data->{title} = build_title($filename);
    $data->{url} = build_url($filename);
    
    return $data;
}

#----------------------------------------------------------------------
# Retrieve the data associated with a file

sub index_data {
    my ($index_dir) = @_;
    
    my $dd = IO::Dir->new($index_dir) or die "Couldn't open $index_dir: $!\n";

    my @dir_data;
    my @file_data;
    while (defined (my $file = $dd->read())) {
        my $path = catpath('', $index_dir, $file);
        
        if (-d $path) {
            next if $file =~ /^\./;

        } else {
            my ($root, $ext) = split(/\./, $file);
            next unless $ext eq $config{html_extension};
            next if $root =~ /template$/;
        }
        
        my $data = get_data_for_file($path);

        if (-d $path) {
            push(@dir_data, $data);
        } else {
            push(@file_data, $data);
        }
    }
    
    close($dd);
    
    my @loop = (@dir_data, @file_data);
    return \@loop;
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
# Update a website based on changes to a file's template

sub update_site {   
    my $template;
    my $ext = $config{html_extension};
    my ($visit_dirs, $visit_files, $most_recent) = visitors($ext);
    
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
# Return a closure that returns each file name

sub visitors {
    my ($ext) = @_;

    my @dirlist;
    my @filelist;
    my @stats = stat('.');
    push(@dirlist, [$stats[9], '.']);

    my $visit_dirs = sub {
        my $node = shift(@dirlist);
        return unless defined $node;

        my $dir = $node->[1];
        my $dd = IO::Dir->new($dir) or die "Couldn't open $dir: $!\n";

        # Find matching files and directories
        while (defined (my $file = $dd->read())) {
            my $path = $dir eq '.' ? $file : "$dir/$file";
            @stats = stat($path);
            
            if (-d $path) {
                next if $file    =~ /^\./;
                push(@dirlist, [$stats[9], $path]);
                
            } else {
                next unless $file =~ /^[^\.]+\.$ext$/;
                push(@filelist, [$stats[9], $path]);
            }
        }

        $dd->close;

        @dirlist = sort {$b->[0] <=> $a->[0]} @dirlist;
        @filelist = sort {$b->[0] <=> $a->[0]} @filelist;

        return $dir;
    };
    
    my $visit_files = sub {
        my $node = shift(@filelist);
        if (defined $node) {
            return $node->[1];
        } else {
            return;
        }
    };
    
    my $most_recent_files = sub {
        my ($limit) = @_;        
        while (@dirlist) {
            last if @filelist >= $limit &&
                    $filelist[$limit-1]->[0] > $dirlist[0]->[0];
            $visit_dirs->();
        }
        my @files;
        foreach my $i (0 .. $limit-1) {
            my $node = shift(@filelist);
            push(@files, $node->[1]);
        }
        return @files;
    };
        
    return ($visit_dirs, $visit_files, $most_recent_files);
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

App::Followme - Create a simple static website

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

