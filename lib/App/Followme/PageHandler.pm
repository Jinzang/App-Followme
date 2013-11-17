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
            web_extension => 'html',
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
    my $directory = $self->{base_directory};
    my $top_directory = App::Followme::TopDirectory->name;
    
    for (;;) {
        if ($uplevel) {
            $uplevel -= 1;

        } else {
            my $mrf = App::Followme::MostRecentFile->new($directory);
            $filename = $mrf->next;
            last if $filename;
        }

        last if $directory eq $top_directory;
        chdir(updir());
        $directory = getcwd();
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
        my $decorated = 0;
        my $prototype_path = {};
        $final_template = $self->update_page($prototype, $template, 
                                             $decorated, $prototype_path);
    } else {
        $final_template = $template;
    }

    return $final_template;
}

#----------------------------------------------------------------------
# Return 1 if filename passes test

sub match_file {
    my ($self, $path) = @_;
    return ! -d $path && $path =~ /\.$self->{web_extension}$/;
}

#----------------------------------------------------------------------
# Return 1 if folder passes test

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
    my ($self, $page, $decorated, $block_handler, $prototype_handler) = @_;
    
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
                $prototype_handler->($token);
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
                $prototype_handler->($token);
            }

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
    
    my $prototype_handler = sub {
        return;
    };

    $self->parse_blocks($page, $decorated, $block_handler, $prototype_handler);    
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
    my ($self, $prototype, $page, $decorated, $prototype_path) = @_;

    my $output = [];
    my $blocks = $self->parse_page($page, $decorated);
    
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

    $self->parse_blocks($prototype, $decorated,
                        $block_handler, $prototype_handler);

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
