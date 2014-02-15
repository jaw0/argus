# -*- perl -*-
# Function: test override

# $opt_f = 1;

print "1..10\n";
require "t/libs.pl";

$top = Conf::testconfig( \*DATA );

# find object
$o = $MonEl::byname{'Top:G1:Ping_localhost'};
die unless $o;
$d = $MonEl::byname{'Top:G1:DNS2'};
die unless $d;

$o->Service::start();
$o->isdown( 'test' );			# ping -> down

$o->override( mode => 'auto', user => 'test' );
t( $o->{ovstatus}   eq 'override' );
t( $top->{ovstatus} eq 'override' );

$o->Service::start();
$o->isup();				# ping -> up
t( ! $o->{override} );
t( $top->{ovstatus} eq 'up' );

$o->override( mode => 'manual', user => 'test' );
$o->Service::start();
$o->isdown( 'test' );			# ping -> down
t( $o->{ovstatus}   eq 'override' );
t( $top->{ovstatus} eq 'override' );

$d->Service::start();
$d->isdown( 'test' );			# dns -> down
t( $top->{ovstatus} eq 'down' );

$d->Service::start();
$d->isup();				# dns -> up
t( $top->{ovstatus} eq 'override' );

$o->override_remove( 'test', 'test' );
t( $top->{ovstatus} eq 'down' );

$o->Service::start();
$o->isup();				# ping -> up
t( $top->{ovstatus} eq 'up' );



exit 0;
################################################################

__END__
    
    _test_mode: 1
    retries: 	0
    
    Group "G1" {
        hostname: localhost
	Service Ping

	Service UDP/DNS {
	    uname:      DNS2
	    zone:	example.com
	    test:	answer
	}
    }

