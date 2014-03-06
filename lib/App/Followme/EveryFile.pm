package App::Followme::EveryFile;
use 5.008005;
use strict;
use warnings;

use lib '../..';

use Cwd;
use IO::Dir;
use File::Spec::Functions qw(rel2abs catfile splitdir no_upwards);

our $VERSION = "1.02";

#----------------------------------------------------------------------
# Create object that returns files in a directory tree

sub new {
    my ($pkg, $configuration) = @_;

    my %self = $pkg->update_parameters($configuration);
    my $self = bless(\%self, $pkg);
    
    $self->{included_files} = $self->glob_patterns($self->get_included_files());
    $self->{excluded_files} = $self->glob_patterns($self->get_excluded_files());
    $self = $self->setup($configuration);
    
    return $self;
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
# Return all the files in a subtree (example)

sub run {
    my ($self, $directory) = @_;

    my ($filenames, $directories) = $self->visit($directory);
    my @files = @$filenames;

    while (my $directory = @$directories) {
        push(@files, $self->run($directory));
    }
    
    return @files;
}

#----------------------------------------------------------------------
# Get the list of excluded files

sub get_excluded_directories {
    my ($self) = @_;
    return [];
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
            push(@globbed_patterns,  '.') if $pattern eq '*';
            
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

sub match_file {
    my ($self, $filename) = @_;
    
    my $dir;
    ($dir, $filename) = $self->split_filename($filename);
    
    foreach my $pattern (@{$self->{excluded_files}}) {
        return if $filename =~ /$pattern/;
    }
    
    foreach my $pattern (@{$self->{included_files}}) {
        return 1 if $filename =~ /$pattern/;
    }

    return;
}

#----------------------------------------------------------------------
# Read a file into a string

sub read_page {
    my ($self, $filename) = @_;
    return unless defined $filename;
    
    local $/;
    my $fd = IO::File->new($filename, 'r');
    return unless $fd;
    
    my $page = <$fd>;
    close($fd);
    
    return $page;
}

#----------------------------------------------------------------------
# Cehck if two filenames are the same in an os independent way

sub same_file {
    my ($self, $filename1, $filename2) = @_;
    
    my @path1 = splitdir(rel2abs($filename1));
    my @path2 = splitdir(rel2abs($filename2));
    return unless @path1 == @path2;

    while(@path1) {
        return unless shift(@path1) eq shift(@path2);
    }
    
    return 1;
}

#----------------------------------------------------------------------
# Check if directory should be searched

sub search_directory {
    my ($self, $directory) = @_;
    
    my $excluded_dirs = $self->get_excluded_directories();
    
    foreach my $excluded (@$excluded_dirs) {
        return if $self->same_file($directory, $excluded);
    }
    
    return 1;
}

#----------------------------------------------------------------------
# Set up object fields (stub)

sub setup {
    my ($self, $configuration) = @_;
    return $self;
}

#----------------------------------------------------------------------
# Sort pending filenames

sub sort_files {
    my ($self, $files) = @_;

    my @files = sort @$files;
    return \@files;
}

#----------------------------------------------------------------------
# Split filename from directory

sub split_filename {
    my ($self, $filename) = @_;
    
    $filename = rel2abs($filename);
    my @path = splitdir($filename);
    my $file = pop(@path);
        
    my $dir = catfile(@path);
    return ($dir, $file);
}

#----------------------------------------------------------------------
# Update a module's parameters

sub update_parameters {
    my ($pkg, $configuration) = @_;
    $configuration = {} unless defined $configuration;
        
    my %parameters = $pkg->parameters();
    foreach my $field (keys %parameters) {
        $parameters{$field} = $configuration->{$field}
            if exists $configuration->{$field};
    }
    
    return %parameters;
}

#----------------------------------------------------------------------
# Return two closures that will visit a directory tree

sub visit {
    my ($self, $directory) = @_;

    my @filenames;
    my @directories;
    my $dd = IO::Dir->new($directory);
    die "Couldn't open $directory: $!\n" unless $dd;

    # Find matching files and directories
    while (defined (my $file = $dd->read())) {
        next unless no_upwards($file);
        my $path = catfile($directory, $file);
    
        if (-d $path) {
            push(@directories, $path) if $self->search_directory($path);
        } else {
            push(@filenames, $path) if $self->match_file($path);
        }
    }

    $dd->close;
    
    my $filenames = $self->sort_files(\@filenames);
    my $directories = $self->sort_files(\@directories);
    
    return ($filenames, $directories);   
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

App::Followme::EveryFile - Base class for App::Followme classes

=head1 SYNOPSIS

    use App::Followme::EveryFile;
    my $ef = App::Followme::EveryFiles->new();
    my ($filenames, $directories) = $ef->visit($top_directory);
    foreach my $filename (@$filenames) {
        my $page = $ef->read_file($filename);
        # other stuff
        $ef->write_file($filename, $page);
    }

=head1 DESCRIPTION

This class contains methods that do the file handling for App::Followme.

=over 4

=item ($filenames, $directories) = $self->visit($top_directory);

Return a list of filenames and directories in a directory, The filenames are
filtered by the two methods get_included_files and get_excluded_files. By
default, it returns all files with the web extension.

=item $str = $self->read_page($filename);

Read a fie into a string. An the entire file is read from a string, there is no
line at a time IO. This is because files are typically small and the parsing
done is not line oriented. 

=item $self->write_page($filename, $str);

Write a file from a string. An the entire file is read to or written from a
string, there is no line at a time IO. This is because files are typically small
and the parsing done is not line oriented. 

=back

=head1 CONFIGURATION

The following fields in the configuration file are used in this class and every
class based on it:

=over 4

=item base_directory

The directory the class is invoked from. This controls which files are returned. The
default value is the current directory.

=item web_extension

The extension used by web pages. This controls which files are returned. The
default value is 'html'.

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut
