package App::Followme::Common;
use 5.008005;
use strict;
use warnings;

use Cwd;
use IO::File;
use Digest::MD5 qw(md5_hex);
use File::Spec::Functions qw(abs2rel rel2abs splitdir catfile updir);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(build_date build_title build_url compile_template
                 find_prototype make_template read_page top_directory
                 set_variables sort_by_date sort_by_depth sort_by_name 
                 unchanged_prototype update_page write_page);

our $VERSION = "0.90";
our $top_directory;

use constant MONTHS => [qw(January February March April May June July
                           August September October November December)];

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

    my ($dir, $root, $ext) = parse_filename($filename);
    my $page_name = "$root.html";

    return $dir ? catfile($dir, $page_name) : $page_name;
}

#----------------------------------------------------------------------
# Get the title from the filename root

sub build_title {
    my ($filename) = @_;
    
    my ($dir, $root, $ext) = parse_filename(rel2abs($filename));

    if ($root eq 'index') {
        my @dirs = splitdir($dir);
        $root = pop(@dirs) || '';
    }
    
    $root =~ s/^\d+// unless $root =~ /^\d+$/;
    my @words = map {ucfirst $_} split(/\-/, $root);
    return join(' ', @words);
}

#----------------------------------------------------------------------
# Get the url for a file from its name

sub build_url {
    my ($filename, $absolute) = @_;

    $filename = abs2rel(rel2abs($filename), $top_directory);
    my @dirs = splitdir($filename);
    my $basename = pop(@dirs);

    my $page_name;
    if ($basename !~ /\./) {
        push(@dirs, $basename);
        $page_name = 'index.html';

    } else {
        $page_name = build_page_name($basename);
    }
    
    my $url = join('/', @dirs, $page_name);
    return make_relative($url, $absolute);
}

#----------------------------------------------------------------------
# Compute checksum for constant sections of page

sub checksum_prototype {
    my ($prototype, $decorated, $prototype_path) = @_;    

    my $md5 = Digest::MD5->new;

    my $block_handler = sub {
        my ($blockname, $locality, $blocktext) = @_;
        $md5->add($blocktext) if exists $prototype_path->{$locality};
    };
    
    my $prototype_handler = sub {
        my ($blocktext) = @_;
        $md5->add($blocktext);
        return;
    };

    parse_blocks($prototype, $decorated, $block_handler, $prototype_handler);

    return $md5->hexdigest;
}

#----------------------------------------------------------------------
# Compile a template into a subroutine

sub compile_template {
    my ($template, $variable) = @_;
    $variable = '{{*}}' unless $variable;
    
    my ($left, $right) = split(/\*/, $variable);
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
# Find an file to serve as a prototype for updating other files

sub find_prototype {
    my ($ext, $uplevel) = @_;

    my $filename;
    my $pattern = "*.$ext";
    my $directory = getcwd();
    my $current_directory = $directory;
    
    for (;;) {
        if ($uplevel) {
            $uplevel -= 1;

        } else {
            my @files = sort_by_date(glob($pattern));
            if (@files) {
                $filename = rel2abs(pop(@files));
                last;
            }
        }

        last if $directory eq $top_directory;
        chdir(updir());
        $directory = getcwd();
    }

    chdir($current_directory);
    return $filename;
}

#----------------------------------------------------------------------
# Return the level of a filename (top = 0)

sub get_level {
    my ($filename) = @_;

    my $level;
    if (defined $filename){
        $level = scalar splitdir($filename);
    } else {
        $level = 0;
    }

    return $level;  
}

#----------------------------------------------------------------------
# Make a url relative to a directory unless the absolute flag is set

sub make_relative {
    my ($url, $absolute) = @_;

    if ($absolute) {
        $url = "/$url";
        
    } else {
        my @urls = split('/', $url);
        my @dirs = splitdir($top_directory);

        while (@urls && @dirs && $urls[0] eq $dirs[0]) {
            shift(@urls);
            shift(@dirs);
        }
       
        $url = join('/', @urls);
    }
    
    return $url;
}

#----------------------------------------------------------------------
# Combine template with prototype

sub make_template {
    my ($template_name, $ext) = @_;

    $template_name = rel2abs($template_name, $top_directory);
    my $template = read_page($template_name);
    die "Couldn't find template: $template_name\n" unless $template;

    my $prototype_name = find_prototype($ext, 0);
    my $prototype = read_page($prototype_name); 
    
    my $final_template;
    if ($prototype) {
        my $decorated = 0;
        my $prototype_path = {};
        $final_template = update_page($prototype, $template, 
                                      $decorated, $prototype_path);
    } else {
        $final_template = $template;
    }

    return $final_template;
}

#----------------------------------------------------------------------
# Parse fields out of section tag

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
# Break page into blocks

sub parse_blocks {
    my ($page, $decorated, $block_handler, $prototype_handler) = @_;
    
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
                $prototype_handler->($token);
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
                $prototype_handler->($token);
            }

            $block = '';
            $blockname = '';

        } else {
            if ($blockname) {
                $block .= $token;
            } else {
                $prototype_handler->($token);
            }            
        }
    }
 
    die "Unmatched block (<!-- section $blockname -->)\n" if $blockname;
    return;
}

#----------------------------------------------------------------------
# Parse filename into directory, root, and extension

sub parse_filename {
    my ($filename) = @_;

    my @dirs = splitdir($filename);
    my $basename = pop(@dirs);
    my ($root, $ext) = split(/\./, $basename);
    my $dir = @dirs ? catfile(@dirs) : '';
    
    return ($dir, $root, $ext);
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
    
    my $prototype_handler = sub {
        return;
    };

    parse_blocks($page, $decorated, $block_handler, $prototype_handler);    
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
# Set the variables used to construct a page

sub set_variables {
    my ($filename) = @_;

    my $time;
    if (-e $filename) {
        my @stats = stat($filename);
        $time = $stats[9];
    } else {
        $time = time();
    }
    
    my $data = build_date($time);
    $data->{title} = build_title($filename);
    
    return $data;
}

#----------------------------------------------------------------------
# Sort a list of files so the least recently modified file is first

sub sort_by_date {
    my (@filenames) = @_;

    my @augmented_files;
    foreach my $filename (@filenames) {
        my @stats = stat($filename);
        push(@augmented_files, [$stats[9], $filename]);
    }

    @augmented_files = sort {$a->[0] <=> $b->[0] ||
                             $a->[1] cmp $b->[1]   } @augmented_files;
    
    return map {$_->[1]} @augmented_files;
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
        if ($file =~ /\bindex\.html$/) {
            push(@sorted_files, $file);
        } else {
            push(@unsorted_files, $file)
        }
    }
    
    push(@sorted_files, sort @unsorted_files);
    return @sorted_files;
}

#----------------------------------------------------------------------
# Get / set the top directory of the website

sub top_directory {
    my ($directory) = @_;
    
    $top_directory = $directory if defined $directory;
    return $top_directory;
}

#----------------------------------------------------------------------
# Determine if page matches prototype or needs to be updated

sub unchanged_prototype {
    my ($prototype, $page, $decorated, $prototype_path) = @_;
    
    my $prototype_checksum = checksum_prototype($prototype,
                                              $decorated,
                                              $prototype_path);
    my $page_checksum = checksum_prototype($page,
                                          $decorated,
                                          $prototype_path);

    my $unchanged;
    if ($prototype_checksum eq $page_checksum) {
        $unchanged = 1;
    } else {
        $unchanged = 0;
    }
    
    return $unchanged;
}

#----------------------------------------------------------------------
# Parse prototype and page and combine them

sub update_page {
    my ($prototype, $page, $decorated, $prototype_path) = @_;

    my $output = [];
    my $blocks = parse_page($page, $decorated);
    
    my $block_handler = sub {
        my ($blockname, $locality, $blocktext) = @_;
        if (exists $blocks->{$blockname}) {
            if (exists $prototype_path->{$locality}) {
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

    my $prototype_handler = sub {
        my ($blocktext) = @_;
        push(@$output, $blocktext);
        return;
    };

    parse_blocks($prototype, $decorated, $block_handler, $prototype_handler);

    if (%$blocks) {
        my $names = join(' ', sort keys %$blocks);
        die "Unused blocks ($names)\n";
    }
    
    return join('', @$output);
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

App::Followme::Common - Common functions to different packages
=head1 SYNOPSIS

    use App::Followme::Common qw(update_page);
    $page = update_page($prototype, $page, $decorated, $prototype_path);


=head1 DESCRIPTION

App::Followme::Common exports functions common to more than one package.
Packages directly invoked by followme are modules, but there is enough
commonality between them to want to factor out some functions into this
package.

=head1 FUNCTIONS

=over 4

=item my $date = build_date($filename);

The variables calculated from the modification time are: C<weekday, month,>
C<monthnum, day, year, hour24, hour, ampm, minute,> and C<second.>

=item my $title = build_title($filename);

The title of the page is derived from the file name by removing the filename
extension, removing any leading digits,replacing dashes with spaces, and
capitalizing the first character of each word.

=item $url = build_url($filename, $absolute);

Build the url that of a web page.

=item my $sub = compile_template($template, $variable);

Compile_template compiles a template contained in a string into a subroutine.
Then the subroutine can be called with one argument, a hash containing the data
to be interpolated into the subroutine. The output is a page containing the
template with the interpolated data. The data supplied to the subroutine should
be a hash reference. fields in the hash are substituted into variables in the
template. Variables in the template are surrounded by double braces, so that a
link would look like:

    <li><a href="{{url}}">{{title}}</a></li>

The string which indicates a variable is passed as an optional second argument
to compile_template. If not present or blank,double braces are used. If present,
the string should contain an asterisk to indicate where the variable name is
placed.

The data hash may contain a list of hashes, which should be named loop. Text
in between loop comments will be repeated for each hash in the list and each
hash will be interpolated into the text. Loop comments look like

    <!-- loop -->
    <!-- endloop -->

There should be only one pair of loop comments in the template. 

=item $str = read_page($filename);

Read a fie into a string. An the entire file is read from a string, there is no
line at a time IO. This is because files are typically small and the parsing
done is not line oriented. 

=item $data = set_variables($filename);

Create title and date variables from the filename and the modification date
of the file.

=item @filenames = sort_by_date(@filenames);

Sort filenames by modification date, placing the least recently modified
file first. If two files have the same date, they are sorted by name.

=item @filenames = sort_by_depth(@fienames);

Sort filenames by directory depth, with least deep files first. If two files
have the same depth, they are sorted by name.

=item @filenames = sort_by_name(@fienames);

Sort files by name, except the index file is placed first.

=item $top_directory = top_directory($directory);

Get and optionally set the top directory of the website

=item $page = update_page($prototype, $page, $decorated, $prototype_path);

This function combines the contents of a prototype and page to create a new
page. Update_page updates the constant portions of a web page from a prototype. 
Each html page has sections that are different from other pages and other
sections that are the same. The sections that differ are enclosed in html
comments that look like

    <!-- section name-->
    <!-- endsection name -->

and indicate where the section begins and ends. A page is
updated by substituting all its named blocks into corresponding block in the
prototype. The effect is that all the text outside the named blocks are
updated to be same as the text in the prototype.

Updates to the named block can also be made conditional by adding an in after
the section name. If the folder name after the "in" is included in the
prototype_path hash, then the block tags are ignored, it is as if the block does
not exist. The block is considered as part of the constant portion of the
prototype. If the folder is not in the prototype_path, the block is treated as
any other block and varies from page to page.

    <!-- section name in folder -->
    <!-- endsection name -->

Text in conditional blocks can be used for navigation or other sections of the
page that are constant, but not constant across the entire site.

Both prototype and page are strings, not filenames. The argument decorated
controls whether the section comment tags are copied from the prototype or page.
If decorated is true, the section tags are treated as part of the block and are
copied from the page. If decorated is false, the section tags are copied from
the prototype. Template_path is a hash containing the directories from the base
directory of the web site down to the directory containing the prototype. The
hash is treated as a set, that is, the directory names are the keys and the
values of the keys are one/

=item $flag = unchanged_prototype($prototype, $page, $decorated, $prototype_path);

Update_prototype return true if running update_page would leave the page
unchanged, false if it would change the page. The arguments are the same as
update_page.

=item write_page($filename, $str);

Write a file from a string. An the entire file is read to or written from a
string, there is no line at a time IO. This is because files are typically small
and the parsing done is not line oriented. 

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut
