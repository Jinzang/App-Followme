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
               text_extension => 'txt',
               archive_index_length => 5,
               archive_index => 'blog.html',
               archive_directory => 'archive',
               body_tag => 'content',
               page_converter => \&add_tags,
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

    my $page_name = "$root.html";
    return join('/', @dirs, $page_name);
}

#----------------------------------------------------------------------
# Get the title from the filename root

sub build_title {
    my ($filename) = @_;
    
    my @dirs = split(/\//, $filename);
    my $basename = pop(@dirs);
    my ($root, $ext) = split(/\./, $basename);

    if ($root eq 'index') {
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
        $page_name = 'index.html';

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
            $code .= 'foreach my $data (@{$data->{loop}}) {' . "\n";

        } elsif ($token =~ /^<!--\s*endloop/) {
            $code .= "}\n";

        } else {
            $token =~ s/\$(\w+)/\$data->{$1}/g;
            $code .= "\$text .= <<\"EOQ\";\n";
            $code .= "${token}\nEOQ\n";
            $code .= "chomp \$text;\n";
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

    my $converter = $config{page_converter};
    my $data = get_data_for_file($filename);

    my $text = read_page($filename);
    die "Couldn't read $filename" unless defined $text;
    $data->{body} = $converter->($text);

    my $template = find_template($filename);
    my $sub = compile_template($template);
    my $page = $sub->($data);
 
    my $page_name = build_page_name($filename);
    write_page($page_name, $page);

    return;    
}

#----------------------------------------------------------------------
# Convert all text files under a directory

sub convert_text_files {
    my $ext = $config{text_extension};
    my ($visit_dirs, $visit_files) = visitors($ext);
    
    my @converted_files;
    while (defined ($visit_dirs->())) {
        while (defined (my $filename = $visit_files->())) {
            eval {convert_a_file($filename)};

            if ($@) {
                warn "$filename: $@";
            } else {
                push(@converted_files, $filename);
                unlink($filename);
            }
        }
    }
    
    return \@converted_files;
}

#----------------------------------------------------------------------
# Create an index filr

sub create_an_index {
    my ($index_file) = @_;

    my $data = index_data($index_file);
    my $template = find_template($index_file);
    my $sub = compile_template($template);
    my $page = $sub->($data);
 
    write_page($index_file, $page);
    return;
}

#----------------------------------------------------------------------
# Create the index of most recent additions to the archive

sub create_archive_index {
    my ($archive_index) = @_;

    my $archive_dir = $config{archive_directory};
    my $data = recent_archive_data($archive_index, $archive_dir);
    my $template = find_template($archive_index);
    my $sub = compile_template($template);
    my $page = $sub->($data);
 
    write_page($archive_index, $page);
    return;
}

#----------------------------------------------------------------------
# Create index pages for archived files

sub create_indexes {
    my ($converted_files) = @_;

    my @index_files = get_indexes($converted_files);
    return unless @index_files;
    
    foreach my $index_file (@index_files) {
        eval {create_an_index($index_file)};
        warn "$index_file: $@" if $@;
    }

    eval {create_archive_index($config{archive_index})};
    warn "$config{archive_index}: $@" if $@;
    
    return;
}

#----------------------------------------------------------------------
# Find the template file for a filename

sub find_template {
    my ($filename) = @_;   

    my @dirs = split(/\//, $filename);
    my $basename = pop(@dirs);
    my ($root, $ext) = split(/\./, $basename);
    $ext = 'html';

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
    create_indexes($converted_files);

    return;
}

#----------------------------------------------------------------------
# Get the data used to construct a page

sub get_data_for_file {
    my ($filename) = @_;

    my $data;    
    if (-e $filename) {
        my @stats = stat($filename);
        $data = build_date($stats[9]);

    } else {
        $data = {};
    }
    
    $data->{title} = build_title($filename);
    $data->{url} = build_url($filename);
    
    return $data;
}

#----------------------------------------------------------------------
# Get a list of index files for the converted files

sub get_indexes {
    my ($converted_files) = @_;

    my %index_files;
    foreach my $filename (@$converted_files) {
        my ($top_dir, @dirs) = split(/\//, $filename);
        next unless $top_dir eq $config{archive_directory};
        
        while (@dirs) {
            pop(@dirs);
            my $file = join('/', $top_dir, @dirs, 'index.html');
            $index_files{$file} = 1;
        }
    }
    
    my @index_files = keys %index_files;
    @index_files = sort_by_depth(@index_files) if @index_files;
    
    return @index_files;
}

#----------------------------------------------------------------------
# Retrieve the data associated with a file

sub index_data {
    my ($index_file) = @_;
        
    my @dirs = split(/\//, $index_file);
    my $basename = pop(@dirs);
    
    my $index_dir = join('/', @dirs);
    my $data = get_data_for_file($index_dir);

    my ($visit_dirs, $visit_files) = visitors('html', $index_dir);

    my @dir_data;
    my @file_data;
    $visit_dirs->();

    while (defined (my $file = $visit_files->())) {
        my ($root, $ext) = split(/\./, $file);
        
        next if $root eq 'index';
        next if $root =~ /template$/;
        
        my $loop_data = get_data_for_file($file);

        if (-d $file) {
            push(@dir_data, $loop_data);
        } else {
            push(@file_data, $loop_data);
        }
    }
       
    my @loop = (@dir_data, @file_data);
    $data->{loop} = \@loop;

    return $data;
}

#----------------------------------------------------------------------
# Get the most recently changed files

sub most_recent_files {
    my ($limit, $top_dir) = @_;
    
    my ($visit_dirs, $visit_files) = visitors('html', $top_dir);
    
    my @augmented_files;
    while (defined (my $dir = $visit_dirs->())) {
        while (defined (my $filename = $visit_files->())) {
            my @dirs = split(/\//, $filename);
            my $basename = pop(@dirs);
            
            my ($root, $ext) = split(/\./, $basename);
            next if $root eq 'index';
            next if $root =~ /template$/;
            
            my @stats = stat($filename);

            if (@augmented_files < $limit) {
                push(@augmented_files, [$stats[9], $filename]);
                @augmented_files = sort {$a->[0] <=> $b->[0]} @augmented_files;

            } else {
                # The modification date is compared and sorted on
                if ($stats[9] > $augmented_files[0]->[0]) {
                    push(@augmented_files, [$stats[9], $filename]);
                    @augmented_files = sort {$a->[0] <=> $b->[0]} @augmented_files;
                    shift(@augmented_files);
                }
            }
        }
    }
    
    my @recent_files = map {$_->[1]} @augmented_files;
    return reverse @recent_files;
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
# Get the data to put in the archive index

sub recent_archive_data {
    my ($archive_index, $archive_dir) = @_;

    my @loop;
    my $limit = $config{archive_index_length};
    my $data = get_data_for_file($archive_index);
    my @filenames = most_recent_files($limit, $archive_dir);

    foreach my $filename (@filenames) {
        my $loopdata = get_data_for_file($filename);

        my $page = read_page($filename);
        my $blocks = parse_page($page);
        $loopdata->{body} = $blocks->{$config{body_tag}};

        push(@loop, $loopdata);
    }

    $data->{loop} = \@loop;
    return $data;
}

#----------------------------------------------------------------------
# Sort a list of files so the deepest files are first

sub sort_by_depth {
    my (@index_files) = @_;

    my @augmented_files;
    foreach my $filename (@index_files) {
        # tr returns a count of the number of characters translated
        my $depth = $filename =~ tr(/)(/);
        push(@augmented_files, [$depth, $filename]);
    }

    @augmented_files = sort {$b->[0] <=> $a->[0]} @augmented_files;
    @index_files = map {$_->[1]} @augmented_files;
    
    return @index_files;
}

#----------------------------------------------------------------------
# Sort a list of files alphabetically, except for the index file

sub sort_by_name {
    my (@files) = @_;
    
    my @sorted_files;
    my @unsorted_files;

    foreach my $file (@files) {
        if ($file =~ /\/index\.html$/) {
            push(@sorted_files, $file);
        } else {
            push(@unsorted_files, $file)
        }
    }
    
    push(@sorted_files, sort @unsorted_files);
    return @sorted_files;
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
    my ($visit_dirs, $visit_files) = visitors('html');
    
    my $template_file = "template.html";
    $template = read_page($template_file);

    die "Couldn't read $template_file" unless defined $template;    
    return unless changed_template($template);                

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
            }
        }
    }
    
    return;
}

#----------------------------------------------------------------------
# Return a closure that returns each file name

sub visitors {
    my ($ext, $top_dir) = @_;
    $top_dir = '.' unless defined $top_dir;
    
    my @dirlist;
    my @filelist;
    
    # Store the modification date with the file
    push(@dirlist, $top_dir);

    my $visit_dirs = sub {
        my $dir = shift(@dirlist);
        return unless defined $dir;

        my $dd = IO::Dir->new($dir) or die "Couldn't open $dir: $!\n";

        # Find matching files and directories
        while (defined (my $file = $dd->read())) {
            my $path = $dir eq '.' ? $file : "$dir/$file";
            
            if (-d $path) {
                next if $file    =~ /^\./;
                push(@dirlist, $path);
                
            } else {
                next unless $file =~ /^[^\.]+\.$ext$/;
                push(@filelist, $path);
            }
        }

        $dd->close;

        @dirlist = sort(@dirlist);
        @filelist = sort_by_name(@filelist);

        return $dir;
    };
    
    my $visit_files = sub {
        return shift(@filelist);
    };
            
    return ($visit_dirs, $visit_files);
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

=encoding utf-8T

=head1 NAME

App::Followme - Simple static website maintainance

=head1 SYNOPSIS

    use App::Followme qw(followme);
    followme();

=head1 DESCRIPTION

This application does three things. First, it updates the constant partions of
each web page when the template is changed. Second, it converts text files into
html using the template. Third, it creates indexes for files when they are
placed in a special directory, the archive directory. This simplifies keeping
a blog on a static site.

Each html page has sections that are different from other pages and other
sections that are the same. The sections that differer are enclosed in html
comments that look like

    <!-- begin name-->
    <!-- end name -->

that indicate where the section begins and ends. When the main template
is changed, sections of the page outside the comments are changed to match
the main template. This includes the other templates. The main template is
template.html and is placed in the root directory of the site.

If there are any text files when the , they are converted into html files
by substituting the content and other variables into a template.

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

