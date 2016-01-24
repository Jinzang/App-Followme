package App::Followme::FIO;

use 5.008005;
use strict;
use warnings;
use integer;
use lib '../..';

use Cwd;
use IO::Dir;
use IO::File;
use Time::Local;
use Time::Format;
use File::Spec::Functions qw(abs2rel catfile file_name_is_absolute
                             no_upwards rel2abs splitdir);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(fio_filename_to_url fio_full_file_name fio_format_date
                 fio_get_date fio_get_size fio_glob_patterns fio_is_newer
                 fio_match_patterns fio_most_recent_file fio_pushdir fio_popdir
                 fio_read_page fio_same_file fio_set_date fio_split_filename
                 fio_to_file fio_visit fio_write_page);

our $VERSION = "1.16";

our @fio_directory_stack = (); # for fio_pushdir and fio_popdir

#----------------------------------------------------------------------
# Convert filename to url

sub fio_filename_to_url {
    my ($directory, $filename, $ext) = @_;

    $filename = rel2abs($filename);
    $filename = fio_to_file($filename, $ext);
    $filename = abs2rel($filename, $directory);

    my @path = $filename eq '.' ? () : splitdir($filename);

    my $url = join('/', @path);
    $url =~ s/\.[^\.]*$/.$ext/ if defined $ext;

    return $url;
}

#----------------------------------------------------------------------
# Format a date string

sub fio_format_date {
    my ($date, $format) = @_;

    # Default format is iso date format
    $format = 'yyyy-mm-ddThh:mm:ss' unless defined $format;
    return time_format($format, $date);
}

#----------------------------------------------------------------------
# Construct the full file name from a relative file name

sub fio_full_file_name {
    my (@directories) = @_;

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
# Get modification date of file

sub fio_get_date {
    my ($filename) = @_;

    my $date;
    if (-e $filename) {
        my @stats = stat($filename);
        $date = $stats[9];
    } else {
        $date =time();
    }

    return $date;
}

#----------------------------------------------------------------------
# Get size of file

sub fio_get_size {
    my ($filename) = @_;

    my $size;
    if (-e $filename) {
        my @stats = stat($filename);
        $size = $stats[7];
    } else {
        $size = 0;
    }

    return $size;
}

#----------------------------------------------------------------------
# Map filename globbing metacharacters onto regexp metacharacters

sub fio_glob_patterns {
    my ($patterns) = @_;

    my @globbed_patterns;
    my @patterns = split(/\s*,\s*/, $patterns);

    foreach my $pattern (@patterns) {
        if ($pattern eq '*') {
            push(@globbed_patterns,  '.');

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
# Is the target newer than any source file?

sub fio_is_newer {
    my ($target, @sources) = @_;

    my $target_date = -e $target ? fio_get_date($target) : 0;

    foreach my $source (@sources) {
        next unless defined $source;

        next unless -e $source;
        next if fio_same_file($target, $source);

        my $source_date = fio_get_date($source);
        return if $source_date >= $target_date;
    }

    return 1;
}

#----------------------------------------------------------------------
# Return true if filename matches pattern

sub fio_match_patterns {
    my ($file, $patterns) = @_;

    foreach my $pattern (@$patterns) {
        return 1 if $file =~ /$pattern/;
    }

    return;
}

#----------------------------------------------------------------------
# Get the most recently modified web file in a directory

sub fio_most_recent_file {
    my ($directory, $pattern) = @_;

    my ($filenames, $directories) = fio_visit($directory);

    my $newest_file;
    my $newest_date = 0;
    my $globs = fio_glob_patterns($pattern);

    foreach my $filename (@$filenames) {
        my ($dir, $file) = fio_split_filename($filename);
        next unless fio_match_patterns($file, $globs);

        my $file_date = fio_get_date($filename);

        if ($file_date > $newest_date) {
            $newest_date = $file_date;
            $newest_file = $filename;
        }
    }

    return $newest_file;
}

#----------------------------------------------------------------------
# Read a file into a string

sub fio_read_page {
    my ($filename, $binmode) = @_;
    return unless defined $filename;

    local $/;
    my $fd = IO::File->new($filename, 'r');
    return unless $fd;

    binmode($fd, $binmode) if defined $binmode;
    my $page = <$fd>;
    close($fd);

    return $page;
}

#----------------------------------------------------------------------
# Cehck if two filenames are the same in an os independent way

sub fio_same_file {
    my ($filename1, $filename2) = @_;

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
# Set modification date of file

sub fio_set_date {
    my ($filename, $date) = @_;

    if ($date =~ /[^\d]/) {
        die "Can't convert date: $date\n" unless $date =~ /T/;
        my @time = split(/[^\d]/, $date);
        $time[1] -= 1; # from 1 based to 0 based month

        $date = timelocal(reverse @time);
    }

    return utime($date, $date, $filename);
}

#----------------------------------------------------------------------
# Split filename from directory

sub fio_split_filename {
    my ($filename) = @_;

    $filename = rel2abs($filename);

    my ($dir, $file);
    if (-d $filename) {
        $file = '';
        $dir = $filename;

    } else {
        my @path = splitdir($filename);
        $file = pop(@path);
        $dir = catfile(@path);
    }

    return ($dir, $file);
}

#----------------------------------------------------------------------
# Convert filename to index file if it is a directory

sub fio_to_file {
    my ($file, $ext) = @_;

    $file = catfile($file, "index.$ext") if -d $file;
    return $file;
}

#----------------------------------------------------------------------
# Return a list of files and directories in a directory

sub fio_visit {
    my ($directory) = @_;

    my @filenames;
    my @directories;
    my $dd = IO::Dir->new($directory);
    die "Couldn't open $directory: $!\n" unless $dd;

    # Find matching files and directories
    while (defined (my $file = $dd->read())) {
        next unless no_upwards($file);
        my $path = catfile($directory, $file);

        if (-d $path) {
            push(@directories, $path);
        } else {
            push(@filenames, $path);
        }
    }

    $dd->close;

    @filenames = sort(@filenames);
    @directories = sort(@directories);

    return (\@filenames, \@directories);
}

#----------------------------------------------------------------------
# Write the page back to the file

sub fio_write_page {
    my ($filename, $page, $binmode) = @_;

    my $fd = IO::File->new($filename, 'w');
    die "Couldn't write $filename" unless $fd;

    binmode($fd, $binmode) if defined $binmode;
    print $fd $page;
    close($fd);

    return;
}

1;

=pod

=encoding utf-8

=head1 NAME

App::Followme::FIO - File IO routines used by followme

=head1 SYNOPSIS

    use App::Followme::FIO;
    TODO more examples

=head1 DESCRIPTION

This module contains the subroutines followme uses to access the file system

=head1 SUBROUTINES

=over 4

=item $test = fio_is_newer($target, @sources);

Compare the modification date of the target file to the modification dates of
the source files. If the target file is newer than all of the sources, return
1 (true).

=item $str = fio_read_page($filename, $binmode);

Read a fie into a string. An the entire file is read from a string, there is no
line at a time IO. This is because files are typically small and the parsing
done is not line oriented. Binmode is an optional parameter that indicates file
type if it is not a plain text file.

=item fio_write_page($filename, $str, $binmode);

Write a file from a string. An the entire file is written from a string, there
is no line at a time IO. This is because files are typically small. Binmode is
an optional parameter that indicates file type if it is not a plain text file.

=item ($filenames, $directories) = fio_visit($top_directory);

Return a list of filenames and directories in a directory,

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut
