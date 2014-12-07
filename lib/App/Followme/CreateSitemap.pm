package App::Followme::CreateSitemap;

use 5.008005;
use strict;
use warnings;

use lib '../..';

use File::Spec::Functions qw(catfile);
use base qw(App::Followme::Module);

our $VERSION = "1.11";

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($self) = @_;
    
    return (
            site_url => '',
            sitemap => 'sitemap.txt',
           );
}

#----------------------------------------------------------------------
# Write a list of urls in a directory tree

sub run {
    my ($self, $directory) = @_;

    my @urls = $self->list_urls($directory);
    my $page = join("\n", @urls) . "\n";
    
    my $filename = catfile($directory, $self->{sitemap});
    $self->write_page($filename, $page);
   
    return;
}

#----------------------------------------------------------------------
# Return a list of the urls of all web pages in a directory

sub list_urls {
    my ($self, $directory) = @_;

    my @urls;
    my $data = {};
    my ($filenames, $directories) =  $self->visit($directory);

    foreach my $filename (@$filenames) {
        next unless $self->match_file($filename);

        $data = $self->build_url($data, $directory, $filename);
        my $url = $self->{site_url} . $data->{absolute_url};
        push(@urls, $url);
    }

    foreach my $subdirectory (@$directories) {
        next unless $self->search_directory($directory);
        push(@urls, $self->list_urls($subdirectory));
    }
   
    return @urls;
}

#----------------------------------------------------------------------
# Clean up parameters passed to this object

sub setup {
    my ($self, $configuration) = @_;
    
    # Remove any trailing slash
    $self->{site_url} =~ s/\/$//;
    return;
}

1;
__END__

=encoding utf-8

=head1 NAME

App::Followme::CreateSitemap - Create a Google sitemap

=head1 SYNOPSIS

    use App::Followme::Sitemap;
    my $map = App::Followme::Sitemap->new();
    $map->run($directory);

=head1 DESCRIPTION

This module creates a sitemap file, which is a text file containing the url of
every page on the site, one per line. It is also intended as a simple example of
how to write a module that can be run by followme.

=head1 CONFIGURATION

The following field in the configuration file are used:

=over 4

=item sitemap

The name of the sitemap file. It is written to the directory this module is
invoked from. Typically this is the top folder of a site. The default value is
sitemap.txt.

=item site_url

The url of the website, e.g. http://www.example.com. 

=back

=head1 LICENSE

Copyright (C) Bernie Simon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Bernie Simon E<lt>bernie.simon@gmail.comE<gt>

=cut
