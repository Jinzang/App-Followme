#!/usr/bin/perl

use strict;
use warnings;

use FindBin qw($Bin);

use IO::File;
use IO::Dir;
use File::Spec::Functions qw(catfile  no_upwards rel2abs splitdir);

#----------------------------------------------------------------------
# Configuration

# Prefix that preceds every command in data section
# Must agree with Initialize.pm
use constant CMD_PREFIX => '#>>>';

# The location of the initialization module relative to this file
my $output = 'lib/App/Followme/Initialize.pm';

# The files that will be included in the data section
# using unix style wild cards
my @patterns = qw(index.html *.cfg *.htm);

#----------------------------------------------------------------------
# Main routine

my $dir = shift(@ARGV) or die "Must supply site directory\n";
$dir  = rel2abs($dir);

@patterns = glob_patterns(@patterns);

chdir ($Bin);
my $out = copy_script($output);

chdir($dir);
my $visitor = get_visitor(@patterns);

while (my $file = &$visitor) {
    append_file($out, $file);
}

close($out);

chdir($Bin);
rename("$output.TMP", $output);

#----------------------------------------------------------------------
# Append a text file to the bundle

sub append_file {
    my ($out, $file) = @_;

    my $text = read_file($file);
    $file = join('/', splitdir($file));

    print $out CMD_PREFIX, "copy $file\n";
    print $out $text;

    return;
}

#----------------------------------------------------------------------
# Copy the script to start

sub copy_script {
    my ($output) = @_;

    my @path = split(/\//, $output);
    $output = catfile(@path);

    my $last = "__DATA__\n";
    my $text = read_file($output, $last);

    $output .= '.TMP';
    my $out = IO::File->new($output, 'w');
    die "Couldn't write to script: $output\n" unless $out;

    print $out $text;
    return $out;
}

#----------------------------------------------------------------------
# Return a closure that visits files in a directory

sub get_visitor {
    my (@patterns) = @_;

    my @dirlist;
    my @filelist;
    push(@dirlist, '.');

    return sub {
        for (;;) {
            my $file = shift @filelist;
            return $file if defined $file;

            my $dir = shift @dirlist;
            return unless defined $dir;

            my $dd = IO::Dir->new($dir) or die "Couldn't open $dir: $!\n";

            while (defined ($file = $dd->read())) {
                my $path = $dir ne '.' ? catfile($dir, $file) : $file;

                if (-d $path) {
                    push(@dirlist, $path) if no_upwards($file);

                } else {
                    my $match = 0;
                    foreach my $pattern (@patterns) {
                        if ($path =~ /$pattern/) {
                            $match = 1;
                            last;
                        }
                    }
                    push(@filelist, $path) if $match;
                }
            }

            $dd->close;
        }
    };
}

#----------------------------------------------------------------------
# Map filename globbing metacharacters onto regexp metacharacters

sub glob_patterns {
    my (@patterns) = @_;

    my @globbed_patterns;
    foreach my $pattern (@patterns) {
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

    return @globbed_patterns;
}

#----------------------------------------------------------------------
# Read a text file into a string

sub read_file {
    my ($file, $last) = @_;

    my $in = IO::File->new($file, 'r') or
        die "Couldn't read $file: $!\n";

    my @text;
    while (<$in>) {
        push(@text, $_);
        last if $last && $_ eq $last;
    }

    close($in);

    return join('', @text);
}

__END__

=encoding utf-8

=head1 NAME

bundle.pl - Combine website files with Initialize module

=head1 SYNOPSIS

    perl bundle.pl directory

=head1 DESCRIPTION

When followme is called with the -i flag it creates a new website in a directory,
including the files it needs to run. These files are extraced from the DATA
section at the end of the Initialize.pm module. This script updates that DATA section
from a sample website. It is for developers of this code and not for end users.

Run this script with the name of the directory containing the sample website on
the command line.

=head1 CONFIGURATION

The following variabless are defined in the configuration section at the top of
the script:

=over 4

=item CMD_PREFIX

The string which marks a line in the DATA section as a command. It must match
the constant of the same name in the Initialize.pm module.

=item $output

The file path to the Initialize.pm module relative to the location of this script.
Directories should be separated by forward slashes (/) regardless of the convention
of the operating system.

=item @patterns

A list of wildcard patterns using Unix filename wildcard syntax. If a file matches
any of the patterns it will be added to the DATA section.

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut
