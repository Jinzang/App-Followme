package App::Followme::MostRecentFile;
use 5.008005;
use strict;
use warnings;

use lib '../..';

our $VERSION = "0.93";

use File::Spec::Functions qw(rel2abs);
use base qw(App::Followme::EveryFile);

#----------------------------------------------------------------------
# Return most recent file

sub finish_folder {
    my ($self, $directory) = @_;
    
    $self->{done} = exists $self->{newest_file}
                    ? $self->{newest_file}
                    : undef;
    return;
}

#----------------------------------------------------------------------
# Update most recent file

sub handle_file {
    my ($self, $directory, $filename) = @_;
    
    my @stats = stat($filename);  
    my $file_date = $stats[9];

    if ($file_date > $self->{newest_date}) {
        $self->{newest_date} = $file_date;
        $self->{newest_file} = $filename;
    }

    return;
}

#----------------------------------------------------------------------
# Initialize search for most recent file

sub start_folder {
    my ($self, $directory) = @_;

    $self->{newest_date} = 0;
    return;
}

1;
__END__