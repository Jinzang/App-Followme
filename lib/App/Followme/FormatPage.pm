package App::Followme::FormatPage;
use 5.008005;
use strict;
use warnings;

use lib '../..';

use base qw(App::Followme::HandleSite);

use Digest::MD5 qw(md5_hex);
use File::Spec::Functions qw(abs2rel rel2abs splitdir catfile);

our $VERSION = "0.97";

#----------------------------------------------------------------------
# Return all the files in a subtree (example)

sub run {
    my ($self, $directory) = @_;

    my ($prototype_file, $prototype_path, $prototype);
    $prototype_file = $self->find_prototype($directory, 1);
    
    if (defined $prototype_file) {
        $prototype_path = $self->get_prototype_path($prototype_file);
        $prototype = $self->read_page($prototype_file);
    }

    $self->update_directory($directory, $prototype, $prototype_path);    
    return;
}

#----------------------------------------------------------------------
# Compute checksum for constant sections of page

sub checksum_prototype {
    my ($self, $prototype, $prototype_path) = @_;    

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

    $self->parse_blocks($prototype, $block_handler, $prototype_handler);
    return $md5->hexdigest;
}

#----------------------------------------------------------------------
# Get the prototype path for the current directory

sub get_prototype_path {
    my ($self, $filename) = @_;
    
    $filename = rel2abs($filename);
    $filename = abs2rel($filename, $self->{top_directory});
    my @path = splitdir($filename);
    pop(@path);
    
    my %prototype_path = map {$_ => 1} @path;
    return \%prototype_path;    
}

#----------------------------------------------------------------------
# Parse fields out of section tag

sub parse_blockname {
    my ($self, $str) = @_;
    
    my ($blockname, $in, $locality) = split(/\s+/, $str);
    
    if ($in) {
        die "Syntax error in block ($str)"
            unless $in eq 'in' && defined $locality;
    } else {
        $locality = '';
    }
    
    return ($blockname, $locality);
}

#----------------------------------------------------------------------
# This code considers the surrounding tags to be part of the block

sub parse_blocks {
    my ($self, $page, $block_handler, $prototype_handler) = @_;
    
    my $locality;
    my $block = '';
    my $blockname = '';
    my @tokens = split(/(<!--\s*(?:section|endsection)\s+.*?-->)/, $page);
    
    foreach my $token (@tokens) {
        if ($token =~ /^<!--\s*section\s+(.*?)-->/) {
            die "Improperly nested block ($token)\n" if $blockname;
                
            ($blockname, $locality) = $self->parse_blockname($1);
            $block .= $token
            
        } elsif ($token =~ /^<!--\s*endsection\s+(.*?)-->/) {
            my ($endname) = $self->parse_blockname($1);
            die "Unmatched ($token)\n"
                if $blockname eq '' || $blockname ne $endname;
                
            $block .= $token;
            $block_handler->($blockname, $locality, $block);

            $block = '';
            $blockname = '';

        } else {
            if ($blockname) {
                $block .= $token;
            } else {
                $prototype_handler->($token);
            }            
        }
    }
 
    die "Unmatched block (<!-- section $blockname -->)\n" if $blockname;
    return;
}

#----------------------------------------------------------------------
# Extract named blocks from a page

sub parse_page {
    my ($self, $page) = @_;
    
    my $blocks = {};
    my $block_handler = sub {
        my ($blockname, $locality, $blocktext) = @_;
        if (exists $blocks->{$blockname}) {
            die "Duplicate block name ($blockname)\n";
        }
        $blocks->{$blockname} = $blocktext;
        return;
    };
    
    my $prototype_handler = sub {
        return;
    };

    $self->parse_blocks($page, $block_handler, $prototype_handler);    
    return $blocks;
}

#----------------------------------------------------------------------
# Sort files so more recently modified files are first

sub sort_files {
    my ($self, $filenames) = @_;
       
    my @augmented_files;
    foreach my $filename (@$filenames) {
        my @stats = stat($filename);
        push(@augmented_files, [$stats[9], $filename]);
    }
    
    @augmented_files = sort {$b->[0] <=> $a->[0]} @augmented_files;
    @$filenames = map {$_->[1]} @augmented_files;

    return $filenames;
}

#----------------------------------------------------------------------
# Determine if page matches prototype or needs to be updated

sub unchanged_prototype {
    my ($self, $prototype, $page, $prototype_path) = @_;
    
    my $prototype_checksum =
        $self->checksum_prototype($prototype, $prototype_path);
    
    my $page_checksum =
        $self->checksum_prototype($page, $prototype_path);

    my $unchanged;
    if ($prototype_checksum eq $page_checksum) {
        $unchanged = 1;
    } else {
        $unchanged = 0;
    }
    
    return $unchanged;
}

#----------------------------------------------------------------------
# Perform all updates on the directory

sub update_directory {
    my ($self, $directory, $prototype, $prototype_path) = @_;

    my ($filenames, $directories) = $self->visit($directory);
    
    my @stats = stat($directory);
    my $modtime = $stats[9];

    # The first update uses a file from the directory above
    # as a prototype, if one is found

    unless (defined $prototype) {
        my $prototype_file = shift(@$filenames);  

        if (defined $prototype_file) {
            $prototype_path = $self->get_prototype_path($prototype_file);
            $prototype = $self->read_page($prototype_file);
        }
    }
    
    my $count = 0;
    my $changes = 0;
    foreach my $filename (@$filenames) {
        my $page = $self->read_page($filename);
        die "Couldn't read $filename" unless defined $page;

        # Check for changes before updating page
        my $skip = $self->unchanged_prototype($prototype, $page, $prototype_path);

        if ($skip) {
            last if $count;
            
        } else {    
            $page = $self->update_page($prototype, $page, $prototype_path);
        
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

    utime($modtime, $modtime, $directory);
    return unless $changes;

    my $template_directory = $self->full_file_name($self->{top_directory},
                                                   $self->{template_directory});
    
    for my $subdirectory (@$directories) {
        next if $subdirectory eq $template_directory;
        $self->update_directory($subdirectory, $prototype, $prototype_path);
    }

    return; 
}

#----------------------------------------------------------------------
# Parse prototype and page and combine them

sub update_page {
    my ($self, $prototype, $page, $prototype_path) = @_;
    $prototype_path = {} unless defined $prototype_path;
    
    my $output = [];
    my $blocks = $self->parse_page($page);
    
    my $block_handler = sub {
        my ($blockname, $locality, $blocktext) = @_;
        if (exists $blocks->{$blockname}) {
            if (exists $prototype_path->{$locality}) {
                push(@$output, $blocktext);          
            } else {
                push(@$output, $blocks->{$blockname});
            }
            delete $blocks->{$blockname};
        } else {
            push(@$output, $blocktext);
        }
        return;
    };

    my $prototype_handler = sub {
        my ($blocktext) = @_;
        push(@$output, $blocktext);
        return;
    };

    $self->parse_blocks($prototype, $block_handler, $prototype_handler);

    if (%$blocks) {
        my $names = join(' ', sort keys %$blocks);
        die "Unused blocks ($names)\n";
    }
    
    return join('', @$output);
}

1;
__END__

=encoding utf-8

=head1 NAME

App::Followme::FormatPages - Simple static web site maintenance

=head1 SYNOPSIS

    use App::Followme::FormatPages;
    my $formatter = App::Followme::FormatPages->new($configuration);
    $formatter->run($directory);
    
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

Updates to the named block can also be made conditional by adding an in after
the section name. If the folder name after the "in" is included in the
prototype_path hash, then the block tags are ignored, it is as if the block does
not exist. The block is considered as part of the constant portion of the
prototype. If the folder is not in the prototype_path, the block is treated as
any other block and varies from page to page.

    <!-- section name in folder -->
    <!-- endsection name -->

Text in conditional blocks can be used for navigation or other sections of the
page that are constant, but not constant across the entire site.

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

