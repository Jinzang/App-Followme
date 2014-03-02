package App::Followme::Variables;
use 5.008005;
use strict;
use warnings;

use lib '../..';

use Cwd;
use IO::File;
use File::Spec::Functions qw(abs2rel catfile file_name_is_absolute
                             no_upwards rel2abs splitdir updir);

use App::Followme::MostRecentFile;
use base qw(App::Followme::EveryFile);

our $VERSION = "0.99";

use constant MONTHS => [qw(January February March April May June July
                           August September October November December)];

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($pkg) = @_;
    
    my %parameters = (
            top_directory => getcwd(),
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
    if (exists $data->{body}) {
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
    
    if (exists $data->{body}) {
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
# Get fields from reading the file (stub)

sub internal_fields {
    my ($self, $data, $filename) = @_;   

    my ($ext) = $filename =~ /\.([^\.]*)$/;

    if ($ext eq $self->{web_extension}) {
        if (-d $filename) {
            my $index_name = "index.$self->{web_extension}";
            $filename = catfile($filename, $index_name);
        }
    
        my $body = $self->read_page($filename);
        $data->{body} = $body if defined $body;
        $data->{summary} = $self->build_summary($data);
        $data = $self->build_title_from_header($data);
    }
    
    return $data;
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
__END__

=pod

=encoding utf-8

=head1 NAME

App::Followme::Variables - Supplies common methods for App::Followme modules 

=head1 SYNOPSIS

    use App::Followme::Variables;
    my $var = App::Followme::Variables($configuration);
    my $data = $var->set_fields($directory, $filename);

=head1 DESCRIPTION

App::Followme::Variables is a base class for all the modules that App::Followme
uses to process a website. It is not called directly, App::Followme::HandleSite
subclasses it, so all its methods are called through it. Subclasses can create
other variables or override the methods in this class that create variables.

=head1 FUNCTIONS

The methods which calculate the variables are:

=over 4

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

