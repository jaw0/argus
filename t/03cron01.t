# -*- perl -*-
# Function: test of Cron spec

$opt_f = 1;
require "t/libs.pl";

print "1..1\n";

$x = {};
$^T = 1070513423;
Cron::parse_spec( $x, "50 * * * *" );
$t = Cron::next_spec_time( $x );

t( $t > $^T );


exit 0;
################################################################
