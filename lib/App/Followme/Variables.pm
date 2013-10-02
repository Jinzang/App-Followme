package App::Followme::Variables;
use 5.008005;
use strict;
use warnings;

use File::Spec::Functions qw(abs2rel rel2abs splitdir catfile);

our $VERSION = "0.90";

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(build_url set_variables);

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
    
    my ($dir, $root, $ext) = parse_filename($filename);

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
    my ($filename, $base_dir, $absolute) = @_;

    $filename = abs2rel(rel2abs($filename), $base_dir);
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
    return make_relative($url, $base_dir, $absolute);
}

#----------------------------------------------------------------------
# Make a url relative to a directory unless the absolute flag is set

sub make_relative {
    my ($url, $base_dir, $absolute) = @_;

    $base_dir = '' unless defined $base_dir;
    $absolute = 0 unless defined $absolute;
    
    if ($absolute) {
        $url = "/$url";
        
    } else {
        my @urls = split('/', $url);
        my @dirs = splitdir($base_dir);

        while (@urls && @dirs && $urls[0] eq $dirs[0]) {
            shift(@urls);
            shift(@dirs);
        }
       
        $url = join('/', @urls);
    }
    
    return $url;
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

1;
__END__

=encoding utf-8

=head1 NAME

App::Followme::Variables - Set variables used when rendering file

=head1 SYNOPSIS

    use App::Followme::Variables qw(build_url set_variables);
    my $data = set_variables($filename);
    my $url = build_url($filename, $base_dir, $absolute);

=head1 DESCRIPTION

The functions in this package generate variables that are included in generated
web pages. These variables are:

=over 4

=item title

The title of the page is derived from the file name by removing the filename
extension, removing any leading digits,replacing dashes with spaces, and
capitalizing the first character of each word.

=item time fields

The variables calculated from the modification time are: C<weekday, month,>
C<monthnum, day, year, hour24, hour, ampm, minute,> and C<second.>

=item url

The url of the web page generated from a file.

=back

=head1 FUNCTIONS

Two functions are exported:

=over 4

=item $url = build_url($filename, $base_dir, $absolute);

Build the url that of a web page.

=item $data = set_variables($filename);

Create title and date variables from the filename and the modification date
of the file.

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut

