package App::Followme::FormatPages;
use 5.008005;
use strict;
use warnings;

use lib '../..';

use base qw(App::Followme::PageHandler);

use Digest::MD5 qw(md5_hex);
use File::Spec::Functions qw(abs2rel rel2abs splitdir catfile);
use App::Followme::TopDirectory;

our $VERSION = "0.93";

#----------------------------------------------------------------------
# Perform all updates on the directory

sub run {
    my ($self) = @_;

    my @stats = stat($self->{base_directory});
    my $modtime = $stats[9];
    
    # The first update uses a file from the directory above
    # as a prototype, if one is found

    my $prototype_file = $self->find_prototype(1);
    $prototype_file = $self->next unless defined $prototype_file;
    
    my $prototype_path = $self->get_prototype_path($prototype_file);
    my $prototype = $self->read_page($prototype_file);
    
    my $count = 0;
    my $changes = 0;
    my $decorated = 1;

    while (defined(my $filename = $self->next)) {
        my $page = $self->read_page($filename);
        die "Couldn't read $filename" unless defined $page;

        # Check for changes before updating page
        my $skip = $self->unchanged_prototype($prototype, $page,
                                              $decorated, $prototype_path);

        if ($skip) {
            last if $self->{quick_update} && $count;
            
        } else {    
            $page = $self->update_page($prototype, $page, 
                                       $decorated, $prototype_path);
        
            my @stats = stat($filename);
            my $modtime = $stats[9];
        
            $self->write_page($filename, $page);
            utime($modtime, $modtime, $filename);
            $changes += 1;
        }
        
        if ($count == 0) {
            # The second and subsequent updates use the most recently
            # modified file in a directory as the prototype, so we
            # must change the values used for the first update
            $prototype = $page;
            $prototype_path = $self->get_prototype_path($filename);
        }
        
        $count += 1;
    }
    
    utime($modtime, $modtime, $self->{base_directory});
    return ! $self->{quick_update} || $changes; 
}

#----------------------------------------------------------------------
# Compute checksum for constant sections of page

sub checksum_prototype {
    my ($self, $prototype, $decorated, $prototype_path) = @_;    

    my $md5 = Digest::MD5->new;

    my $block_handler = sub {
        my ($blockname, $locality, $blocktext) = @_;
        $md5->add($blocktext) if exists $prototype_path->{$locality};
    };
    
    my $prototype_handler = sub {
        my ($blocktext) = @_;
        $md5->add($blocktext);
        return;
    };

    $self->parse_blocks($prototype, $decorated,
                        $block_handler, $prototype_handler);

    return $md5->hexdigest;
}

#----------------------------------------------------------------------
# Get the prototype path for the current directory

sub get_prototype_path {
    my ($self, $filename) = @_;
    
    $filename = rel2abs($filename);
    $filename = abs2rel($filename, App::Followme::TopDirectory->name);
    my @path = splitdir($filename);
    pop(@path);
    
    my %prototype_path = map {$_ => 1} @path;
    return \%prototype_path;    
}

#----------------------------------------------------------------------
# Determine if page matches prototype or needs to be updated

sub unchanged_prototype {
    my ($self, $prototype, $page, $decorated, $prototype_path) = @_;
    
    my $prototype_checksum = $self->checksum_prototype($prototype,
                                                       $decorated,
                                                       $prototype_path);
    my $page_checksum = $self->checksum_prototype($page,
                                                  $decorated,
                                                  $prototype_path);

    my $unchanged;
    if ($prototype_checksum eq $page_checksum) {
        $unchanged = 1;
    } else {
        $unchanged = 0;
    }
    
    return $unchanged;
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

=item quick_update

Only check files in current directory

=item web_extension

The extension used by web pages. The default value is html

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut

