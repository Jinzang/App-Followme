package App::Followme::MostRecentFile;
use 5.008005;
use strict;
use warnings;

use lib '../..';

our $VERSION = "0.93";

use base qw(App::Followme::EveryFile);

#----------------------------------------------------------------------
# Return most recently modified file in directory

sub run {
    my ($self, $directory) = @_;

    my ($visit_folder, $visit_file) = $self->visit($directory);

    $directory = &$visit_folder;
    my $newest_date = 0;
    my $newest_file;
    
    while (my $filename = &$visit_file) {
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