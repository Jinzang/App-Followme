package App::Followme::FormatPages;
use 5.008005;
use strict;
use warnings;

use Cwd;
use Digest::MD5 qw(md5_hex);
use File::Spec::Functions qw(abs2rel rel2abs splitdir catfile updir);

use App::Followme::SortPages qw(sort_by_date);
use App::Followme::PageIO qw(read_page write_page);
use App::Followme::PageBlocks qw(unchanged_template update_page);

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
           );
}

#----------------------------------------------------------------------
# Perform all updates on the directory

sub run {
    my ($self) = @_;

    my @filenames = sort_by_date(glob('*.html'));
    my $filename = pop(@filenames);
    return 1 unless $filename;
    
    my $count = 0;
    my $decorated = 1;
    my $template = $self->make_template($filename);
    my $template_path = $self->get_template_path($filename);

    foreach $filename (@filenames) {        
        my $page = read_page($filename);
        die "Couldn't read $filename" unless defined $page;

        my $skip = unchanged_template($template, $page,
                                      $decorated, $template_path);

        if ($skip) {
            last unless $self->{options}{all};

        } else {
            $count ++;
            
            if ($self->{options}{noop}) {
                print "$filename\n";

            } else {
                my $new_page = update_page($template, $page,
                                           $decorated, $template_path);

                $self->write_page_same_date($filename, $new_page);
            }
        }
    }
    
    return $self->{options}{all} || $count;
}

#----------------------------------------------------------------------
# Find an file in a directory above the current directory

sub find_template {
    my ($self) = @_;

    my $filename;
    my $directory = getcwd();
    my $current_directory = $directory;
    
    while ($directory ne $self->{base_dir}) {
        $directory = updir();
        chdir($directory);
        
        my @files = sort_by_date(glob('*.html'));
        if (@files) {
            $filename = rel2abs(pop(@files));
            last;
        }
    }

    chdir($current_directory);
    return $filename;
}

#----------------------------------------------------------------------
# Get the template path for the current directory

sub get_template_path {
    my ($self, $filename) = @_;
    
    $filename = rel2abs($filename);
    $filename = abs2rel($filename, $self->{base_dir});
    my @path = splitdir($filename);
    pop(@path);
    
    my %template_path = map {$_ => 1} @path;
    return \%template_path;    
}

#----------------------------------------------------------------------
# Create the template by joining a file with one in the directory above it

sub make_template {
    my ($self, $filename) = @_;
    
    my $template;
    my $decorated = 1;
    my $template_file = $self->find_template();
    
    if (defined $template_file) {
        my $page = read_page($filename);
        $template = read_page($template_file);
        my $template_path = $self->get_template_path($template_file);

        if (unchanged_template($template, $page,
                               $decorated, $template_path)) {
            $template = $page;

        } elsif ($self->{options}{noop}) {
                print "$filename\n";

         } else {
            $template = update_page($template, $page,
                                    $decorated, $template_path);
            $self->write_page_same_date($filename, $template);
        }
        
    } else {
        $template = read_page($filename);
    }
    
    return $template;
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

App::Followme::FormatPages  updates the constant
portions of each web page when a change is made on any page. 
Each html page has sections that are different from other pages and other
sections that are the same. The sections that differ are enclosed in html
comments that look like

    <!-- section name-->
    <!-- endsection name -->

and indicate where the section begins and ends. When a page is changed, followme
checks the text outside of these comments. If that text has changed. the other
pages on the site are also changed to match the page that has changed. Each page
updated by substituting all its named blocks into corresponding block in the
changed page. The effect is that all the text outside the named blocks are
updated to be the same across all the html pages.

Block text will be synchronized over all files in the folder if the begin
comment has "in folder" after the name. For example:

    <!-- section name in folder -->
    <!-- endsection name -->

Text in "in folder" blocks can be used for navigation or other sections of the
page that are constant, but not constant across the entire site.

=head1 CONFIGURATION


=over 4

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut

