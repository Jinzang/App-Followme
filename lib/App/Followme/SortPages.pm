package App::Followme::SortPages;
use 5.008005;
use strict;
use warnings;

use File::Spec::Functions qw(splitdir);

our $VERSION = "0.89";

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(sort_by_date sort_by_depth sort_by_name);

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

1;
__END__

=encoding utf-8

=head1 NAME

App::Followme::SortPages - Several sort routines for files

=head1 SYNOPSIS

    use App::Followme::SortPages qw(sort_by_date sort_by_depth sort_by_name);
    @filenames = sort_by_date(@filenames);
    @filenames = sort_by_depth(@fienames);
    @filenames = sort_by_name(@fienames);

=head1 DESCRIPTION

This package contains several sort routines used by followme. They are

=over 4

=item @filenames = sort_by_date(@filenames);

Sort filenames by modification date, placing the least recently modified
file first. If two files have the same date, they are sorted by name.

=item @filenames = sort_by_depth(@fienames);

Sort filenames by directory depth, with least deep files first. If two files
have the same depth, they are sorted by name.

=item @filenames = sort_by_name(@fienames);

Sort files by name, except the index file is placed first.

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut

