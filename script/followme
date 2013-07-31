#!/usr/bin/perl

use lib '../lib';

use IO::File;
use App::Followme qw(configure_followme followme);

my $dir = shift @ARGV;
read_configuration($dir);
followme($dir);

#----------------------------------------------------------------------
# Construct configuration file name

sub configuration_file {
    my ($dir) = @_;
    
    my @path = split(/\//, $0);
    my $basename = pop(@path);
    $basename =~ s/[^\.]*$/cfg/;
    
    @path = split($dir);
    push(@path, $basename);
    
    return join('/', @path);
}

#----------------------------------------------------------------------
# Load a module containing the named routine

sub load_module {
    my ($subroutine) = @_;
    
    my @path = split(/::/, $subroutine);
    pop(@path);
    
    if (@path) {
        my $pkg = join('::', @path);
        eval "require $pkg" or die "Subroutine not found: $subroutine\n";
    }
    
    return \&$subroutine;
}

#----------------------------------------------------------------------
# Read configuration file

sub read_configuration {
    my ($dir) = @_;
    $dir = '.' unless defined $dir;
    
    my $filename = configuration_file($dir);
    my $fd = IO::File->new($filename, 'r');
    return unless $fd;

    while (<$fd>) {
        my ($line, $comment) = split(/#/, $_, 2);
        $line =~ s/\s+$//;

        if (length $line) {
            die "Bad configuration: $line\n" unless $line =~ /=/;
            my ($name, $value) = split(/\s*=\s*/, $line, 2);
            $value = load_module($value) if $name eq 'page_converter';
            
            configure_followme($name, $value) if $value;
        }
    }

    close($fd);
    return;
}