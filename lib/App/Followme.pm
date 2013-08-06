package App::Followme;
use 5.008005;
use strict;
use warnings;

use lib '..';

use IO::Dir;
use IO::File;
use Digest::MD5 qw(md5_hex);
use App::FollowmeSite qw(copy_file next_file);

our $VERSION = "0.74";

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(configure_followme followme);

our %config = (
               reindex_option => 0,
               initialize_option => 0,
               checksum_file => 'followme.md5',
               text_extension => 'txt',
               archive_index_length => 5,
               archive_index => 'blog.html',
               archive_directory => 'archive',
               body_tag => 'content',
               variable => '{{*}}',
               page_converter => \&add_tags,
               variable_setter => \&set_variables,
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
# Get all index files under the archive directory

sub all_indexes {    
    my %index_files;
    my $visitor = visitor_function('html', $config{archive_directory});

    while (defined (my $filename = &$visitor)) {
        my @dirs = split(/\//, $filename);
        pop(@dirs);
        
        while (@dirs) {
            my $file = join('/', @dirs, 'index.html');
            $index_files{$file} = 1;
            pop(@dirs);
        }
    }
    
    my @index_files = keys %index_files;
    if (@index_files > 1) {
        @index_files = reverse sort_by_depth(@index_files);
    }
    
    return @index_files;
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
    
    $root =~ s/^\d+//;
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
    my ($left, $right) = split(/\*/, $config{variable});
    $left = quotemeta($left);
    $right = quotemeta($right);
    
    my $code = <<'EOQ';
sub {
my ($data) = @_;
my ($block, @blocks);
EOQ

    my @tokens = split(/(<!--\s*(?:loop|endloop).*?-->)/, $template);
    
    foreach my $token (@tokens) {
        if ($token =~ /^<!--\s*loop/) {
            $code .= 'foreach my $data (@{$data->{loop}}) {' . "\n";

        } elsif ($token =~ /^<!--\s*endloop/) {
            $code .= "}\n";

        } else {
            $code .= "\$block = <<'EOQ';\n";
            $code .= "${token}\nEOQ\n";
            $code .= "chomp \$block;\n";
            $code .= "\$block =~ s/$left(\\w+)$right/\$data->{\$1}/g;\n";
            $code .= "push(\@blocks,\$block);\n";
        }
    }
    
    $code .= <<'EOQ';
return join('', @blocks);
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
    my $setter = $config{variable_setter};
    my $data = $setter->($filename);

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
    my ($top_dir) = @_;
    
    my $ext = $config{text_extension};
    my $visitor = visitor_function($ext, $top_dir);
    
    my @converted_files;
    while (defined (my $filename = &$visitor)) {
        eval {convert_a_file($filename)};

        if ($@) {
            warn "$filename: $@";
        } else {
            push(@converted_files, $filename);
            unlink($filename);
        }
    }
    
    return \@converted_files;
}

#----------------------------------------------------------------------
# Create an index file

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
    my @index_files = @_;
    
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

    for (;;) {
        my $template = join('/', @dirs, "${root}_template.html");
        return $template if -e $template;
        
        $template = join('/', @dirs, 'template.html');
        return $template if -e $template;

        last unless @dirs;
        pop(@dirs);
    }

    die "Couldn't find template for $filename\n";
}

#----------------------------------------------------------------------
# Find the initial website

sub find_site {
    my $pkg = 'App/Followme.pm';
    foreach my $dir (@INC) {
        my $file = "$dir/$pkg";
        print "$file\n" if -e $file;
    }

    return;
}

#----------------------------------------------------------------------
# Update a website based on changes to a file's template

sub followme {
    my ($top_dir) = @_;
    chdir($top_dir) if defined $top_dir;
    
    if ($config{initialize_option}) {
        initialize_site($top_dir);

    } else {
        my @index_files;
        update_site('.');
        my $converted_files = convert_text_files('.');

        if ($config{reindex_option}) {
            @index_files = all_indexes();
        } else {
            @index_files = get_indexes($converted_files);
        }

        create_indexes(@index_files) if @index_files;           
    }
    
    return;
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
    if (@index_files > 1) {
        @index_files = reverse sort_by_depth(@index_files);
    }
    
    return @index_files;
}

#----------------------------------------------------------------------
# Return the level of a filename (top = 0)

sub get_level {
    my ($filename) = @_;

    my $level;
    if ($filename eq '.'){
        $level = 0;

    } else {
        # tr returns a count of the number of characters replaced
        $level = $filename =~ tr(/)(/);
        $level ++;
    }

    return $level;  
}

#----------------------------------------------------------------------
# Retrieve the data needed to build an index

sub index_data {
    my ($index_file) = @_;
        
    my @dirs = split(/\//, $index_file);
    my $basename = pop(@dirs);
    
    my $index_dir = join('/', @dirs);
    my $setter = $config{variable_setter};
    my $data = $setter->($index_dir);

    my $visitor = visitor_function('html', $index_dir, 2);

    my @filenames;
    my $top_level = get_level($index_file);
    while (defined (my $filename = &$visitor)) {
        my @dirs = split(/\//, $filename);
        my $basename = pop(@dirs);
        my ($root, $ext) = split(/\./, $basename);

        next if $root =~ /template$/;

        if (get_level($filename) == $top_level) {
            push(@filenames, $filename) unless $root eq 'index';
        } else {
            push(@filenames, $filename) if $root eq 'index';
        }
    }

    @filenames = sort_by_depth(@filenames);
    
    my @loop_data;
    foreach my $filename (@filenames) {
        push(@loop_data, $setter->($filename)); 
    }

    $data->{loop} = \@loop_data;
    return $data;
}

#----------------------------------------------------------------------
# Initialize website by creating templates

sub initialize_site {
    my ($top_dir) = @_;
    
    while (my ($file, $text) = next_file()) {
        eval {
            $file = rename_template($file);
            $text = modify_template($text);
            copy_file($file, $text, $top_dir);
        };
        
        warn "$file: $@" if $@;
    }

    return;
}

#----------------------------------------------------------------------
# Modify template to match non-default configuration

sub modify_template {
    my ($text) = @_;
    
    if ($config{body_tag} ne 'content') {
        $text =~ s/<!--\s*begin\s+content\s*-->/<!-- begin $config{body_tag} -->/;
        $text =~ s/<!--\s*end\s+content\s*-->/<!-- end $config{body_tag} -->/;
    }

    if ($config{variable} ne '{{*}}') {
        my ($left, $right) = split(/\*/, $config{variable});
        $text =~ s/{{(\w+)}}/$left$1$right/g;
    }

    return $text;
}

#----------------------------------------------------------------------
# Get the more recently changed files

sub more_recent_files {
    my ($limit, $top_dir) = @_;
    
    my $visitor = visitor_function('html', $top_dir);
    
    my @dated_files;
    while (defined (my $filename = &$visitor)) {
        my @dirs = split(/\//, $filename);
        my $basename = pop(@dirs);
        
        my ($root, $ext) = split(/\./, $basename);
        next if $root eq 'index';
        next if $root =~ /template$/;

        my @stats = stat($filename);
        if (@dated_files < $limit || $stats[9] > $dated_files[0]->[0]) {
            shift(@dated_files) if @dated_files >= $limit;
            push(@dated_files, [$stats[9], $filename]);
            @dated_files = sort {$a->[0] <=> $b->[0]} @dated_files;
        }
    }
    
    my @recent_files = map {$_->[1]} @dated_files;
    @recent_files = reverse @recent_files if @recent_files > 1;
    return @recent_files;
}

#----------------------------------------------------------------------
# Get the most recently changed file

sub most_recently_changed {
    my ($top_dir) = @_;
    
    my ($most_recent_file, $most_recent_date);
    my $visitor = visitor_function('html', $top_dir);
    
    while (defined (my $filename = &$visitor)) {
        my @stats = stat($filename);
        if (! defined $most_recent_file || $stats[9] > $most_recent_date) {
            $most_recent_file = $filename;
            $most_recent_date = $stats[9];
        }
    }
    
    return $most_recent_file;
}

#----------------------------------------------------------------------
# Break page into template and blocks

sub parse_blocks {
    my ($page, $block_handler, $template_handler) = @_;
    
    my $blockname = '';
    my @tokens = split(/(<!--\s*(?:begin|end)\s+\w+\s*-->)/, $page);
    
    foreach my $token (@tokens) {
        if ($token =~ /^<!--\s*begin\s+(\w+)/) {
            die "Improperly nested block ($token)\n" if $blockname;
                
            $blockname = $1;
            $template_handler->($token);
            
        } elsif ($token =~ /^<!--\s*end\s+(\w+)/) {
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
    my $setter = $config{variable_setter};
    my $data = $setter->($archive_index);

    my @filenames = more_recent_files($limit, $archive_dir);

    foreach my $filename (@filenames) {
        my $loopdata = $setter->($filename);
        my $page = read_page($filename);
        my $blocks = parse_page($page);

        $loopdata->{body} = $blocks->{$config{body_tag}};
        push(@loop, $loopdata);
    }

    $data->{loop} = \@loop;
    return $data;
}

#----------------------------------------------------------------------
# Rename a template to match the configuration

sub rename_template {
    my ($file) = @_;

    while ($file =~/{{(\w+)}}/) {
        my $parameter = $config{$1};
        my ($root, $ext) = split(/\./, $parameter);
        $file =~ s/{{\w+}}/$root/;
    }

    return $file;
}

#----------------------------------------------------------------------
# Set the variables used to construct a page

sub set_variables {
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
# Sort a list of files so the deepest files are first

sub sort_by_depth {
    my (@index_files) = @_;

    my @augmented_files;
    foreach my $filename (@index_files) {
        push(@augmented_files, [get_level($filename), $filename]);
    }

    @augmented_files = sort {$a->[0] <=> $b->[0] ||
                             $a->[1] cmp $b->[1]   } @augmented_files;
    
    return map {$_->[1]} @augmented_files;
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
    my ($top_dir) = @_;
 
    my $template_file = most_recently_changed($top_dir);
    my $template = read_page($template_file);

    die "Couldn't read $template_file" unless defined $template;    
    return unless changed_template($template);                

    my $visitor = visitor_function('html', $top_dir);
    while (defined (my $filename = &$visitor)) {        
        next if $filename eq $template_file;

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
# Return a closure that returns each file name

sub visitor_function {
    my ($ext, $top_dir, $levels) = @_;
    $levels = 999 unless defined $levels;
    
    my @dirlist;
    my @filelist;
    
    # Store the modification date with the file
    push(@dirlist, $top_dir);
    my $top_level = get_level($top_dir);

    return sub {
        for (;;) {
            my $file = shift(@filelist);
            return $file if defined $file;
        
            my $dir = shift(@dirlist);
            return unless defined $dir;
    
            if ((get_level($dir) - $top_level) < $levels) {           
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
            }
        }
    };
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

App::Followme - Simple static web site maintenance

=head1 SYNOPSIS

    use App::Followme qw(followme);
    followme();

=head1 DESCRIPTION

Followme does three things. First, it updates the constant portions of each web
page when it is changed on any page. Second, it converts text files into html
using a template. Third, it creates indexes for files when they are placed in a
special directory, the archive directory. This simplifies keeping a blog on a
static site. Each of these three actions are explained in turn.

Each html page has sections that are different from other pages and other
sections that are the same. The sections that differ are enclosed in html
comments that look like

    <!-- begin name-->
    <!-- end name -->

and indicate where the section begins and ends. When a page is changed, followme
checks the text outside of these comments. If that text has changed. the other
pages on the site are also changed to match the page that has changed. Each page
updated by substituting all its named blocks into corresponding block in the
changed page. The effect is that all the text outside the named blocks are
updated to be the same across all the html pages.

If there are any text files in the directory, they are converted into html files
by substituting the content into a template. After the conversion the original
file is deleted. Along with the content, other variables are calculated from the
file name and modification date. Variables in the template are surrounded by
double braces, so that a link would look like:

    <li><a href="{{url}}">{{title}}</a></li>

The string which indicates a variable is configurable. The variables that are
calculated for a text file are:

=over 4

=item body

All the content of the text file. The content is passed through a subroutine
before being stored in this variable. The subroutine takes one input, the
content stored as a string, and returns it as a string containing html. The
default subroutine, add_tags in this module, only surrounds paragraphs with
p tags, where paragraphs are separated by a blank line. You can supply a
different subroutine by changing the value of the configuration variable
page_converter.

=item title

The title of the page is derived from the file name by removing the filename
extension, removing any leading digits,replacing dashes with spaces, and
capitalizing the first character of each word.

=item url

The relative url of the resulting html page. 

=item time fields

The variables calculated from the modification time are: weekday, month,
monthnum, day, year, hour24, hour, ampm, minute, and second.

=back

The template for the text file is selected by first looking for a file in
the same directory starting with the same name as the file, e.g.,
index_template.html for index.html. If not found, then a file named
template.html in the same directory is used. If neither is found, the same
search is done in the directory above the file, up to the top directory of
the site.

As a final step, followme builds indexes for each directory in the archive
directory. Each directory gets an index containing links to all the files and
directories contained in it. And one index is created from all the most
recently changed files in the archive directory. This index thus serves as a
weblog. Both kinds of index are built using a template. The variables are
the same as mentioned above, except that the body variable is set to the
block inside the content comment. Loop comments that look like

    <!-- loop -->
    <!-- endloop -->

indicate the section of the template that is repeated for each file contained
in the index. 

=head1 CONFIGURATION

Followme is called with the function followme, which takes one or no argument.

    followme($directory);
    
The argument is the name of the top directory of the site. If no argument is
called, the current directory is taken as the top directory. Before calling
this function, it can be configured by calling the function configure_followme.

    configure_followme($name, $value);

The first argument is the name and the second the value of the configuration
parameter. All parameters have scalar values except for page-converter, whose
value is a reference to a function. The configuration parameters all have default
values, which are listed below with each parameter.

=over 4

=item checksum_file (followme.md5)

The name of the file containing the checksum of the constant parts of an html
page. It's used to see if the file has changed.

=item text_extension (txt)

The extension of files that are converted to html.

=item archive_index_length (5)

The number of recent files to include in the weblog index.

=item archive_index (blog.html)

The filename of the weblog index.

=item archive_directory (archive)

The name of the directory containing the weblog entries.

=item body_tag (content)

The comment name surrounding the weblog entry content.

=item variable ({{*}})

The string which indicates a variable in a template. The variable name replaces
the star in the pattern.

=item page_converter (add_tags)

A reference to a function use to convert text to html. The function should
take one argument, a string containing the text to be converted and return one
value, the converted text.

=item variable_setter (set_variables)

A reference to a function that sets the variables that will be substituted
into the templates, with the exception of body, which is set by page_converter.
The function takes one argument, the name of the file the variables are
generated from, and returns a reference to a hash containing the variables and
their values.

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut

