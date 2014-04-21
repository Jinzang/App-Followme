package App::Followme::Template;

use 5.008005;
use strict;
use warnings;
use integer;

use Carp;
use IO::File;
use File::Spec::Functions qw(abs2rel catfile rel2abs splitdir);

use lib '../..';

use base qw(App::Followme::ConfiguredObject);

our $VERSION = "1.09";

use constant COMMAND_START => '<!-- ';
use constant COMMAND_END => '-->';

#----------------------------------------------------------------------
# Coerce a value to the type indicated by the sigil

sub coerce {
    my ($self, $sigil, $value) = @_;

    my $data;
    if (defined $value) {
        my $ref = ref $value;
    
        if ($sigil eq '$') {
            if (! $ref) {
                $data = \$value;
            } elsif ($ref eq 'ARRAY') {
                my $val = @$value;
                $data = \$val;
            } elsif ($ref eq 'HASH') {
                my @data = %$value;
                my $val = @data;
                $data = \$val;
            }
    
        } elsif ($sigil eq '@') {
            if (! $ref) {
                $data = [$value];
            } elsif ($ref eq 'ARRAY') {
                $data = $value;
            } elsif ($ref eq 'HASH') {
                my @data = %$value;
                $data = \@data;
            }
    
        } elsif ($sigil eq '%') {
            if ($ref eq 'ARRAY' && @$value % 2 == 0) {
                my %data = @$value;
                $data = \%data;
            } elsif ($ref eq 'HASH') {
                $data = $value;
            }
        }

    } elsif ($sigil eq '$') {
        $data = \$value;
    }
    
    return $data;
}

#----------------------------------------------------------------------
# Compile a template into a subroutine which when called fills itself

sub compile {
    my ($pkg, @templates) = @_;
    my $self = ref $pkg ? $pkg : $pkg->new();

    # Template precedes subtemplate, which precedes subsubtemplate

    my @block;
    my $sections = {};
    while (my $template = pop(@templates)) {
        my $fd = IO::File->new($template, 'r');
        die "Cannot read $template: $!\n" unless $fd;
    
        my @lines = <$fd>;
        close($fd);

        @block = $self->parse_block($sections, \@lines, '');
    }

    return $self->construct_code(\@block);
}

#----------------------------------------------------------------------
# Construct a subroutine from the code embedded in the template

sub construct_code {
    my ($self, $lines) = @_;

    my $code = <<'EOQ';
sub {
$self->init_stack();
$self->push_stack(@_);
my $text = '';
EOQ

    push(@$lines, "\n");
    $code .= $self->parse_code($lines);

    $code .= <<'EOQ';
chomp $text;
return $text;
}
EOQ

    my $sub = eval ($code);
    croak $@ unless $sub;
    return $sub;
}

#----------------------------------------------------------------------
# Replace variable references with hashlist fetches

sub encode_expression {
    my ($self, $value) = @_;

    if (defined $value) {
        my $pre = '{$self->fetch_stack(\'';
        my $mid = '\',\'';
        my $post = '\')}';
        $value =~ s/(?<!\\)([\$\@\%])(\w+)/$1$pre$1$mid$2$post/g;

    } else {
        $value = '';
    }

    return $value;
}

#----------------------------------------------------------------------
# Replace variable references with hashlist fetches

sub encode_text {
    my ($self, $value) = @_;

    if (defined $value) {
        my $pre = '${$self->fill_in(\'';
        my $mid = '\',\'';
        my $post = '\')}';
        $value =~ s/(?<!\\)([\$\@\%])(\w+)/$pre$1$mid$2$post/g;

    } else {
        $value = '';
    }

    return $value;
}

#----------------------------------------------------------------------
# Find and retrieve a value from the hash stack

sub fetch_stack {
    my ($self, $sigil, $name) = @_;

    my $value;
    for my $hash (@{$self->{stack}}) {
        if (exists $hash->{$name}) {
            $value = $hash->{$name};
            last;
        }
    }

    $value = $self->coerce($sigil, $value);
    croak "Illegal type conversion: $sigil$name" unless defined $value;

    return $value;
}

#----------------------------------------------------------------------
# Return a value to fill in a template

sub fill_in {
    my ($self, $sigil, $name) = @_;

    my $data = $self->fetch_stack($sigil, $name);
    my $result = $self->render($data);

    return \$result;
}

#----------------------------------------------------------------------
# Get the translation of a template command

sub get_command {
    my ($self, $cmd) = @_;

    my $commands = {
                    do => "%%;",
                    each => "while (my (\$k, \$v) = each %%) {\n" .
                            "\$self->push_stack({key=>\$k, value=>\$v});",
                    endeach => "\$self->pop_stack();\n}",
                    for => "foreach (%%) {\n\$self->push_stack(\$_);",
                	endfor => "\$self->pop_stack();\n}",
                    if => "if (%%) {",
                    elsif => "} elsif (%%) {",
                    else => "} else {",
                    endif => "}",
                    set => \&set_command,
                    while => "while (%%) {",
                    endwhile => "}",
                	with => "\$self->push_stack(\\%%);",
                    endwith => "\$self->pop_stack();",
                    };

    return $commands->{$cmd};
}

#----------------------------------------------------------------------
# Initialize the data stack

sub init_stack {
    my ($self) = @_;

    $self->{stack} = [];
    return;
}

#----------------------------------------------------------------------
# Is a command a singleton command?

sub is_singleton {
    my ($self, $cmd) = @_;

    return ! ($cmd eq 'section' || $self->get_command("end$cmd"));
}

#----------------------------------------------------------------------
# Read and check the template files

sub parse_block {
    my ($self, $sections, $lines, $command) = @_;

    my @block;
    while (defined (my $line = shift @$lines)) {
        my ($cmd, $arg) = $self->parse_command($line);

        if (defined $cmd) {
            if (substr($cmd, 0, 3) eq 'end') {
                $arg = substr($cmd, 3);
                croak "Mismatched block end ($command/$arg)"
                      if defined $arg && $arg ne $command;

                push(@block, $line);
                return @block;

            } elsif ($self->is_singleton($cmd)) {
                push(@block, $line);

            } else {
                my @sub_block = $self->parse_block($sections, $lines, $cmd);

                if ($cmd eq 'section') {
                    my $endline = pop(@sub_block);
                    my ($name, $rest) = split(' ', $arg, 2);

                    $sections->{$name} = \@sub_block
                        unless exists $sections->{$name};

                    push(@block, $line, @{$sections->{$name}}, $endline); 

                } else {
                    push(@block, $line, @sub_block);
                }
            }

        } else {
            push(@block, $line);
        }
    }

    croak "Missing end" if $command;
    return @block;
}

#----------------------------------------------------------------------
# Parse the templace source

sub parse_code {
    my ($self, $lines) = @_;

    my $code = '';
    my $stash = '';

    while (defined (my $line = shift @$lines)) {
        my ($cmd, $arg) = $self->parse_command($line);

        if (defined $cmd) {
            if (length $stash) {
                $code .= "\$text .= <<\"EOQ\";\n";
                $code .= "${stash}EOQ\n";
                $stash = '';
            }

            my $command = $self->get_command($cmd);
            if (defined $command) {
                my $ref = ref ($command);
                if (! $ref) {
                    $arg = $self->encode_expression($arg);
                    $command =~ s/%%/$arg/;
                    $code .= "$command\n";
    
                } elsif ($ref eq 'CODE') {
                    $code .= $command->($self, $arg);
    
                } else {
                    die "I don't know how to handle a $ref: $cmd";
                }
            
            } else {
                $stash .=  $self->encode_text($line);
            }

        } else {
            $stash .= $self->encode_text($line);
        }
    }

    if (length $stash) {
        $code .= "\$text .= <<\"EOQ\";\n";
        $code .= "${stash}EOQ\n";
    }

    return $code;
}

#----------------------------------------------------------------------
# Parse a command and its argument

sub parse_command {
    my ($self, $line) = @_;

    if ($line =~ s/$self->{command_start_pattern}//) {
        $line =~ s/$self->{command_end_pattern}//;
        return split(' ', $line, 2)
    }

    return;
}

#----------------------------------------------------------------------
# Return a hash of the sections in a page

sub parse_sections {
    my ($self, $page) = @_;
    
    # Extract sections from page
    
    my $sections = {};
    my @lines = map {"$_\n"} split(/\n/, $page);
    $self->parse_block($sections, \@lines, '');

    # Combine lines in each section into a single string
    
    foreach my $name (keys %$sections) {
        my $section = join('', @{$sections->{$name}});
        $sections->{$name} = $section;
    }
    
    return $sections;    
}

#----------------------------------------------------------------------
# Remove hash pushed on the stack

sub pop_stack {
    my ($self) = @_;
    return shift (@{$self->{stack}});
}

#----------------------------------------------------------------------
# Push one or more hashes on the stack

sub push_stack {
    my ($self, @hash) = @_;

    foreach my $hash (@hash) {
        my $newhash;
        if (ref $hash eq 'HASH') {
            $newhash = $hash;
        } else {
            $newhash = {data => $hash};
        }

        unshift (@{$self->{stack}}, $newhash);
    }

    return;
}

#----------------------------------------------------------------------
# Render a data structure as html

sub render {
    my ($self, $data) = @_;

    my $result;
    my $ref = ref $data;

    if ($ref eq 'SCALAR') {
        $result = defined $$data ? $$data : '';

    } elsif ($ref eq 'ARRAY') {
        my @result;
        foreach my $datum (@$data) {
            my $val = $self->render($datum);
            push(@result, "<li>$val</li>");
        }

        $result = join("\n", '<ul>', @result, '</ul>');

    } elsif ($ref eq 'HASH') {
        my @result;
        foreach my $key (sort keys %$data) {
            my $val = $self->render($data->{$key});
            push(@result, "<dt>$key</dt>", "<dd>$val</dd>");
        }

        $result = join("\n", '<dl>', @result, '</dl>');

    } else  {
        $result = "$data";
    }


    return $result;
}

#----------------------------------------------------------------------
# Set the regular expression patterns used to match a command

sub setup {
    my ($self, $configuration) = @_;

    $self->{command_start_pattern} = '^\s*' . quotemeta(COMMAND_START);
    $self->{command_end_pattern} = '\s*' . quotemeta(COMMAND_END) . '\s*$';

    return;
}

#----------------------------------------------------------------------
# Generate code for the set command, which stores results in the hashlist

sub set_command {
    my ($self, $arg) = @_;

    my ($var, $expr) = split (/\s*=\s*/, $arg, 2);
    $expr = $self->encode_expression($expr);

    return "\$self->store_stack(\'$var\', ($expr));\n";
}

#----------------------------------------------------------------------
# Store a variable in the hashlist, used by set

sub store_stack {
    my ($self, $var, @val) = @_;

    my ($sigil, $name) = $var =~ /([\$\@\%])(\w+)/;
    die "Unrecognized variable type: $name" unless defined $sigil;

    my $i;
    for ($i = 0; $i < @{$self->{stack}}; $i ++) {
        last if exists $self->{stack}[$i]{$name};
    }

    $i = 0 unless $i < @{$self->{stack}};

    if ($sigil eq '$') {
        my $val = @val == 1 ? $val[0] : @val;
        $self->{stack}[$i]{$name} = $val;

    } elsif ($sigil eq '@') {
        $self->{stack}[$i]{$name} = \@val;

    } elsif ($sigil eq '%') {
        my %val = @val;
        $self->{stack}[$i]{$name} = \%val;
    }

    return;
}

1;

=pod

=encoding utf-8

=head1 NAME

App::Followme::Template - Handle templates and prototype files

=head1 SYNOPSIS

    use App::Followme::Template;
    my $template = App::Followme::Template->new;
    my $render = $template->compile($prototype_file, $template_file);
    my $output = $render->($hash);

=head1 DESCRIPTION

This module contains the methods that perform template handling. A Template is a
file containing commands and variables for making a web page. First, the
template is compiled into a subroutine and then the subroutine is called with a
hash as an argument to fill in the variables and produce a web
page.

=head1 METHODS

This module has one public method:

=over 4

=item $sub = $self->compile($prototype_file, $template_file);

Combine a prototype file and a template, compile them, and return the compiled
subroutine. The prototype is the most recently modified file in the directory. A
template if a file containing commands and variables that describe how data is to
be represented. The method returns a subroutine reference, which when called
with a reference to a hash, returns a web page containing the data in the hash.
fields in the hash are substituted into variables in the template. Variables in
the template are preceded by Perl sigils, so that a link would look like:

    <li><a href="$url">$title</a></li>

=back

=head1 TEMPLATE SYNTAX

Templates support the control structures in Perl: "for" and "while" loops,
"if-else" blocks, and some others. Creating output is a two step process. First
you generate a subroutine from one or more templates, then you call the
subroutine with your data to generate the output.

The template format is line oriented. Commands are enclosed in html comments
(<!-- -->). A command may be preceded by white space. If a command is a block
command, it is terminated by the word "end" followed by the command name. For
example, the "for" command is terminated by an "endfor" command and the "if"
command by an "endif" command.

All lines may contain variables. As in Perl, variables are a sigil character
('$,' '@,' or '%') followed by one or more word characters. For example,
C<$name> or C<@names>. To indicate a literal character instead of a variable,
precede the sigil with a backslash. When you run the subroutine that this module
generates, you pass it a reference, usually a reference to a hash, containing
some data. The subroutine replaces variables in the template with the value in
the field of the same name in the hash. If the types of the two disagree, the
code will coerce the data to the type of the sigil. You can pass a reference to
an array instead of a hash to the subroutine this module generates. If you do,
the template will use C<@data> to refer to the array.

If the first non-white characters on a line are the command start string, the
line is interpreted as a command. The command name continues up to the first
white space character. The text following the initial span of white space is the
command argument. The argument continues up to the command end string, or if
this is empty, to the end of the line.

Variables in the template have the same format as ordinary Perl variables,
a string of word characters starting with a sigil character. for example,

    $SUMMARY @data %dictionary

are examples of variables. The subroutine this module generates will substitute
values in the data it is passed for the variables in the template. New variables
can be added with the "set" command.

Arrays and hashes are rendered as unordered lists and definition lists when
interpolating them. This is done recursively, so arbitrary structures can be
rendered. This is mostly intended for debugging, as it does not provide fine
control over how the structures are rendered. For finer control, use the
commands described below so that the scalar fields in the structures can be
accessed. Undefined fields are replaced with the empty string when rendering. If
the type of data passed to the subroutine differs from the sigil on the variable
the variable is coerced to the type of the sigil. This works the same as an
assignment. If an array is referenced as a scalar, the length of the array is
output.

The following commands are supported in templates:

=over 4

=item do

The remainder of the line is interpreted as Perl code. For assignments, use
the set command.

=item each

Repeat the text between the "each" and "endeach" commands for each entry in the
hash table. The hast table key can be accessed through the variable $key and
the hash table value through the variable $value. Key-value pairs are returned
in random order. For example, this code displays the contents of a hash as a
list:

    <ul>
    <!-- each %hash -->
    <li><b>$key</b> $value</li>
    <!-- endeach -->
    </ul>

=item for

Expand the text between the "for" and "endfor" commands several times. The
"for" command takes a name of a field in a hash as its argument. The value of this
name should be a reference to a list. It will expand the text in the for block
once for each element in the list. Within the "for" block, any element of the list
is accessible. This is especially useful for displaying lists of hashes. For
example, suppose the data field name phonelist points to an array. This array is
a list of hashes, and each hash has two entries, name and phone. Then the code

    <!-- for @phonelist -->
    <p>$name<br>
    $phone</p>
    <!-- endfor -->

displays the entire phone list.

=item if

The text until the matching C<endif> is included only if the expression in the
"if" command is true. If false, the text is skipped. The "if" command can contain
an C<else>, in which case the text before the "else" is included if the
expression in the "if" command is true and the text after the "else" is included
if it is false. You can also place an "elsif" command in the "if" block, which
includes the following text if its expression is true.

    <!-- if $highlight eq 'y' -->
    <em>$text</em>
    <!-- else -->
    $text
    <!-- endif -->

=item section

If a template contains a section, the text until the endsection command will be
replaced by the section block with the same name in one the subtemplates. For
example, if the main template has the code

    <!-- section footer -->
    <div></div>
    <!-- endsection -->

and the subtemplate has the lines

    <!-- section footer -->
    <div>This template is copyright with a Creative Commons License.</div>
    <!-- endsection -->

The text will be copied from a section in the subtemplate into a section of the
same name in the template. If there is no block with the same name in the
subtemplate, the text is used unchanged.

=item set

Adds a new variable or updates the value of an existing variable. The argument
following the command name looks like any Perl assignment statement minus the
trailing semicolon. For example,

    <!-- set $link = "<a href=\"$url\">$title</a>" -->

=item while

Expand the text between the C<while> and C<endwhile> as long as the
expression following the C<while> is true.

    <!-- set $i = 10 -->
    <p>Countdown ...<br>
    <!-- while $i >= 0 -->
    $i<br>
    <!-- set $i = $i - 1 -->
    <!-- endwhile -->

=item with

Lists within a hash can be accessed using the "for" command. Hashes within a
hash are accessed using the "with" command. For example:

    <!-- with %address -->
    <p><i>$street<br />
    $city, $state $zip</i></p.
    <!-- endwith -->

=back

=head1 ERRORS

What to check when this module throws an error

=over 4

=item Couldn't read template

The template is in a file and the file could not be opened. Check the filename
and permissions on the file. Relative filenames can cause problems and the web
server is probably running another account than yours.

=item Illegal type conversion

The sigil on a variable differs from the data passed to the subroutine and
conversion. between the two would not be legal. Or you forgot to escape the '@'
in an email address by preceding it with a backslash.

=item Unknown command

Either a command was spelled incorrectly or a line that is not a command
begins with the command start string.

=item Missing end

The template contains a command for the start of a block, but
not the command for the end of the block. For example  an "if" command
is missing an "endif" command.

=item Mismatched block end

The parser found a different end command than the begin command for the block
it was parsing. Either an end command is missing, or block commands are nested
incorrectly.

=item Syntax error

The expression used in a command is not valid Perl.

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut
