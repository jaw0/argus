# -*- perl -*-
# Function: test notifications

# $opt_f = 1;

print "1..8\n";
require "t/libs.pl";

$top = Conf::testconfig( \*DATA );

# find object
$o = $MonEl::byname{'Top:G1:S1'};
die unless $o;

# manual ack
$o->Service::start();
$o->isdown( 'test' );			# ping1 -> down

$n = Notify::byid( 1 );
t( $n );
t( $n->{state} eq 'active' );

$n->ack();
t( $n->{state} eq 'acked' );

# autoack
$o = $MonEl::byname{'Top:G1:S2'};
die unless $o;
$o->Service::start();
$o->isdown( 'test' );			# ping2 -> down

$n = Notify::byid( 2 );
t( $n );
t( $n->{state} eq 'acked' );

# ackonup
$o = $MonEl::byname{'Top:G1:S3'};
die unless $o;
$o->Service::start();
$o->isdown( 'test' );			# ping3 -> down

$n = Notify::byid( 3 );
t( $n );
t( $n->{state} eq 'active' );

$o->Service::start();
$o->isup();				# ping3 -> up
Notify::maintenance();
t( $n->{state} eq 'acked' );

exit 0;
################################################################

__END__
    
    _test_mode: 1
    retries: 	0
    notify:     null
    
    Group "G1" {
        hostname: localhost
	Service Ping {
	    uname: S1
	}
	Service Ping {
	    uname:      S2
	    autoack:    yes
	}
	Service Ping {
	    uname:      S3
	    ackonup:    yes
	}
    }

