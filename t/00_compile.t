use strict;

use FindBin qw($Bin);
use lib "$Bin/../lib";
use Test::More;

use_ok $_ for qw(
    App::Followme
);

done_testing;

