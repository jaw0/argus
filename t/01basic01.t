# -*- perl -*-
# Function: test basic transition

#$opt_f = 1;

print "1..4\n";
require "t/libs.pl";

$top = Conf::testconfig( \*DATA );

# find object
$o = $MonEl::byname{'Top:G1:Ping_localhost'};
die unless $o;

# transition ok?
$o->Service::start();
$o->isdown( 'test' );			# ping -> down
t( $top->{ovstatus} eq 'down' );
t( $top->{alarm} );

$o->Service::start();
$o->isup( 'test' );			# ping -> up

t( $top->{ovstatus} eq 'up' );
t( ! $top->{alarm} );

exit 0;
################################################################

__END__
    
    _test_mode: 1
    retries: 	0
    
    Group "G1" {
        hostname: localhost
	Service Ping
	Service TCP/HTTP
	Service UDP/Domain/example.com
	Service UDP/DNS {
	    zone:	example.com
	    test:	answer
	}
    }

