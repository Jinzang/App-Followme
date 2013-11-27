package App::Followme::TopDirectory;
use 5.008005;
use strict;
use warnings;

use Carp;
our $VERSION = "0.93";
our $top_directory;

#----------------------------------------------------------------------
# Create a new object to update a website

sub name {
    my ($pkg, $dir) = @_;

    if (defined $dir) {
        croak "Can't redefine top directory" if defined $top_directory;
        $top_directory = $dir;
    }
    
    return $top_directory;
}

1;