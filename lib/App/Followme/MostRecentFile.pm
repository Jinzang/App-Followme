package App::Followme::MostRecentFile;
use 5.008005;
use strict;
use warnings;

use lib '../..';

our $VERSION = "1.00";

use base qw(App::Followme::EveryFile);

#----------------------------------------------------------------------
# Return most recently modified file in directory

sub run {
    my ($self, $directory) = @_;

    my ($filenames, $directories) = $self->visit($directory);

    my $newest_file;
    my $newest_date = 0;    
    foreach my $filename (@$filenames) {
        my @stats = stat($filename);  
        my $file_date = $stats[9];
    
        if ($file_date > $newest_date) {
            $newest_date = $file_date;
            $newest_file = $filename;
        }
    }

    return $newest_file;    
}

1;
__END__