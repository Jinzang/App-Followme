package App::Followme::FormatPage;
use 5.008005;
use strict;
use warnings;

use lib '../..';

use base qw(App::Followme::Module);

use Digest::MD5 qw(md5_hex);
use File::Spec::Functions qw(abs2rel rel2abs splitdir catfile);
use App::Followme::FIO;

our $VERSION = "2.03";

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($pkg) = @_;

    return (
            data_pkg => 'App::Followme::WebData',
    );
}

#----------------------------------------------------------------------
# Modify pages to match the most recently modified page

sub run {
    my ($self, $folder) = @_;

    $self->update_folder($folder);
    return;
}
#----------------------------------------------------------------------
# Add falsified conditionals from another file

sub add_conditionals {
    my ($self, $falsified_blocks, $page, $file) = @_;

    my $block_handler = sub {
        my ($blockname, $expr, $blocktext) = @_;
        $falsified_blocks->{$blockname} += 1 unless $self->evaluate($expr, $file);
    };

    my $prototype_handler = sub {
        return;
    };

    $self->parse_blocks($page, $block_handler, $prototype_handler);
    return $falsified_blocks;
}

#----------------------------------------------------------------------
# Check for conditional blocks keep a list of those tht are false

sub check_conditionals {
    my ($self, $page, $file, $prototype, $prototype_file) = @_;

    my $falsified_blocks = {};
    $falsified_blocks = $self->add_conditionals($falsified_blocks, $prototype,  $prototype_file);
    $falsified_blocks = $self->add_conditionals($falsified_blocks, $page, $file) 
                        if length $falsified_blocks;

    # Delete blocks not present in both files
    while (my ($blockname, $value) = each %$falsified_blocks) {
        delete $falsified_blocks->{$blockname} unless $value == 2;
    }

    return $falsified_blocks;
}

#----------------------------------------------------------------------
# Compute checksum for constant sections of page
# TODO: rewrite to use $block_list

sub checksum_page {
    my ($self, $page, $falsified_blocks) = @_;
    my $md5 = Digest::MD5->new;

    # Checksum includes conditional block if false in both
    my $block_handler = sub {
        my ($blockname, $expr, $blocktext) = @_;
        $md5->add($blocktext) if $falsified_blocks->{$blockname};
    };

    my $prototype_handler = sub {
        my ($blocktext) = @_;
        $md5->add($blocktext);
        return;
    };

    $self->parse_blocks($page, $block_handler, $prototype_handler);
    return $md5->hexdigest;
}

#----------------------------------------------------------------------
# Evaluate an expression for truthiness

sub evaluate {
    my ($self, $expr, $item) = @_;
    return 1 unless defined $expr;

    my @loop;
    my $meta = $self->{data};
    my $template = $self->{template};

    my $code = $template->encode_expression($expr);
    my $value = eval $code;
    die $@ unless defined $value;

    return $value;
}

#----------------------------------------------------------------------
# Parse fields out of section tag

sub parse_blockname {
    my ($self, $str) = @_;

    my ($blockname, $if, $expr) = split(/\s+/, $str, 3);
    if ($if) {
        die "Syntax error in block ($str)"
            unless $if eq 'if' && defined $expr;
    } else {
        undef $expr;
    }

    return ($blockname, $expr);
}

#----------------------------------------------------------------------
# This code considers the surrounding tags to be part of the block

sub parse_blocks {
    my ($self, $page, $block_handler, $prototype_handler) = @_;

    my @tokens = split(/(<!--\s*(?:section|endsection)\s+.*?-->)/, $page);

    my $expr;
    my $block = '';
    my $blockname = '';
    foreach my $token (@tokens) {
        if ($token =~ /^<!--\s*section\s+(.*?)-->/) {
            die "Improperly nested block ($token)\n" if $blockname;

            ($blockname, $expr) = $self->parse_blockname($1);
            $block .= $token

        } elsif ($token =~ /^<!--\s*endsection\s+(.*?)-->/) {
            my ($endname) = $self->parse_blockname($1);
            die "Unmatched ($token)\n"
                if $blockname eq '' || $blockname ne $endname;

            $block .= $token;
            $block_handler->($blockname, $expr, $block);

            $block = '';
            $blockname = '';

        } elsif ($blockname) {
            $block .= $token;

        } else {
            $prototype_handler->($token);
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
        my ($blockname, $expr, $blocktext) = @_;
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
# Initialize the extension

sub setup {
    my ($self) = @_;

    $self->{extension} = $self->{web_extension};
    return;
}

#----------------------------------------------------------------------
# Determine if page matches prototype or needs to be updated

sub unchanged_prototype {
    my ($self, $page, $prototype, $falsified_blocks) = @_;

    my $page_checksum = $self->checksum_page($page, $falsified_blocks);
    my $prototype_checksum = $self->checksum_page($prototype, $falsified_blocks);
 
    my $unchanged = $page_checksum eq $prototype_checksum;
    return $unchanged;
}

#----------------------------------------------------------------------
# Update file using prototype

sub update_file {
    my ($self, $page, $file, $prototype, $prototype_file) = @_;

    my $falsified_blocks = $self->check_conditionals($page, $file, 
                                                     $prototype, $prototype_file);

    # Check for changes before updating page
    return 0 if $self->unchanged_prototype($page, $prototype, $falsified_blocks);

    $page = $self->update_page($page, $prototype, $falsified_blocks);

    my $modtime = fio_get_date($file);
    fio_write_page($file, $page);
    fio_set_date($file, $modtime);

    return 1;
}

#----------------------------------------------------------------------
# Perform all updates on the directory

sub update_folder {
    my ($self, $folder, $prototype_file) = @_;

    # The first update uses a file from the  directory above
    # as a prototype, if one is found

    $prototype_file ||= $self->find_prototype($folder, 1);
    my $prototype = fio_read_page($prototype_file);
    die "No prototype file" unless $prototype;

    my $index_file = $self->to_file($folder);
    my $modtime = fio_get_date($folder);

    my $files = $self->{data}->build('files_by_mdate_reversed', $index_file);

    my $changes = 0;
    foreach my $file (@$files) {
        next if fio_same_file($file, $prototype_file);

        my $page = fio_read_page($file);
        next unless defined $page;

        my $change;
        eval {$change = $self->update_file($page, $file, $prototype, $prototype_file)};
        $self->check_error($@, $file);

        last unless $change;
        $changes += 1;
    }

    fio_set_date($folder, $modtime);

    # Update files in subdirectory

    if ($changes || @$files == 0) {
        my $folders = $self->{data}->build('folders', $index_file);

        foreach my $subfolder (@$folders) {
            $self->update_folder($subfolder, $prototype_file);
        }
    }

    return;
}

#----------------------------------------------------------------------
# Parse prototype and page and combine them

sub update_page {
    my ($self, $page, $prototype, $falsified_blocks) = @_;

    my $output = [];
    my $blocks = $self->parse_page($page);

    # Conditional block taken from prototype if false in both
    my $block_handler = sub {
        my ($blockname, $expr, $blocktext) = @_;
        if (exists $blocks->{$blockname}) {
            if ($falsified_blocks->{$blockname}) {
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

App::Followme::FormatPages - Modify pages in a directory to match a prototype

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

Updates to the named block can also be made conditional by adding an "if" after
the section name. If the expression after the "if" is false, 
then the block tags are ignored, it is as if the block does
not exist. The block is considered as part of the constant portion of the
prototype. If the expression is true, the block is treated as
any other block and varies from page to page.

    <!-- section name if $name eq 'index.html' -->
    <!-- endsection name -->

Text in conditional blocks can be used for navigation or other sections of the
page that are constant, but not constant across the entire site.

=head1 CONFIGURATION

The following parameters are used from the configuration:

=over 4

=item exclude_index

If this value is non-zero, the index page in a folder will not change when other
pages in its folder change and vice versa. The default value of this variable is 
zero.

=item data_pkg

The name of the module that processes web files. The default value is
'App::Followme::WebData'.

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
