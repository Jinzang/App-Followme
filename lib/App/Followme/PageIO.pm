package App::Followme::PageIO;
use 5.008005;
use strict;
use warnings;

use IO::File;
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(read_page write_page);

our $VERSION = "0.90";

#----------------------------------------------------------------------
# Read a file into a string

sub read_page {
    my ($filename) = @_;

    local $/;
    my $fd = IO::File->new($filename, 'r');
    return unless $fd;
    
    my $page = <$fd>;
    close($fd);
    
    return $page;
}

#----------------------------------------------------------------------
# Write the page back to the file

sub write_page {
    my ($filename, $page) = @_;

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

App::Followme::FormPages - Simple static web site maintenance

=head1 SYNOPSIS

    use App::Followme::PageIO qw(read_page write_page);
    my $index_page = read_page('index.html');
    write_page('index.html', $page);
    
=head1 DESCRIPTION

App::Followme::IOPage handles file reading and writing for followm.
An the entire file is read to or written from a string, there is no line at
a time IO. This is because files are typically small and the parsing done is
not line oriented. The two functions are read_page and write_page.

=over 4

=item $str = read_page($filename);

Read a fie into a string

=item write_page($filename, $str);

Write a file from a string

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut

