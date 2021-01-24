package App::Followme::BaseData;

use 5.008005;
use strict;
use warnings;
use integer;
use lib '../..';

use base qw(App::Followme::ConfiguredObject);
use App::Followme::FIO;

#----------------------------------------------------------------------
# Default values of parameters

sub parameters {
    my ($pkg) = @_;

    ## TODO: sort_field='mdate', sort_reverse=1
    return (
            sort_field => '',
            target_prefix => 'target',
            );
}

#----------------------------------------------------------------------
# Build a new variable value given its name and context

sub build {
    my ($self, $variable_name, $item, $loop) = @_;

    # Extract the sigil from the variable name, if present
    my ($sigil, $name) = $self->split_name($variable_name);

    my %cache = ();
    if ($sigil eq '$') {
        if (defined $item &&
           (! $self->{cache}{item} || $self->{cache}{item} ne $item)) {
            # Clear cache when argument to build changes
            %cache = (item => $item);
        } else {
            %cache = %{$self->{cache}};
        }
    }

    # Build the value associated with a name if it is not in the cache
    unless (exists $cache{$name}) {
        my %data = $self->fetch_data($name, $item, $loop);

        my $sorted_order = 0;
        my $sorted_data = $self->sort(\%data);
        $sorted_data = $self->format($sorted_order, $sorted_data);

        %cache = (%cache, %$sorted_data);
    }

    # Check the value for agreement with the sigil and return reference
    my $ref_value = $self->ref_value($cache{$name}, $sigil, $name);
    $self->{cache} = \%cache if $sigil eq '$';
    return $ref_value;
}

#----------------------------------------------------------------------
# Coerce the data to a hash

sub coerce_data {
    my ($self, $name, @data) = @_;

    my %data;
    if (@data == 0) {
        %data = ();

    } elsif (@data == 1) {
        %data = ($name => $data[0]);

    } elsif (@data % 2 == 0) {
        %data = @data;

    } else {
        my $pkg = ref $self;
        die "$name does not return a hash\n";
    }

    return %data;
}

#----------------------------------------------------------------------
# Fetch the data for building a variable's value

sub fetch_data {
    my ($self, $name, $item, $loop) = @_;

    my %data = $self->gather_data('get', $name, $item, $loop);
    return %data;
}

#----------------------------------------------------------------------
# Choose the file comparison routine that matches the configuration

sub file_comparer {
    my ($self, $sort_reverse) = @_;

    my $comparer;
    if ($sort_reverse) {
        $comparer = sub ($$) {$_[1]->[0] cmp $_[0]->[0]};
    } else {
        $comparer = sub ($$) {$_[0]->[0] cmp $_[1]->[0]};
    }

    return $comparer;
}

#----------------------------------------------------------------------
# Find the index column for the data, which guides the sort column

sub find_index_column {
    my ($self, $data) = @_;

    my $index_column;
    my @keys = keys %$data;

    if (@keys == 1 ) {
        my $key = $keys[0];
        if (ref $data->{$key} eq 'ARRAY') {
            $index_column = $data->{$key};
        }
    }

    return $index_column;
}

#----------------------------------------------------------------------
# Find the target, return the target plus an offset

sub find_target {
    my ($self, $offset, $item, $loop) = @_;
    die "Can't use \$target_* outside of for\n"  unless $loop;

    my $match = -999;
    foreach my $i (0 .. @$loop) {
        if ($loop->[$i] eq $item) {
            $match = $i;
            last;
        }
    }

    my $index = $match + $offset + 1;
    $index = 0 if $index < 1 || $index > @$loop;
    return $index ? $self->{target_prefix} . $index : '';
}

#----------------------------------------------------------------------
# Apply an optional format to the data

sub format {
    my ($self, $sorted_order, $sorted_data) = @_;

    foreach my $name (keys %$sorted_data) {
        next unless $sorted_data->{$name};

        my $formatter = join('_', 'format', $name);
        if ($self->can($formatter)) {
            if (ref $sorted_data->{$name} eq 'ARRAY') {
                for my $value (@{$sorted_data->{$name}}) {
                    $value = $self->$formatter($sorted_order,
                                               $value);
                }

            } elsif (ref $sorted_data->{$name} eq 'HASH') {
                die("Illegal data format for build: $name");

            } else {
                $sorted_data->{$name} =
                    $self->$formatter($sorted_order, $sorted_data->{$name});
            }
        }
    }

    return $sorted_data;
}

#----------------------------------------------------------------------
# Don't format anything

sub format_nothing {
    my ($self, $sorted_order, $value) = @_;
    return $value;
}

#----------------------------------------------------------------------
# Format the values to sort by so they are in sort order

sub format_sort_column {
    my ($self, $sort_field, $index_column, $data) = @_;
    
    my $formatter = "format_$sort_field";
    $formatter = "format_nothing" unless $self->can($formatter);

    my @sort_column;
    my $sorted_order = 1;
    if (exists $data->{$sort_field}) {
        for my $value (@{$data->{$sort_field}}) {
            push(@sort_column, $self->$formatter($sorted_order, $value));
        }

    } else {
        my $getter = "get_$sort_field";
        return unless $self->can($getter);

        for my $item (@$index_column) {
            my $value = $self->$getter($item, $index_column);
            push(@sort_column, $self->$formatter($sorted_order, $value));
        }
    }

    return \@sort_column;
}

#----------------------------------------------------------------------
# Gather the data for building a variable's value

sub gather_data {
    my ($self, $method, $name, $item, $loop) = @_;

    my @data;
    $method = join('_', $method, $name);

    if ($self->can($method)) {
        @data = $self->$method($item, $loop);

    } else {
        @data = ();
    }

    my %data = $self->coerce_data($name, @data);
    return %data;
}

#----------------------------------------------------------------------
# Get the count of the item in the list

sub get_count {
    my ($self, $item, $loop) = @_;
    die "Can't use \$count outside of for\n" unless $loop;

    foreach my $i (0 .. @$loop) {
        if ($loop->[$i] eq $item) {
            my $count = $i + 1;
            return $count;
        }
    }

    return;
}

#----------------------------------------------------------------------
# Is this the first item in the list?

sub get_is_first {
    my ($self, $item, $loop) = @_;

    die "Can't use \$is_first outside of for\n" unless $loop;
    return $loop->[0] eq $item ? 1 : 0;
}

#----------------------------------------------------------------------
# Is this the last item in the list?

sub get_is_last {
    my ($self, $item, $loop) = @_;

    die "Can't use \$is_last outside of for\n"  unless $loop;
    return $loop->[-1] eq $item ? 1 : 0;
}

#----------------------------------------------------------------------
# Return the current list of loop items

sub get_loop {
    my ($self, $item, $loop) = @_;

    die "Can't use \@loop outside of for\n"  unless $loop;
    return $loop;
}

#----------------------------------------------------------------------
# Return the name of the current item in a loop

sub get_name {
    my ($self, $item) = @_;
    return $item;
}

#----------------------------------------------------------------------
# Get the current target

sub get_target {
    my ($self, $item, $loop) = @_;
    return $self->find_target(0, $item, $loop);
}

#----------------------------------------------------------------------
# Get the next target

sub get_target_next {
    my ($self, $item, $loop) = @_;
    return $self->find_target(1, $item, $loop);
}

#----------------------------------------------------------------------
# Get the previous target

sub get_target_previous {
    my ($self, $item, $loop) = @_;
    return $self->find_target(-1, $item, $loop);
}

#----------------------------------------------------------------------
# Augment the array to be sorted with the index of its position

sub make_sort_index {
    my ($self, $sort_column) = @_;

    my $i = 0;
    my @augmented_sort;
    for my $value (@$sort_column) {
        push(@augmented_sort, [$value, $i++]);
    }

    return @augmented_sort;
}

#----------------------------------------------------------------------
# Use the array of indexes to move each hash array to its sorted position

sub move_sort_index {
    my ($self, $data, @augmented_sort) =  @_;

    for my $field (keys %$data) {
        my $sorted_values = [];
        my $values = $data->{$field};

        for my $index (@augmented_sort) {
            push(@$sorted_values, $values->[$index->[1]]);
        } 

        $data->{$field} = $sorted_values;
    }


    return $data;
}

#----------------------------------------------------------------------
# Get a reference value and check it for agreement with the sigil

sub ref_value {
    my ($self, $value, $sigil, $name) = @_;

    my ($check, $ref_value);
    if ($sigil eq '$'){
        $value = '' unless defined $value;
        if (ref $value ne 'SCALAR') {
			# Convert data structures for inclusion in template
			$value = fio_flatten($value);
			$ref_value = \$value;
		} else {
			$ref_value = $value;
		}
        $check = ref $ref_value eq 'SCALAR';

    } elsif ($sigil eq '@') {
        $ref_value = $value;
        $check = ref $ref_value eq 'ARRAY';

    } elsif ($sigil eq '' && defined $value) {
        $ref_value = ref $value ? $value : \$value;
        $check = 1;
    }

    die "Unknown variable: $sigil$name\n" unless $check;
    return $ref_value;
}

#----------------------------------------------------------------------
# Set up the cache for data

sub setup {
    my ($self, %configuration) = @_;

    $self->{cache} = {};
}

#----------------------------------------------------------------------
# Sort the data if it is in an array

sub sort {
    my ($self, $data) = @_;

    my $sorted_data;
    my $index_column = $self->find_index_column($data);

    if ($index_column) {
        my @fields = ($self->{sort_field}, 'mdate', 'date', 'name');

        for my $sort_field (@fields) {
            next unless $sort_field;

            if (my $sort_column = $self->format_sort_column($sort_field, 
                                                            $index_column, 
                                                            $data)) {
                my $sort_reverse = ($sort_field =~ /date$/) ? 1 : 0;

                $sorted_data = $self->move_sort_index($data,
                                $self->sort_by_index($sort_reverse,
                                $self->make_sort_index($sort_column)));
                last;
            }
        }
    }

    $sorted_data ||= $data;
    return $sorted_data;
}

#----------------------------------------------------------------------
# Sort array bound to indexes of the array

sub sort_by_index {
    my ($self, $sort_reverse, @augmented_data) = @_;

    my $comparer = $self->file_comparer($sort_reverse);
    return sort $comparer @augmented_data;
}

#----------------------------------------------------------------------
# Split the sigil off from the variable name from a template

sub split_name {
    my ($self, $variable_name) = @_;

    my $name = $variable_name;
    $name =~ s/^([\$\@])//;
    my $sigil = $1 || '';

    return ($sigil, $name);
}

1;

=pod

=encoding utf-8

=head1 NAME

App::Followme::BaseData

=head1 SYNOPSIS

    use App::Followme::BaseData;
    my $meta = App::Followme::BaseData->new();
    my %data = $meta->build($name, $filename);

=head1 DESCRIPTION

This module is the base class for all metadata classes and provides the build
method used to interface metadata classes with the App::Followme::Template
class.

Followme uses templates to construct web pages. These templates contain
variables whose values are computed by calling the build method of the metadata
object, which is passed as an argument to the template function. The build
method returns either a reference to a scalar or list. The names correspond to
the variable names in the template. This class contains the build method, which
couples the variable name to the metadata object method that computes the value
of the variable.

=head1 METHODS

There is only one public method, build.

=over 4

=item my %data = $meta->build($name, $filename);

Build a variable's value. The first argument is the name of the variable
to be built. The second argument is the filename the variable is computed for.
If the variable returned is a list of files, this variable should be left
undefined.

=back

=head1 VARIABLES

The base metadata class can evaluate the following variables. When passing
a name to the build method, the sigil should not be used. All these variables
can only be used inside a for block.

=over 4

=item @loop

A list with all the loop items from the immediately enclosing for block.

=item $count

The count of the current item in the for block.The count starts at one.

=item $is_first

One if this is the first item in the for block, zero otherwise.

=item $is_last

One if this is the last item in the for block, zero otherwise

=item $name

The name of the current item in the for block.

=item $target

A string that can be used as a target for the location of the current item
in the page.

=item $target_next

A string that can be used as a target for the location of the next item
in the page. Empty if there is no next item.

=item $target_previous

A string that can be used as a target for the location of the previous item
in the page. Empty if there is no previous item.

=back

=head1 CONFIGURATION

There is one parameter:

=over 4

=item labels

A comma separated list of strings containing a list of labels to apply
to the values in a loop. The default value is "previous,next" and is
meant to be used with @sequence.

=item sort_field

The metatdata field to sort list valued variables. The default value is the
empty string, which means files are sorted on their filenames.

=item target_prefix

The prefix used to build the target names. The default value is 'target'.

=back

=head1 LICENSE
Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut
