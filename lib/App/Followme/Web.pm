package App::Followme::Web;

use 5.008005;
use strict;
use warnings;
use integer;
use lib '../..';

use Carp;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(web_match_tags web_parse_sections web_only_tags web_only_text
                 web_substitute_sections web_substitute_tags);

our $VERSION = "1.16";

#----------------------------------------------------------------------
# Extract a list of parsed tags from a text

sub web_extract_tags {
    my ($text) = @_;

    my @tokens = web_split_at_tags($text);
    return web_only_tags(@tokens);
}

#----------------------------------------------------------------------
# Is the token an html tag?

sub web_is_tag {
    my ($token) = @_;
    return $token =~ /^<[^!]/ ? 1 : 0;
}

#----------------------------------------------------------------------
# Call a function after a set of tags is matched

sub web_match_tags {
    my ($pattern, $text, $matcher, $metadata, $global) = @_;

    my @tokens;
    my $in = 0;
    my $match_count = 0;
    my @matches = web_extract_tags($pattern);

    foreach my $token (web_split_at_tags($text)) {
        if (web_is_tag($token)) {
            my $tag = web_parse_tag($token);
            if (web_same_tag($matches[$in], $tag)) {
                $in += 1;
                if ($in >= @matches) {
                    push(@tokens, $token);
                    $matcher->($metadata, @tokens);
                    $match_count += 1;
                    @tokens = ();
                    $in = 0;

                    last unless $global;
                }
            }
        }
        push(@tokens, $token) if $in > 0;
    }

    return $match_count;
}

#----------------------------------------------------------------------
# Extract a list of parsed tags from a set of tokens

sub web_only_tags {
    my (@tokens) = @_;

    my @tags;
    foreach my $token (@tokens) {
        if (web_is_tag($token)) {
            push(@tags, web_parse_tag($token));
        }
    }

    return @tags;
}

#----------------------------------------------------------------------
# Parse a text string from a set of tokens

sub web_only_text {
    my (@tokens) = @_;

    my @text;
    foreach my $token (@tokens) {
        push(@text, $token) unless web_is_tag($token);
    }

    my $text = join(' ', @text);
    $text =~ s/\s+/ /g;
    $text =~ s/^\s+//;
    $text =~ s/\s+$//;

    return $text;
}

#----------------------------------------------------------------------
# Extract sections from file, store in hash

sub web_parse_sections {
    my ($text) = @_;

    my $name;
    my %section;

    # Extract sections from input

    my @tokens = split (/(<!--\s*(?:section|endsection)\s+.*?-->)/, $text);

    foreach my $token (@tokens) {
        if ($token =~ /^<!--\s*section\s+(\w+).*?-->/) {
            if (defined $name) {
                die "Nested sections in input: $token\n";
            }
            $name = $1;

        } elsif ($token =~ /^<!--\s*endsection\s+(\w+).*?-->/) {
            if ($name ne $1) {
                die "Nested sections in input: $token\n";
            }
            undef $name;

        } elsif (defined $name) {
            $section{$name} = $token;
        }
    }

    die "Unmatched section (<!-- section $name -->)\n" if $name;
    return \%section;
}

#----------------------------------------------------------------------
# Parse a web tag into attributes and their values

sub web_parse_tag {
    my ($tag) = @_;
    croak "Npt a tag: ($tag)" unless web_is_tag($tag);

    my @pattern;
    my $side = 0;
    my @pair = (undef, undef);

    while ($tag =~ /(=|"[^"]*"|[^<>="\s]+)/gs) {
        my $token = $1;

        if ($token eq '=') {
            $side = 1;
            undef $token;
        } elsif ($token =~ /^"/) {
            $token =~ s/"//g;
        }

        if (defined $token) {
            if (defined $pair[$side]) {
                if (defined $pair[0]) {
                    push(@pattern, @pair);
                    @pair = (undef, undef);
                    $side = 0;
                }
            }

            $token = lc($token) if $side == 0;
            $pair[$side] = $token;
        }
    }

    push(@pattern, @pair) if defined $pair[0];

    if (@pattern < 2 || defined $pattern[1]) {
        unshift(@pattern, undef, undef);
    }

    $tag = shift @pattern;
    shift @pattern;

    my %pattern = ('_', $tag, @pattern);
    return \%pattern;
}

#----------------------------------------------------------------------
# Test if two parsed tags have the same name and attributes.

sub web_same_tag {
    my ($match, $tag) = @_;

    croak "Match not parsed: $match" unless ref $match;
    croak "Tag not parsed: $tag" unless ref $tag;

    while (my ($name, $value) = each %$match) {
        return 0 unless exists $tag->{$name};
        return 0 if $value ne '*' && $tag->{$name} ne $value;
    }

    return 1;
}

#----------------------------------------------------------------------
# Return a list of tokens, split at tag boundaries

sub web_split_at_tags {
    my ($text) = @_;

    my @tokens = split(/(<!--.*?-->|<[^">]*(?:"[^"]*")*[^>]*>)/s, $text);
    @tokens = grep {length} @tokens;

    return @tokens;
}

#----------------------------------------------------------------------
# Substitue comment delimeted sections for same blacks in template

sub web_substitute_sections {
    my ($text, $section) = @_;

    my $name;
    my @output;

    my @tokens = split (/(<!--\s*(?:section|endsection)\s+.*?-->)/, $text);

    foreach my $token (@tokens) {
        if ($token =~ /^<!--\s*section\s+(\w+).*?-->/) {
            if (defined $name) {
                die "Nested sections in template: $name\n";
            }

            $name = $1;
            push(@output, $token);

        } elsif ($token =~ /^\s*<!--\s*endsection\s+(\w+).*?-->/) {
            if ($name ne $1) {
                die "Nested sections in template: $name\n";
            }

            undef $name;
            push(@output, $token);

        } elsif (defined $name) {
            $section->{$name} ||= $token;
            push(@output, $section->{$name});

        } else {
            push(@output, $token);
        }
    }

    return join('', @output);
}

#----------------------------------------------------------------------
# Call a function after a set of tags is matched to generate substitute

sub web_substitute_tags {
    my ($pattern, $text, $substituter, $output, $global) = @_;

    my @tokens;
    my @all_tokens;

    my $in = 0;
    my $match_count = $global ? 99999 : 1;
    my @matches = web_extract_tags($pattern);

    foreach my $token (web_split_at_tags($text)) {
        if (web_is_tag($token)) {
            my $tag = web_parse_tag($token);
            if (web_same_tag($matches[$in], $tag)) {
                $in += 1 if $match_count;
                if ($in >= @matches) {
                    push(@tokens, $token);
                    $token = $substituter->($output, @tokens);
                    $match_count -= 1;
                    @tokens = ();
                    $in = 0;
                }
            }
        }

        if ($in > 0) {
            push(@tokens, $token);
        } else {
            push(@all_tokens, $token);
        }
    }

    push(@all_tokens, @tokens) if @tokens;
    return join('', @all_tokens);
}

1;
