package App::Followme::FormatPages;
use 5.008005;
use strict;
use warnings;

use lib '../..';

use File::Spec::Functions qw(abs2rel rel2abs splitdir catfile);
use App::Followme::Common qw(find_prototype read_page top_directory sort_by_date 
                             unchanged_prototype update_page write_page);

our $VERSION = "0.90";

#----------------------------------------------------------------------
# Create a new object to update a website

sub new {
    my ($pkg, $configuration) = @_;
    
    my %self = ($pkg->parameters(), %$configuration); 
    return bless(\%self, $pkg);
}

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($pkg) = @_;
    
    return (
            options => {},
            web_extension => 'html',
           );
}

#----------------------------------------------------------------------
# Perform all updates on the directory

sub run {
    my ($self) = @_;

    my $pattern = "*.$self->{web_extension}";
    my @filenames = reverse sort_by_date(glob($pattern));
    return 1 unless @filenames;
    
    my $prototype_file = find_prototype($self->{web_extension}, 1);
    $prototype_file = shift(@filenames) unless defined $prototype_file;

    my $prototype_path = $self->get_prototype_path($prototype_file);
    my $prototype = read_page($prototype_file);
    
    my $count = 0;
    my $changed = 0;
    my $decorated = 1;

    foreach my $filename (@filenames) {        
        my $page = read_page($filename);
        die "Couldn't read $filename" unless defined $page;

        my $skip = unchanged_prototype($prototype, $page, $decorated, 
                                      $prototype_path);

        if ($skip) {
            last if $self->{options}{quick} && $count; 

        } else {
            $changed += 1;
            
            if ($self->{options}{noop}) {
                print "$filename\n";

            } else {
                $page = update_page($prototype, $page, $decorated,
                                    $prototype_path);

                $self->write_page_same_date($filename, $page);
            }
        }

        if ($count == 0) {
            $prototype = $page;
            $prototype_path = $self->get_prototype_path($filename);
        }
        
        $count += 1;
    }
    
    return $changed || ! $self->{options}{quick};
}

#----------------------------------------------------------------------
# Get the prototype path for the current directory

sub get_prototype_path {
    my ($self, $filename) = @_;
    
    $filename = rel2abs($filename);
    $filename = abs2rel($filename, top_directory());
    my @path = splitdir($filename);
    pop(@path);
    
    my %prototype_path = map {$_ => 1} @path;
    return \%prototype_path;    
}

#----------------------------------------------------------------------
# Set modification date for file when writing

sub write_page_same_date {
    my ($self, $filename, $page) = @_;

    my $modtime;
    if (-e $filename) {
        my @stats = stat($filename);
        $modtime = $stats[9];
    }

    write_page($filename, $page);
    utime($modtime, $modtime, $filename) if defined $modtime;
    
    return;
}

1;
__END__

=encoding utf-8

=head1 NAME

App::Followme::FormatPages - Simple static web site maintenance

=head1 SYNOPSIS

    use App::Followme::FormatPages;
    my $formatter = App::Followme::FormatPages->new($configuration);
    $formatter->run();
    
=head1 DESCRIPTION

App::Followme::FormatPages updates the web pages in a folder to match the most
recently modified page. Each web page has sections that are different from other
pages and other sections that are the same. The sections that differ are
enclosed in html comments that look like

    <!-- section name-->
    <!-- endsection name -->

and indicate where the section begins and ends. When a page is changed, this
module checks the text outside of these comments. If that text has changed. the
other pages on the site are also changed to match the page that has changed.
Each page updated by substituting all its named blocks into corresponding block
in the changed page. The effect is that all the text outside the named blocks
are updated to be the same across all the web pages.

=head1 CONFIGURATION

The following parameters are used from the configuration:

=over 4

=item options

A hash holding the command line option flags

=item web_extension

The extension uesd by web pages. The default value is html

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut

