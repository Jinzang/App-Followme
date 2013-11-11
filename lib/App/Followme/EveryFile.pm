package App::Followme::EveryFile;
use 5.008005;
use strict;
use warnings;

use lib '../..';

use Cwd;
use IO::Dir;
use File::Spec::Functions qw(rel2abs catfile no_upwards);

our $VERSION = "0.93";

#----------------------------------------------------------------------
#Create object that returns files in a directory tree

sub new {
    my ($pkg, $configuration) = @_;

    if (defined $configuration ) {
        if (! ref $configuration) {
            $configuration = {base_directory => $configuration};
        }

    } else {
        $configuration = {};
    }
    
    my %self = ($pkg->parameters(), %$configuration);
    my $self = bless(\%self, $pkg);
    $self->setup();
    
    return $self;
}

#----------------------------------------------------------------------
# Print a list of files

sub run {
    my ($self) = @_;

    my $ref = ref $self;
    while(defined (my $filename = $self->next)) {
        print "$ref\t$filename\n";
    }
    
    return;
}

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($pkg) = @_;
    
    return (
            base_directory => getcwd(),
           );
}

#----------------------------------------------------------------------
# Return 1 if filename passes test

sub match_file {
    my ($self, $path) = @_;
    return ! -d $path;
}

#----------------------------------------------------------------------
# Return 1 if folder passes test

sub match_folder {
    my ($self, $path) = @_;
    return 1;
}

#----------------------------------------------------------------------
# Return the next file

sub next {
    my ($self) = @_;
    return $self->visit;
}

#----------------------------------------------------------------------
# Set up non-configured fields in the object

sub setup {
    my ($self) = @_;
    
    $self->{pending_files} = [];
    $self->{pending_folders} =[$self->{base_directory}];
    
    return;
}

#----------------------------------------------------------------------
# Sort a list of files so the most recently modified file is first

sub sort_files {
    my ($self) = @_;

    my @augmented_files;
    foreach my $filename (@{$self->{pending_files}}) {
        my @stats = stat($filename);
        push(@augmented_files, [$stats[9], $filename]);
    }

    @augmented_files = sort {$b->[0] <=> $a->[0] ||
                             $b->[1] cmp $a->[1]   } @augmented_files;
    
    @{$self->{pending_files}} = map {$_->[1]} @augmented_files;
    return;
}

#----------------------------------------------------------------------
# Return a filename from a directory

sub visit {
    my ($self) = @_;

    for (;;) {
        my $file = shift(@{$self->{pending_files}});
        return $file if defined $file;
    
        return unless @{$self->{pending_folders}};
        my $dir = shift(@{$self->{pending_folders}});

        my $dd = $dir ? IO::Dir->new($dir) : IO::Dir->new(getcwd());
        die "Couldn't open $dir: $!\n" unless $dd;

        # Find matching files and directories
        while (defined (my $file = $dd->read())) {
            next unless no_upwards($file);
            my $path = catfile($dir, $file);
            
            push(@{$self->{pending_folders}}, $path)
                if -d $path && $self->match_folder($path);;

            push(@{$self->{pending_files}}, $path)
                if $self->match_file($path);
        }

        $dd->close;

        $self->sort_files();
        @{$self->{pending_folders}} = sort(@{$self->{pending_folders}});
    }
}

1;
__END__

=encoding utf-8

=head1 NAME

App::Followme::EveryFile - Base class for App::Followme classes

=head1 SYNOPSIS

    use App::Followme::EveryFile;
    my @files;
    my $dd = App::Followme::EveryFiles->new($directory);
    while (defined (my $file = $ef->next)) {
        push(@files, $file)
    }

=head1 DESCRIPTION

This class has methods for looping all the files in a directory. The files in
a directory are returned in date order, with the most recently modified file
returned first. 

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut
