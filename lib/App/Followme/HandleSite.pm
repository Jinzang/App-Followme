package App::Followme::HandleSite;

use 5.008005;
use strict;
use warnings;
use integer;

use Cwd;
use IO::File;
use File::Spec::Functions qw(abs2rel catfile file_name_is_absolute
                             no_upwards rel2abs splitdir updir);

use App::Followme::MostRecentFile;
use base qw(App::Followme::EveryFile);

our $VERSION = "1.03";

use constant MONTHS => [qw(January February March April May June July
                           August September October November December)];

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($pkg) = @_;
    
    my %parameters = (
            quick_update => 0,
            body_tag => 'content',
            top_directory => getcwd(),
            template_directory => 'templates',
            template_pkg => 'App::Followme::Template',
           );

    my %base_params = $pkg->SUPER::parameters();
    %parameters = (%base_params, %parameters);

    return %parameters;
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
    
    my $summary = '';
    if ($data->{body}) {
        if ($data->{body} =~ m!<p[^>]*>(.*?)</p[^>]*>!si) {
            $summary = $1;
        }
    }
    
    return $summary;
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
            my $mrf = App::Followme::MostRecentFile->new($self);
            my $filename = $mrf->run($dir);
            return $filename if $filename;
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
# Get fields from reading the file (stub)

sub internal_fields {
    my ($self, $data, $filename) = @_;   

    my ($ext) = $filename =~ /\.([^\.]*)$/;

    if ($ext eq $self->{web_extension}) {
        if (-d $filename) {
            my $index_name = "index.$self->{web_extension}";
            $filename = catfile($filename, $index_name);
        }
    
        my $page = $self->read_page($filename);

        if ($page) {
            my $sections = $self->parse_sections($page);
            $data->{body} = $sections->{$self->{body_tag}};
            $data->{summary} = $self->build_summary($data);
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
        next unless -e $source;

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
# Return a hash of the sections in a page

sub parse_sections {
    my ($self, $page) = @_;
        
    return $self->{template}->parse_sections($page);  
}

#----------------------------------------------------------------------
# Set the regular expression patterns used to match a command

sub setup {
    my ($self, $configuration) = @_;

    my $template_pkg = $self->{template_pkg};

    eval "require $template_pkg" or die "Module not found: $template_pkg\n";
    $self->{template} = $template_pkg->new($configuration);

    return $self;
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

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut
