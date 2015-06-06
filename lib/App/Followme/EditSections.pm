package App::Followme::EditSections;

use 5.008005;
use strict;
use warnings;

use lib '../..';

use File::Spec::Functions qw(catfile);
use base qw(App::Followme::Module);

our $VERSION = "1.14";

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($self) = @_;

    return (
            remove_comments => 0,
           );
}

#----------------------------------------------------------------------
# Modify pages to match the most recently modified page

sub run {
    my ($self, $directory) = @_;

    my $prototype_file = $self->find_prototype($directory, 0);
    my $prototype = $self->strip_comments($prototype_file, 1);

    $self->update_directory($directory, $prototype);

    return;
}

#----------------------------------------------------------------------
# Find the location of a string in a page

sub find_location {
    my ($self, $page, $prototype, $propos, $after) = @_;

    my $hi;
    my $lo = 0;
    my $mid = 8;

    while ($mid > $lo && (! defined $hi || $mid < $hi)) {
        my $str;
        if ($after) {
            $str = substr($prototype, $propos, $mid)
        } else {
            $mid = $propos if $mid > $propos;
            $str = substr($prototype, $propos-$mid, $mid);
        }

        my $pagepos;
        my $count = 0;
        while ($page =~ /($str)/g) {
            if ($count ++) {
                last;
            } else {
                $pagepos = pos($page);
            }
        }

        if ($count > 1) {
            $lo = $mid;
            if (defined $hi) {
                $mid = int(0.5 * ($mid + $hi));
           } else {
                $mid = $mid + 8;
            }

        } elsif ($count == 1) {
            $pagepos -= $mid if $after;
            return $pagepos;

        } else {
            $hi = $mid;
            $mid = int(0.5 * ($mid + $lo));
        }
    }

    return;
}

#----------------------------------------------------------------------
# Read page and strip comments

sub strip_comments {
    my ($self, $filename, $keep_sections) = @_;

    my $page = $self->read_page($filename);
    die "Could not read page" unless length($page);

    my @output;
    my @tokens = split(/(<!--.*?-->)/, $page);

    foreach my $token (@tokens) {
        if ($token !~ /^(<!--.*?-->)$/) {
            push(@output, $token);
        } elsif ($token =~ /(<!--\s*end)?section\s+.*?-->/) {
            push(@output, $token) if $keep_sections;
        } else {
            push(@output, $token) unless $self->{remove_comments};
        }
    }

    return join('', @output);
}

#----------------------------------------------------------------------
# Edit all files in the directory

sub update_directory {
    my ($self, $directory, $prototype) = @_;

    my ($filenames, $directories) = $self->visit($directory);

    foreach my $filename (@$filenames) {
        next unless $self->match_file($filename);

        my $page;
        eval {
            $page = $self->update_page($filename, $prototype);
        };

        if ($@) {
            warn "$filename: $@";
        } else {
            $self->write_page($filename, $page);
        }
    }

    for my $subdirectory (@$directories) {
        next unless $self->search_directory($directory);
        $self->update_directory($subdirectory, $prototype);
    }

    return;
}

#----------------------------------------------------------------------
# Parse prototype and page and combine them

sub update_page {
    my ($self, $filename, $prototype) = @_;

    my $page = $self->strip_comments($filename, 0);

    my @output;
    my $notfound;
    while ($prototype =~ /(<!--\s*(?:end)?section\s+.*?-->)/g) {
        my $comment = $1;
        my $pos = pos($prototype);
        my $after = $comment =~ /end/;

        # locate the position of the comment from the prototype in the page
        $pos = $pos - length($comment) unless $after;
        my $loc = $self->find_location($page, $prototype, $pos, $after);

        unless (defined $loc) {
            $notfound ++;
            $loc= 0;
        }

        # substitute comment into page
        push(@output, substr($page, 0, $loc), $comment);
        $page = substr($page, $loc);
    }

    push(@output, $page);
    $self->write_page($filename, join('', @output));

    die "Could not locate tags\n" if $notfound;
    return;
}

1;
__END__

=encoding utf-8

=head1 NAME

App::Followme::EditSections - Edit the section tags on an html page

=head1 SYNOPSIS

    use App::Followme::Sitemap;
    my $edit = App::Followme::EditSection->new();
    $edit->run($directory);

=head1 DESCRIPTION

Followme distinguishes between sections of a web page which are the same across
the website and sections that differ between each page by html comments starting
with section and endsection. This module modifies the placement or number of these
tags across a website. It can also used to modify an existing website so it
can be maintained by followme. Before running followme with this module, edit a
page and put the section and endsection comments in the proper locations. Then
create a configuration file containing the name of this module. Then run followme
and it will modify all the pages of the website to include the same comments. Any
section and endsection tags that were previously in the file will be removed.

=head1 CONFIGURATION

The following field in the configuration file are used:

=over 4

=item remove_comments

Remove all html comments that are in a file, not just the section and endsection
tags.

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut
