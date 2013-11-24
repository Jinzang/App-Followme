package App::Followme::MostRecentFile;
use 5.008005;
use strict;
use warnings;

use lib '../..';

our $VERSION = "0.93";

use File::Spec::Functions qw(rel2abs);
use base qw(App::Followme::EveryFile);

#----------------------------------------------------------------------
# Create object that returns files in a directory tree

sub new {
    my ($pkg, $directory) = @_;
    
    my %configuration = $directory ? (base_directory => $directory) : ();
    my %self = ($pkg->parameters(), %configuration);
    my $self = bless(\%self, $pkg);
    $self->setup();
    
    return $self;
}

#----------------------------------------------------------------------
# Read the default parameter values

sub parameters {
    my ($pkg) = @_;
    
    my %parameters = (
                count => 0,
           );

    my %base_params = $pkg->SUPER::parameters();
    %parameters = (%base_params, %parameters);

    return %parameters;
}

#---------------------------------------------------------------------
# Return the next file

sub next {
    my ($self) = @_;
    
    return if $self->{count} ++;
    return $self->SUPER::next;
}

#----------------------------------------------------------------------
# Return 1 if filename passes test

sub match_file {
    my ($self, $path) = @_;
    return ! -d $path && $path =~ /\.$self->{web_extension}$/;
}

#----------------------------------------------------------------------
# Return 1 if folder passes test

sub match_folder {
    my ($self, $path) = @_;
    return;
}

1;
__END__