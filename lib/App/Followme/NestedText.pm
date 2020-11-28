package App::Followme::NestedText;

use 5.008005;
use strict;
use warnings;
use integer;
use lib '../..';

our $VERSION = "1.95";

use App::Followme::FIO;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(nt_merge_items nt_parse_file 
                 nt_parse_string nt_write_file);

#----------------------------------------------------------------------
# Merge items from two configurations

sub nt_merge_items {
    my ($old_config, $new_config) = @_;

    my $final_config;
    my $ref = ref $old_config;

    if ($ref eq ref $new_config) {
        if ($ref eq 'ARRAY') {
            $final_config = [];
            @$final_config = @$old_config;
            my %old = map {$_ => 1} @$old_config;

            foreach my $item (@$new_config) {
                push(@$final_config, $item) unless $old{$item};    
            }

        } elsif ($ref eq 'HASH') {
            $final_config = {};
            %$final_config = %$old_config;

            foreach my $name (keys %$new_config) {
                if (exists $old_config->{$name}) {
                    $final_config->{$name} = nt_merge_items($old_config->{$name},
                                                            $new_config->{$name});
                } else {
                    $final_config->{$name} = $new_config->{$name};
                }
            }

        } else {
            $final_config = $new_config;
        }

    } else {
        $final_config = $new_config;
    }

    return $final_config;
}

#----------------------------------------------------------------------
# Read file in NestedText Format

sub nt_parse_file {
	my ($filename) = @_;

	my %configuration;
	my $page = fio_read_page($filename);

	eval {%configuration = nt_parse_string($page)};
	die "$filename: $@" if $@;

	return %configuration;
}

#----------------------------------------------------------------------
# Read string in NestedText Format

sub nt_parse_string {
	my ($page) = @_;

	my @lines = split(/\n/, $page);
	my $block = parse_block(\@lines);
	
	if (@lines) {
		my $msg = trim_string(shift(@lines));
		die("Bad indent at $msg\n");
	}

	if (ref($block) ne 'HASH') {
		die("Configuration must be a hash\n");
	}

	return %$block;
}

#----------------------------------------------------------------------
# Write file in NestedText Format

sub nt_write_file {
	my ($filename, %configuration) = @_;

	my ($type, $page) = format_value(\%configuration);
    $page .= "\n";

	fio_write_page($filename, $page);
	return;
}

#----------------------------------------------------------------------
# Format a value as a string for writing

sub format_value {
	my ($value, $level) = @_;
	$level = 0 unless defined $level;

	my $text;
    my $type = ref $value;
	my $leading = ' ' x (4 * $level);
	if ($type eq 'ARRAY') {
		my @subtext;
		foreach my $subvalue (@$value) {
			my ($subtype, $subtext) = format_value($subvalue, $level+1);
			if ($subtype) {
				$subtext = $leading . "-\n" . $subtext;
			} else {
				$subtext = $leading . "- " . $subtext;
			}
			push (@subtext, $subtext);
		} 
		$text = join("\n", @subtext);

	} elsif ($type eq 'HASH') {
		my @subtext;
		foreach my $name (sort keys %$value) {
			my $subvalue = $value->{$name};
			my ($subtype, $subtext) = format_value($subvalue, $level+1);
			if ($subtype) {
				$subtext = $leading . "$name:\n" . $subtext;
			} else {
				$subtext = $leading . "$name: " . $subtext;
			}
			push (@subtext, $subtext);
		} 
		$text = join("\n", @subtext);

	} elsif (length($value) > 60) {
        $type = 'SCALAR';
		my @subtext = split(/(\S.{0,59}\S*)/, $value);
		@subtext = grep( /\S/, @subtext);
		@subtext = map("$leading> $_", @subtext);
		$text = join("\n", @subtext);
		
	} else {
		$text = $value;
	}

	return ($type, $text);
}

#----------------------------------------------------------------------
# Parse a block of lines at the same indentation level

sub parse_block {
	my ($lines) = @_;

	my @block;
	my ($first_indent, $first_type);

	while (@$lines) {
		my $line = shift(@$lines);
		my ($indent, $value) = parse_line($line);
		next unless defined $indent;

		if (! defined $first_indent) {
			$first_indent = $indent;
			$first_type = ref($value);
		}
		
		if ($indent == $first_indent) {
			my $type = ref($value);

			if ($type ne $first_type) {
				my $msg = trim_string($line);
				die("Missing indent at $msg\n");
			}

			if ($type eq 'ARRAY') {
				push(@block, @$value);
			} elsif ($type eq 'HASH') {
				push(@block, %$value);
			} else {
				push(@block, $value);
			}

		} elsif ($indent > $first_indent) {
			if ($first_type ne 'ARRAY' &&
			    $first_type ne 'HASH') {
				my $msg = trim_string($line);
				die("Indent under string at $msg\n");
			}

			if (length($block[-1])) {
				my $msg = trim_string($line);
				die("Duplicate value at $msg\n");
							
			}

			unshift(@$lines, $line);
			$block[-1] = parse_block($lines);

		} elsif ($indent < $first_indent) {
			unshift(@$lines, $line);				
			last;	
		}
	}

	my $block;
	if (! defined $first_type) {
		$block = {};
	} elsif ($first_type eq 'ARRAY') {
		$block = \@block;
	} elsif ($first_type eq 'HASH') {
		my %block = @block;
		$block = \%block;
	} else {
		$block = join(' ', @block);
	}
	
	return $block;
}

#----------------------------------------------------------------------
# Parse a single line to get its indentation and value

sub parse_line {
	my ($line) = @_;
    
    $line =~ s/\t/    /g;
	$line .= ' ';

	my ($indent, $value);
	if ($line !~ /^\s*#/ && $line =~ /\S/) {
		my $spaces;
		if ($line =~ /^(\s*)> (.*)/) {
			$spaces = $1;
			$value = trim_string($2);
		} elsif ($line =~ /^(\s*)- (.*)/) {
			$spaces = $1;
			$value = [trim_string($2)];
		} elsif ($line =~ /^(\s*)(\S+): (.*)/) {
			$spaces = $1;
			$value = {$2 => trim_string($3)};
		} else {
			my $msg = trim_string($line);
			die "Bad tag at $msg\n";
		}

		$indent = defined($spaces) ? length($spaces) : 0;
	} 
	
	return ($indent, $value);
}

#----------------------------------------------------------------------
# Remove leading and trailing space from string

sub trim_string {
	my ($str) = @_;
	return '' unless defined $str;
	
	$str =~ s/^\s+//;
	$str =~ s/\s+$//;
	return $str;
}

1;
__END__

=encoding utf-8

=head1 NAME

App::Followme::NestedText - Read a file or string using a subset of yaml
=head1 SYNOPSIS

	use App::Followme::NestedText
    my %config = nt_parse_file($filename);
    %config = nt_parse_string($str);
	nt_write_file($filename, %config)

=head1 DESCRIPTION

This module reads configuration data from either a file or string. The data
is a hash whose values are strings, arrays, or other hashes. Because of the
loose typing of Perl, numbers can be represted as strings. A hash is a list
of name value pairs separated by a colon and a space:

    name1: value1
    name2: value2
    name3: value3

In the above example all the values are short strings and fit on a line.
Longer values can be split across several lines by starting each line
sith a greater than sign and space indented beneath the name:

    name1: value1
    name2:
        > A longer value
        > split across lines
        > however many you need
    name3: value3

The lines are joined with spaces into a single string.

Array values are formatted one element per line with each line indented 
beneath the name starting with a dash and space

    name1: value1
	array_name: 
	    - subvalue1
        - subvalue2
        - subvalue3

Hash values are indented from the field containg them, each field in
the hash on a separate line.

    name1: value1
    hash_name:
        subname1: subvalue1
        subname2: subvalue2
        subname3: subvalue3

Hashes, arrays, and strings can be nested to any depth, but the top level
must be a hash. Values may contain any character except a newline. Quotes
are not needed around values. Leading and trailing spaces are trimmed
from values, interior spaces are unchanged. Values can be the empty 
string. Names can contain any non-whitespace character. The amount of 
indentation is arbitrary, but must  be consistent for all values in a 
string, array, or hash. The three special characters which indicate the
field type (:, -, and > ) must be followed by at least one space unless 
they are the last character on the line.

=head1 SUBROUTINES

The following subroutines can be use to read a configuration. Subroutine
names are exported when you use this module.

=over 4

=item my %config = nt_parse_file($filename);

Load a configuration from a file into a hash.

=item my %config = nt_parse_string($string);

Load a configuration from a string into a hash.

=item nt_write_file($filename, %config);

Write a configuration back to a file

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut
