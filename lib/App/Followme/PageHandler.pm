package App::Followme::PageHandler;
use 5.008005;
use strict;
use warnings;

use lib '../..';

use Cwd;
use IO::File;
use File::Spec::Functions qw(abs2rel catfile rel2abs splitdir updir);
use App::Followme::TopDirectory;
use App::Followme::MostRecentFile;

use base qw(App::Followme::EveryFile);

our $VERSION = "0.93";

use constant MONTHS => [qw(January February March April May June July
                           August September October November December)];

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($pkg) = @_;
    
    my %parameters = (
            absolute => 0,
            quick_update => 0,
           );

    my %base_params = $pkg->SUPER::parameters();
    %parameters = (%base_params, %parameters);

    return %parameters;
}

#----------------------------------------------------------------------
# Create a new page from the old (example)

sub run {
    my ($self) = @_;

    my $template = $self->make_template();
    my $sub = $self->compile_template($template);

    while (defined(my $filename = $self->next)) {
        eval {
              my $data = $self->set_fields($filename);
              my $page = $sub->($data);
              $self->write_page($filename, $page);
             };

        warn "$filename: $@" if $@;
    }

    return ! $self->{quick_update};    
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
# Get the title from the filename root

sub build_title {
    my ($self, $data, $filename) = @_;
    
    my ($dir, $root, $ext) = $self->parse_filename($filename);

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
# Build a url from a filename

sub build_url {
    my ($self, $data, $filename) = @_;

    my $directory = $self->{absolute}
                  ? App::Followme::TopDirectory->name()
                  : $self->{base_directory};
                  
    $filename = catfile($filename, 'index.html') if -d $filename;
    $filename = rel2abs($filename);
    $filename = abs2rel($filename, $directory);

    my $url = join('/', splitdir($filename));
    $url = "/$url" if $self->{absolute};
    $url =~ s/\.[^\.]*$/.$self->{web_extension}/;

    $data->{url} = $url;
    return $data;
}

#----------------------------------------------------------------------
# Compile a template into a subroutine

sub compile_template {
    my ($self, $template, $variable) = @_;
    $variable = '{{*}}' unless $variable;
    
    my ($left, $right) = split(/\*/, $variable);
    $left = quotemeta($left);
    $right = quotemeta($right);
    
    my $code = <<'EOQ';
sub {
my ($data) = @_;
my ($block, @blocks);
EOQ

    my @tokens = split(/(<!--\s*(?:loop|endloop).*?-->)/, $template);
    
    foreach my $token (@tokens) {
        if ($token =~ /^<!--\s*loop/) {
            $code .= 'foreach my $data (@{$data->{loop}}) {' . "\n";

        } elsif ($token =~ /^<!--\s*endloop/) {
            $code .= "}\n";

        } else {
            $code .= "\$block = <<'EOQ';\n";
            $code .= "${token}\nEOQ\n";
            $code .= "chomp \$block;\n";
            $code .= "\$block =~ s/$left(\\w+)$right/\$data->{\$1}/g;\n";
            $code .= "push(\@blocks,\$block);\n";
        }
    }
    
    $code .= <<'EOQ';
return join('', @blocks);
}
EOQ

    my $sub = eval ($code);
    die $@ unless $sub;
    return $sub;
}

#----------------------------------------------------------------------
# Get fields external to file content

sub external_fields {
    my ($self, $data, $filename) = @_;

    $data = $self->build_date($data, $filename);
    $data = $self->build_title($data, $filename);
    $data = $self->build_url($data, $filename);

    return $data;
}

#----------------------------------------------------------------------
# Find an file to serve as a prototype for updating other files

sub find_prototype {
    my ($self, $uplevel) = @_;

    my $filename;
    chdir($self->{base_directory});
    my $top_directory = App::Followme::TopDirectory->name;
    
    for (;;) {
        my $directory = getcwd();
        if ($uplevel) {
            $uplevel -= 1;

        } else {
            my $mrf = App::Followme::MostRecentFile->new($directory);
            $filename = $mrf->next;
            last if $filename;
        }

        last if $directory eq $top_directory;
        chdir(updir());
    }

    chdir($self->{base_directory});
    return $filename;
}

#----------------------------------------------------------------------
# Get the full template name (stub)

sub get_template_name {
    my ($self) = @_;
    
    return catfile($self->{base_directory}, 'template.htm');
}

#----------------------------------------------------------------------
# Get fields from reading the file (stub)

sub internal_fields {
    my ($self, $data, $filename) = @_;   

    $data->{body} = $self->read_page($filename);
    return $data;
}

#----------------------------------------------------------------------
# Combine template with prototype

sub make_template {
    my ($self) = @_;

    my $template_name = $self->get_template_name();
    my $template = $self->read_page($template_name);
    die "Couldn't find template: $template_name\n" unless $template;

    my $prototype_name = $self->find_prototype(0);
    my $prototype = $self->read_page($prototype_name); 
    
    my $final_template;
    if ($prototype) {
        my $prototype_path = {};
        $final_template = $self->update_page($prototype, $template, 
                                             $prototype_path);
    } else {
        $final_template = $template;
    }

    return $final_template;
}

#----------------------------------------------------------------------
# Do not descend into folders

sub match_folder {
    my ($self, $path) = @_;
    return;
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
# Break page into blocks

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
            $prototype_handler->($token);

            
        } elsif ($token =~ /^<!--\s*endsection\s+(.*?)-->/) {
            my ($endname) = $self->parse_blockname($1);
            die "Unmatched ($token)\n"
                if $blockname eq '' || $blockname ne $endname;
                
            $block_handler->($blockname, $locality, $block);
            $prototype_handler->($token);

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
# Set the data fields for a file

sub set_fields {
    my ($self, $filename) = @_;
    
    my $data = {};
    $data = $self->external_fields($data, $filename);
    $data = $self->internal_fields($data, $filename);

    return $data;
}

#----------------------------------------------------------------------
# Parse prototype and page and combine them

sub update_page {
    my ($self, $prototype, $page, $prototype_path) = @_;

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

#----------------------------------------------------------------------
# Write the page back to the file

sub write_page {
    my ($self, $filename, $page) = @_;

    my $fd = IO::File->new($filename, 'w');
    die "Couldn't write $filename" unless $fd;
    
    print $fd $page;
    close($fd);
        
    return;
}

1;
__END__
=encoding utf-8

=head1 NAME

App::Followme::PageHandler - Base class fo

=head1 SYNOPSIS

    use App::Followme::PageHandler;
    $handler = App::Followme::PageHandler($configuration);
    $handler->run();

=head1 DESCRIPTION

App::Followme::PageHandler is the base class for all the modules that
App::Followme uses to process a website. It is not called directly, it just
contains the common methods used by modules, which access them by subclassing
it.

=head1 FUNCTIONS

Some of the common methods are:

=over 4

=item my $data = $self->build_date($data, $filename);

The variables calculated from the modification time are: C<weekday, month,>
C<monthnum, day, year, hour24, hour, ampm, minute,> and C<second.>

=item my $data = $self->build_title($data, $filename);

The title of the page is derived from the file name by removing the filename
extension, removing any leading digits,replacing dashes with spaces, and
capitalizing the first character of each word.

=item $data = $self->build_url($data, $filename);

Build the url that of a web page from its filename.

=item my $sub = $self->compile_template($template, $variable);

Compile_template compiles a template contained in a string into a subroutine.
Then the subroutine can be called with one argument, a hash containing the data
to be interpolated into the subroutine. The output is a page containing the
template with the interpolated data. The data supplied to the subroutine should
be a hash reference. fields in the hash are substituted into variables in the
template. Variables in the template are surrounded by double braces, so that a
link would look like:

    <li><a href="{{url}}">{{title}}</a></li>

The string which indicates a variable is passed as an optional second argument
to compile_template. If not present or blank,double braces are used. If present,
the string should contain an asterisk to indicate where the variable name is
placed.

The data hash may contain a list of hashes, which should be named loop. Text
in between loop comments will be repeated for each hash in the list and each
hash will be interpolated into the text. Loop comments look like

    <!-- loop -->
    <!-- endloop -->

There should be only one pair of loop comments in the template. 

=item $blocks = $self->parse_page($page);

Extract blocks from a web page. Page is a string containing the web page.

=item $str = $self->read_page($filename);

Read a fie into a string. An the entire file is read from a string, there is no
line at a time IO. This is because files are typically small and the parsing
done is not line oriented. 

=item $data = $self->set_fields($filename);

Create title, url, and date variables from the filename and the modification date
of the file. Calculate the body variable from the contents of the file.

=item $page = $self->update_page($prototype, $page, $prototype_path);

This function combines the contents of a prototype and page to create a new
page. Update_page updates the constant portions of a web page from a prototype. 
Each html page has sections that are different from other pages and other
sections that are the same. The sections that differ are enclosed in html
comments that look like

    <!-- section name-->
    <!-- endsection name -->

and indicate where the section begins and ends. A page is
updated by substituting all its named blocks into corresponding block in the
prototype. The effect is that all the text outside the named blocks are
updated to be same as the text in the prototype.

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

Both prototype and page are strings, not filenames. Template_path is a hash
containing the directories from the base directory of the web site down to the
directory containing the prototype. The hash is treated as a set, that is, the
directory names are the keys and the values of the keys are one/

=item $self->write_page($filename, $str);

Write a file from a string. An the entire file is read to or written from a
string, there is no line at a time IO. This is because files are typically small
and the parsing done is not line oriented. 

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut

