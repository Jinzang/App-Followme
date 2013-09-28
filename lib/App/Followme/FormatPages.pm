package App::Followme::FormatPages;
use 5.008005;
use strict;
use warnings;

use Cwd;
use IO::Dir;
use IO::File;
use Digest::MD5 qw(md5_hex);
use File::Spec::Functions qw(abs2rel rel2abs splitdir catfile updir);

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

    my @filenames = $self->sort_by_date(glob('*.html'));
    my $filename = pop(@filenames);
    return 1 unless $filename;
    
    my $count = 0;
    my $decorated = 1;
    my $template = $self->make_template($filename);
    my $template_path = $self->get_template_path($filename);

    foreach $filename (@filenames) {        
        my $page = $self->read_page($filename);
        die "Couldn't read $filename" unless defined $page;

        my $skip = $self->unchanged_template($template, $page,
                                             $decorated, $template_path);

        if ($skip) {
            last unless $self->{options}{all};

        } else {
            $count ++;
            
            if ($self->{options}{noop}) {
                print "$filename\n";

            } else {
                my $new_page = $self->update_page($template, $page,
                                                  $decorated, $template_path);
                $self->write_page($filename, $new_page);
            }
        }
    }
    
    return $count;
}

#----------------------------------------------------------------------
# Compute checksum for template

sub checksum_template {
    my ($self, $template, $decorated, $template_path) = @_;    

    my $md5 = Digest::MD5->new;

    my $block_handler = sub {
        my ($blockname, $locality, $blocktext) = @_;
        $md5->add($blocktext) if exists $template_path->{$locality};
    };
    
    my $template_handler = sub {
        my ($blocktext) = @_;
        $md5->add($blocktext);
        return;
    };

    $self->parse_blocks($template, $decorated, $block_handler,
                        $template_handler);

    return $md5->hexdigest;
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
        
        my @files = $self->sort_by_date(glob('*.html'));
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
        my $page = $self->read_page($filename);
        $template = $self->read_page($template_file);
        my $template_path = $self->get_template_path($template_file);

        if ($self->unchanged_template($template, $page,
                                      $decorated, $template_path)) {
            $template = $page;

        } elsif ($self->{options}{noop}) {
                print "$filename\n";

         } else {
            $template = $self->update_page($template, $page,
                                           $decorated, $template_path);
            $self->write_page($filename, $template);
        }
        
    } else {
        $template = $self->read_page($filename);
    }
    
    return $template;
}

#----------------------------------------------------------------------
# Parse fields out of block tag

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
# Break page into template and blocks

sub parse_blocks {
    my ($self, $page, $decorated, $block_handler, $template_handler) = @_;
    
    my $locality;
    my $block = '';
    my $blockname = '';
    my @tokens = split(/(<!--\s*(?:section|endsection)\s+.*?-->)/, $page);
    
    foreach my $token (@tokens) {
        if ($token =~ /^<!--\s*section\s+(.*?)-->/) {
            die "Improperly nested block ($token)\n" if $blockname;
                
            ($blockname, $locality) = $self->parse_blockname($1);
            if ($decorated) {
                $block .= $token
            } else {
                $template_handler->($token);
            }
            
        } elsif ($token =~ /^<!--\s*endsection\s+(.*?)-->/) {
            my ($endname) = $self->parse_blockname($1);
            die "Unmatched ($token)\n"
                if $blockname eq '' || $blockname ne $endname;
                
            if ($decorated) {
                $block .= $token;
                $block_handler->($blockname, $locality, $block);
            } else {
                $block_handler->($blockname, $locality, $block);
                $template_handler->($token);
            }

            $block = '';
            $blockname = '';

        } else {
            if ($blockname) {
                $block .= $token;
            } else {
                $template_handler->($token);
            }            
        }
    }
 
    die "Unmatched block (<!-- section $blockname -->)\n" if $blockname;
    return;
}

#----------------------------------------------------------------------
# Parse filename into directory, root, and extension

sub parse_filename {
    my ($self, $filename) = @_;

    my @dirs = splitdir($filename);
    my $basename = pop(@dirs);
    my ($root, $ext) = split(/\./, $basename);
    my $dir = @dirs ? catfile(@dirs) : '';
    
    return ($dir, $root, $ext);
}

#----------------------------------------------------------------------
# Extract named blocks from a page

sub parse_page {
    my ($self, $page, $decorated) = @_;
    
    my $blocks = {};
    my $block_handler = sub {
        my ($blockname, $locality, $blocktext) = @_;
        if (exists $blocks->{$blockname}) {
            die "Duplicate block name ($blockname)\n";
        }
        $blocks->{$blockname} = $blocktext;
        return;
    };
    
    my $template_handler = sub {
        return;
    };

    $self->parse_blocks($page, $decorated, $block_handler, $template_handler);    
    return $blocks;
}

#----------------------------------------------------------------------
# Read a file into a string

sub read_page {
    my ($self, $filename) = @_;

    local $/;
    my $fd = IO::File->new($filename, 'r');
    return unless $fd;
    
    my $page = <$fd>;
    close($fd);
    
    return $page;
}

#----------------------------------------------------------------------
# Sort a list of files so the least recently modified file is first

sub sort_by_date {
    my ($self, @filenames) = @_;

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
# Determine if page matches template or needs to be updated

sub unchanged_template {
    my ($self, $template, $page, $decorated, $template_path) = @_;
    
    my $template_checksum = $self->checksum_template($template,
                                                     $decorated,
                                                     $template_path);
    my $page_checksum = $self->checksum_template($page,
                                                 $decorated,
                                                 $template_path);

    my $unchanged;
    if ($template_checksum eq $page_checksum) {
        $unchanged = 1;
    } else {
        $unchanged = 0;
    }
    
    return $unchanged;
}

#----------------------------------------------------------------------
# Parse template and page and combine them

sub update_page {
    my ($self, $template, $page, $decorated, $template_path) = @_;

    my $output = [];
    my $blocks = $self->parse_page($page, $decorated);
    
    my $block_handler = sub {
        my ($blockname, $locality, $blocktext) = @_;
        if (exists $blocks->{$blockname}) {
            if (exists $template_path->{$locality}) {
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

    my $template_handler = sub {
        my ($blocktext) = @_;
        push(@$output, $blocktext);
        return;
    };

    $self->parse_blocks($template, $decorated,
                        $block_handler, $template_handler);

    if (%$blocks) {
        my $names = join(' ', sort keys %$blocks);
        die "Unused blocks ($names)\n";
    }
    
    return join('', @$output);
}

#----------------------------------------------------------------------
# Write the page back to the file

sub write_page {
    my ($self, $filename, $page) = @_;

    my $modtime;
    if (-e $filename) {
        my @stats = stat($filename);
        $modtime = $stats[9];
    }

    my $fd = IO::File->new($filename, 'w');
    die "Couldn't write $filename" unless $fd;
    
    print $fd $page;
    close($fd);
        
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

