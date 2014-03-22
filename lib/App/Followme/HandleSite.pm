package App::Followme::HandleSite;

use 5.008005;
use strict;
use warnings;
use integer;
use lib '../..';

use Cwd;
use IO::Dir;
use IO::File;
use File::Spec::Functions qw(abs2rel catfile file_name_is_absolute
                             no_upwards rel2abs splitdir updir);

use base qw(App::Followme::ConfiguredObject);

our $VERSION = "1.03";

use constant MONTHS => [qw(January February March April May June July
                           August September October November December)];

#----------------------------------------------------------------------
# Create object that returns files in a directory tree

sub new {
    my ($pkg, $configuration) = @_;

    my %self = $pkg->update_parameters($configuration);
    my $self = bless(\%self, $pkg);
    
    $self->{included_files} = $self->glob_patterns($self->get_included_files());
    $self->{excluded_files} = $self->glob_patterns($self->get_excluded_files());
    $self = $self->setup($configuration);
    
    return $self;
}

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($pkg) = @_;
    
    my %parameters = (
            body_tag => 'content',
            web_extension => 'html',
            template_directory => 'templates',
            template_pkg => 'App::Followme::Template',
           );

    my %base_params = $pkg->SUPER::parameters();
    %parameters = (%base_params, %parameters);

    return %parameters;
}

#----------------------------------------------------------------------
# Build date fields from time, based on Blosxom 3

sub build_body {
    my ($self, $data, $filename) = @_;

    my $page = $self->read_page($filename);

    if ($page) {
        my $sections = $self->{template}->parse_sections($page);
        $data->{body} = $sections->{$self->{body_tag}};
    }
            
    return $data;
}

#----------------------------------------------------------------------
# Build date fields from time, based on Blosxom 3

sub build_date {
    my ($self, $data, $filename) = @_;
    
    my $num = '01';
    my $months = MONTHS;
    my %month2num = map {substr($_, 0, 3) => $num ++} @$months;

    my $time;
    if (-e $filename) {
        my @stats = stat($filename);
        $time = $stats[9];
    } else {
        $time = time();
    }
    
    my $ctime = localtime($time);
    my @names = qw(weekday month day hour24 minute second year);
    my @values = split(/\W+/, $ctime);

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
# Set a flag indicating if the the filename is the index file

sub build_is_index {
    my ($self, $data, $filename) = @_;
    
    my ($directory, $file) = $self->split_filename($filename);
    my ($root, $ext) = split(/\./, $file);
    
    my $is_index = $root eq 'index' && $ext eq $self->{web_extension};
    $data->{is_index} = $is_index ? 1 : 0;
    
    return $data;
}

#----------------------------------------------------------------------
# Get the title from the filename root

sub build_title_from_filename {
    my ($self, $data, $filename) = @_;
    
    my ($dir, $file) = $self->split_filename($filename);
    my ($root, $ext) = split(/\./, $file);
    
    if ($root eq 'index') {
        my @dirs = splitdir($dir);
        $root = pop(@dirs) || '';
    }
    
    $root =~ s/^\d+// unless $root =~ /^\d+$/;
    my @words = map {ucfirst $_} split(/\-/, $root);
    $data->{title} = join(' ', @words);
    
    return $data;
}

#----------------------------------------------------------------------
# Get the title from the first paragraph of the page

sub build_summary {
    my ($self, $data) = @_;
    
    if ($data->{body}) {
        if ($data->{body} =~ m!<p[^>]*>(.*?)</p[^>]*>!si) {
            $data->{summary} = $1;
        }
    }

    return $data;
}

#----------------------------------------------------------------------
# Get the title from the page header

sub build_title_from_header {
    my ($self, $data) = @_;
    
    if ($data->{body}) {
        if ($data->{body} =~ s!^\s*<h(\d)[^>]*>(.*?)</h\1[^>]*>!!si) {
            $data->{title} = $2;
        }
    }
    
    return $data;
}

#----------------------------------------------------------------------
# Build a url from a filename

sub build_url {
    my ($self, $data, $directory, $filename) = @_;

    $data->{url} = $self->filename_to_url($directory,
                                          $filename,
                                          $self->{web_extension}
                                        );
    
    $data->{absolute_url} = '/' . $self->filename_to_url($self->{top_directory},
                                                         $filename,
                                                         $self->{web_extension}
                                                        );

    return $data;
}

#----------------------------------------------------------------------
# Get fields external to file content

sub external_fields {
    my ($self, $data, $directory, $filename) = @_;

    $data = $self->build_date($data, $filename);
    $data = $self->build_title_from_filename($data, $filename);
    $data = $self->build_is_index($data, $filename);
    $data = $self->build_url($data, $directory, $filename);

    return $data;
}

#----------------------------------------------------------------------
# Convert filename to url

sub filename_to_url {
    my ($self, $directory, $filename, $ext) = @_;    

    my $is_dir = -d $filename;
    $filename = rel2abs($filename);
    $filename = abs2rel($filename, $directory);
    
    my @path = splitdir($filename);
    push(@path, 'index.html') if $is_dir;
    
    my $url = join('/', @path);
    $url =~ s/\.[^\.]*$/.$ext/ if defined $ext;

    return $url;
}

#----------------------------------------------------------------------
# Find an file to serve as a prototype for updating other files

sub find_prototype {
    my ($self, $directory, $uplevel) = @_;

    $uplevel = 0 unless defined $uplevel;
    my @path = splitdir(abs2rel($directory, $self->{top_directory}));

    for (;;) {
        my $dir = catfile($self->{top_directory}, @path);

        if ($uplevel) {
            $uplevel -= 1;
        } else {
            my $file = $self->most_recent_file($dir, $self->{web_extension});
            return $file if $file;
        }

        last unless @path;
        pop(@path);
    }

    return;
}

#----------------------------------------------------------------------
# Construct the full file name from a relative file name

sub full_file_name {
    my ($self, @directories) = @_;

    return $directories[-1] if file_name_is_absolute($directories[-1]);
   
    my @dirs;
    foreach my $dir (@directories) {
        push(@dirs, splitdir($dir));
    }
    
    my @new_dirs;
    foreach my $dir (@dirs) {
        if (no_upwards($dir)) {
            push(@new_dirs, $dir);
        } else {
            pop(@new_dirs) unless $dir eq '.';
        }
    }
    
    return catfile(@new_dirs);  
}

#----------------------------------------------------------------------
# Get the list of excluded files

sub get_excluded_directories {
    my ($self) = @_;
    return [$self->{template_directory}];
}

#----------------------------------------------------------------------
# Get the list of excluded files

sub get_excluded_files {
    my ($self) = @_;
    return '';
}

#----------------------------------------------------------------------
# Get the list of included files

sub get_included_files {
    my ($self) = @_;
    return "*.$self->{web_extension}";
}

#----------------------------------------------------------------------
# Get the full template name (stub)

sub get_template_name {
    my ($self, $template_file) = @_;

    my @directories = ($self->{base_directory});
    push(@directories, $self->full_file_name($self->{top_directory},
                                             $self->{template_directory}));

    foreach my $directory (@directories) {
        my $template_name = $self->full_file_name($directory,
                                                  $template_file);
        return $template_name if -e $template_name;
    }

    die "Couldn't find template: $template_file\n";
}

#----------------------------------------------------------------------
# Map filename globbing metacharacters onto regexp metacharacters

sub glob_patterns {
    my ($self, $patterns) = @_;

    my @globbed_patterns;
    my @patterns = split(/\s*,\s*/, $patterns);

    foreach my $pattern (@patterns) {
        if ($pattern eq '*') {
            push(@globbed_patterns,  '.') if $pattern eq '*';
            
        } else {
            my $start;
            if ($pattern =~ s/^\*//) {
                $start = '';
            } else {
                $start = '^';
            }
        
            my $finish;
            if ($pattern =~ s/\*$//) {
                $finish = '';
            } else {
                $finish = '$';
            }
        
            $pattern =~ s/\./\\./g;
            $pattern =~ s/\*/\.\*/g;
            $pattern =~ s/\?/\.\?/g;
        
            push(@globbed_patterns, $start . $pattern . $finish);
        }
    }
    
    return \@globbed_patterns;
}

#----------------------------------------------------------------------
# Check if index file for directory is newer than other files

sub index_is_newer {
    my ($self, $index_name, $template_name, $directory) = @_;
    
    $template_name = $self->get_template_name($template_name);
    return unless $self->is_newer($index_name, $template_name);

    my $filename = $self->most_recent_file($directory);
    return $self->is_newer($index_name, $filename);
}

#----------------------------------------------------------------------
# Get fields from reading the file (stub)

sub internal_fields {
    my ($self, $data, $filename) = @_;   

    my $ext;
    if (-d $filename) {
        $ext = $self->{web_extension};
        $filename = catfile($filename, "index.$ext");

    } else {
        ($ext) = $filename =~ /\.([^\.]*)$/;
    }

    if (defined $ext) {       
        if ($ext eq $self->{web_extension}) {   
            $data = $self->build_body($data, $filename);
            $data = $self->build_summary($data);
            $data = $self->build_title_from_header($data);
        }
    }

    return $data;
}

#----------------------------------------------------------------------
# Is the target newer than any source file?

sub is_newer {
    my ($self, $target, @sources) = @_;
    
    my $target_date = 0;   
    if (-e $target) {
        my @stats = stat($target);  
        $target_date = $stats[9];
    }
    
    foreach my $source (@sources) {
        next unless defined $source;
        next unless -e $source;
        
        next if $self->same_file($target, $source);

        my @stats = stat($source);  
        my $source_date = $stats[9];
        return if $source_date >= $target_date;
    }

    return 1;
}

#----------------------------------------------------------------------
# Combine template with prototype and compile to subroutine

sub make_template {
    my ($self, $directory, $template_file) = @_;

    my $template_name = $self->get_template_name($template_file);
    my $prototype_name = $self->find_prototype($directory);

    my $sub;
    if (defined $prototype_name) {
        $sub = $self->{template}->compile($prototype_name, $template_name);
    } else {
        $sub = $self->{template}->compile($template_name);
    }

    return $sub;
}

#----------------------------------------------------------------------
# Return true if this is an included file

sub match_file {
    my ($self, $filename, $ext) = @_;
    
    my $dir;
    ($dir, $filename) = $self->split_filename($filename);
    
    foreach my $pattern (@{$self->{excluded_files}}) {
        return if $filename =~ /$pattern/;
    }
    
    if (defined $ext) {
        return 1 if $filename =~ /\.$ext$/;
        
    } else {
        foreach my $pattern (@{$self->{included_files}}) {
            return 1 if $filename =~ /$pattern/;
        }
    }

    return;
}

#----------------------------------------------------------------------
# Get the most recently modified  file in a directory

sub most_recent_file {
    my ($self, $directory, $ext) = @_;

    my ($filenames, $directories) = $self->visit($directory, $ext);

    my $newest_file;
    my $newest_date = 0;    
    foreach my $filename (@$filenames) {
        my @stats = stat($filename);  
        my $file_date = $stats[9];
    
        if ($file_date > $newest_date) {
            $newest_date = $file_date;
            $newest_file = $filename;
        }
    }

    return $newest_file;    
}

#----------------------------------------------------------------------
# Read a file into a string

sub read_page {
    my ($self, $filename) = @_;
    return unless defined $filename;
    
    local $/;
    my $fd = IO::File->new($filename, 'r');
    return unless $fd;
    
    my $page = <$fd>;
    close($fd);
    
    return $page;
}

#----------------------------------------------------------------------
# Cehck if two filenames are the same in an os independent way

sub same_file {
    my ($self, $filename1, $filename2) = @_;
    
    return unless defined $filename1 && defined $filename2;
    
    my @path1 = splitdir(rel2abs($filename1));
    my @path2 = splitdir(rel2abs($filename2));
    return unless @path1 == @path2;

    while(@path1) {
        return unless shift(@path1) eq shift(@path2);
    }
    
    return 1;
}

#----------------------------------------------------------------------
# Check if directory should be searched

sub search_directory {
    my ($self, $directory) = @_;
    
    my $excluded_dirs = $self->get_excluded_directories();
    
    foreach my $excluded (@$excluded_dirs) {
        return if $self->same_file($directory, $excluded);
    }
    
    return 1;
}

#----------------------------------------------------------------------
# Set the regular expression patterns used to match a command

sub setup {
    my ($self, $configuration) = @_;

    my $template_pkg = $self->{template_pkg};

    eval "require $template_pkg" or die "Module not found: $template_pkg\n";
    $self->{template} = $template_pkg->new($configuration);

    return;
}

#----------------------------------------------------------------------
# Set the data fields for a file

sub set_fields {
    my ($self, $directory, $filename) = @_;
    
    my $data = {};
    $data = $self->external_fields($data, $directory, $filename);
    $data = $self->internal_fields($data, $filename);

    return $data;
}

#----------------------------------------------------------------------
# Sort pending filenames

sub sort_files {
    my ($self, $files) = @_;

    my @files = sort @$files;
    return \@files;
}

#----------------------------------------------------------------------
# Split filename from directory

sub split_filename {
    my ($self, $filename) = @_;
    
    $filename = rel2abs($filename);
    my @path = splitdir($filename);
    my $file = pop(@path);
        
    my $dir = catfile(@path);
    return ($dir, $file);
}

#----------------------------------------------------------------------
# Update a module's parameters

sub update_parameters {
    my ($pkg, $configuration) = @_;
    $configuration = {} unless defined $configuration;
        
    my %parameters = $pkg->parameters();
    foreach my $field (keys %parameters) {
        $parameters{$field} = $configuration->{$field}
            if exists $configuration->{$field};
    }
    
    return %parameters;
}

#----------------------------------------------------------------------
# Return two closures that will visit a directory tree

sub visit {
    my ($self, $directory, $ext) = @_;

    my @filenames;
    my @directories;
    my $dd = IO::Dir->new($directory);
    die "Couldn't open $directory: $!\n" unless $dd;

    # Find matching files and directories
    while (defined (my $file = $dd->read())) {
        next unless no_upwards($file);
        my $path = catfile($directory, $file);
    
        if (-d $path) {
            push(@directories, $path) if $self->search_directory($path);
        } else {
            push(@filenames, $path) if $self->match_file($path, $ext);
        }
    }

    $dd->close;
    
    my $filenames = $self->sort_files(\@filenames);
    my $directories = $self->sort_files(\@directories);
    
    return ($filenames, $directories);   
}

#----------------------------------------------------------------------
# Write the page back to the file

sub write_page {
    my ($self, $filename, $page) = @_;

    my $fd = IO::File->new($filename, 'w');
    die "Couldn't write $filename" unless $fd;
    
    print $fd $page;
    close($fd);
        
    return;
}

1;

=pod

=encoding utf-8

=head1 NAME

App::Followme::HandleSite - Handle templates and prototype files

=head1 SYNOPSIS

    use App::Followme::HandleSite;
    my $hs = App::Followme::HandleSite->new($configuration);
    my $prototype = $hs->find_prototype($directory, 0);
    my $test = $hs->is_newer($filename, $prototype);
    if ($test) {
        my $data = $hs->set_fields($directory, $filename);
        my $sub = $self->make_template($directory, $template_name);
        my $webppage = $sub->($data);
        print $webpage;
    }

=head1 DESCRIPTION

This module contains the methods that perform template and prototype handling.
A Template is a file containing commands and variables for making a web page.
First, the template is compiled into a subroutine and then the subroutine is
called with a hash as an argument to fill in the variables and produce a web
page. A prototype is the most recently modified web page in a directory. It is
combined with the template so that the web page has the same look as the other
pages in the directory.

=head1 METHODS

This module has three public methods.

=over 4

=item $test = $self->is_newer($target, @sources);

Compare the modification date of the target file to the modification dates of
the source files. If the target file is newer than all of the sources, return
1 (true).

=item $filename = $self->find_prototype($directory, $uplevel);

Return the name of the most recently modified web page in a directory. If
$uplevel is defined, search that many directory levels up from the directory
passed as the first argument.

=item $sub = $self->make_template($directory, $template_name);

Combine a prototype and template, compile them, and return the compiled
subroutine. The prototype is the most recently modified file in the directory
passed as the first argument. The method searches for the template file first
in the directory and if it is not found there, in the templates folder, which
is an object parameter,

The data supplied to the subroutine should
be a hash reference. fields in the hash are substituted into variables in the
template. Variables in the template are preceded by Perl sigils, so that a
link would look like:

    <li><a href="$url">$title</a></li>

The data hash may contain a list of hashes, which the modules in App::Followme
name loop. Text in between for and endfor comments will be repeated for each
hash in the list and each hash will be interpolated into the text. For comments
look like

    <!-- for @loop -->
    <!-- endloop -->

=item $data = $self->set_fields($directory, $filename);

The main method for getting variables. This method calls the other methods
mentioned here. Filename is the file that the variables are being computed for.
Directory is used to compute the relative url. The url computed is relative
to it.

=item my $data = $self->build_date($data, $filename);

The variables calculated from the modification time are: C<weekday, month,>
C<monthnum, day, year, hour24, hour, ampm, minute,> and C<second.>

=item my $data = $self->build_is_index($data, $filename);

The variable C<is_flag> is one of the filename is an index file and zero if
it is not. 

=item my $data = $self->build_title_from_filename($data, $filename);

The title of the page is derived from the file name by removing the filename
extension, removing any leading digits,replacing dashes with spaces, and
capitalizing the first character of each word.

=item $data = $self->build_url($data, $filename);

Build the relative and absolute urls of a web page from a filename.

=item my $data = $self->internal_fields($data, $filename);

Compute the fields that you must read the file to calculate: title, body,
and summary

=item $str = $self->read_page($filename);

Read a fie into a string. An the entire file is read from a string, there is no
line at a time IO. This is because files are typically small and the parsing
done is not line oriented. 

=item $self->write_page($filename, $str);

Write a file from a string. An the entire file is read to or written from a
string, there is no line at a time IO. This is because files are typically small
and the parsing done is not line oriented. 

=item ($filenames, $directories) = $self->visit($top_directory);

Return a list of filenames and directories in a directory, The filenames are
filtered by the two methods get_included_files and get_excluded_files. By
default, it returns all files with the web extension.

=back

=head1 CONFIGURATION

The following fields in the configuration file are used in this class and every
class based on it:

=over 4

=item base_directory

The directory the class is invoked from. This controls which files are returned. The
default value is the current directory.

=item web_extension

The extension used by web pages. This controls which files are returned. The
default value is 'html'.

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut
