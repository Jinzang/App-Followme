package App::Followme::EveryFile;
use 5.008005;
use strict;
use warnings;

use lib '../..';

use Cwd;
use IO::Dir;
use File::Spec::Functions qw(rel2abs catfile splitdir no_upwards);

our $VERSION = "0.93";

#----------------------------------------------------------------------
# Create object that returns files in a directory tree

sub new {
    my ($pkg, $configuration) = @_;
    $configuration = {} unless defined $configuration;
    
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
            web_extension => 'html',
           );
}

#----------------------------------------------------------------------
# Get the list of excluded files

sub get_excluded_files {
    my ($self) = @_;
    return '';
}

#----------------------------------------------------------------------
# Get the list of included files

sub get_included_files {
    my ($self) = @_;
    return "*.$self->{web_extension}";
}

#----------------------------------------------------------------------
# Map filename globbing metacharacters onto regexp metacharacters

sub glob_patterns {
    my ($self, $patterns) = @_;

    my @globbed_patterns;
    my @patterns = split(/\s*,\s*/, $patterns);

    foreach my $pattern (@patterns) {
        if ($pattern eq '*') {
            push(@globbed_patterns,  '') if $pattern eq '*';
            
        } else {
            my $start;
            if ($pattern =~ s/^\*//) {
                $start = '';
            } else {
                $start = '^';
            }
        
            my $finish;
            if ($pattern =~ s/\*$//) {
                $finish = '';
            } else {
                $finish = '$';
            }
        
            $pattern =~ s/\./\\./g;
            $pattern =~ s/\*/\.\*/g;
            $pattern =~ s/\?/\.\?/g;
        
            push(@globbed_patterns, $start . $pattern . $finish);
        }
    }
    
    return \@globbed_patterns;
}

#----------------------------------------------------------------------
# Return true if this is an included file

sub include_file {
    my ($self, $filename) = @_;
    
    my $dir;
    ($dir, $filename) = $self->split_filename($filename);
    
    foreach my $pattern (@{$self->{exclude_files}}) {
        return if $filename =~ /$pattern/;
    }
    
    foreach my $pattern (@{$self->{include_files}}) {
        return 1 if $filename =~ /$pattern/;
    }

    return;
}

#----------------------------------------------------------------------
# Return 1 if filename passes test

sub match_file {
    my ($self, $path) = @_;
    return $self->include_file($path) && ! -d $path;
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

    for (;;) {
        my $file = shift(@{$self->{pending_files}});
        return $file if defined $file;
    
        return unless @{$self->{pending_folders}};
        my $dir = shift(@{$self->{pending_folders}});

        my $dd = IO::Dir->new($dir);
        die "Couldn't open $dir: $!\n" unless $dd;

        # Find matching files and directories
        while (defined (my $file = $dd->read())) {
            next unless no_upwards($file);
            my $path = catfile($dir, $file);
            
            push(@{$self->{pending_folders}}, $path)
                if -d $path && $self->match_folder($path);

            push(@{$self->{pending_files}}, $path)
                if $self->match_file($path);
        }

        $dd->close;

        $self->sort_files();
        @{$self->{pending_folders}} = sort(@{$self->{pending_folders}});
    }
}

#----------------------------------------------------------------------
# Set up non-configured fields in the object

sub setup {
    my ($self) = @_;
    
    $self->visit($self->{base_directory});
    $self->{include_files} = $self->glob_patterns($self->get_included_files());
    $self->{exclude_files} = $self->glob_patterns($self->get_excluded_files());
    
    return;
}

#----------------------------------------------------------------------
# Sort a list of files so the most recently modified file is first

sub sort_files {
    my ($self) = @_;

    my @augmented_files;
    foreach my $filename (@{$self->{pending_files}}) {
        my @stats = stat($filename);
        push(@augmented_files, [$filename, $stats[9]]);
    }

    @augmented_files = sort {$b->[1] <=> $a->[1] ||
                             $b->[0] cmp $a->[0]   } @augmented_files;
    
    @{$self->{pending_files}} = map {$_->[0]} @augmented_files;
    return;
}

#----------------------------------------------------------------------
# Split filename from directory

sub split_filename {
    my ($self, $filename) = @_;
    
    $filename = rel2abs($filename);
    my @path = splitdir($filename);
    my $file = pop(@path);
    
    my @new_path;
    foreach my $dir (@path) {
        if (no_upwards($dir)) {
            push(@new_path, $dir);
        } else {
            pop(@new_path);
        }
    }
    
    my $new_dir = catfile(@new_path);
    return ($new_dir, $file);
}

#----------------------------------------------------------------------
# Set the direcory to visit

sub visit {
    my ($self, $directory) = @_;
    
    $self->{pending_files} = [];
    $self->{pending_folders} =[rel2abs($directory)];
    
    return;   
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
