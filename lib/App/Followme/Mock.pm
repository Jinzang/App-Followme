package App::Followme::Mock;

use 5.008005;
use strict;
use warnings;

use Cwd;
use IO::File;
our $VERSION = "0.93";

#----------------------------------------------------------------------
# Create a new object to update a website

sub new {
    my ($pkg, $configuration) = @_;
    $configuration = {} unless defined $configuration;
    
    my %self = %$configuration; 
    return bless(\%self, $pkg);
}

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($pkg) = @_;
    
    return (
            user => '',
            mock_file => 'mock.txt',
            );
}

#----------------------------------------------------------------------
# Perform all updates on the directory

sub run {
    my ($self) = @_;

    my $dir = getcwd();
    my $fd = IO::File->new($self->{mock_file}, 'w');
    print $fd "$self->{user} is here: $dir\n";
    close($fd);
    return 1;
}

1;
__END__

=encoding utf-8

=head1 NAME

App::Followme::Mock - Mock object for unit tests

=head1 SYNOPSIS

    use App::Followme::Mock;
    my $mock = App::Followme::Mock->new();
    $mock->run();

=head1 DESCRIPTION

This is a minimal objects intended for unit tests and not for production use.

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut
