# -*- perl -*-
# Function: test dependency

# $opt_f = 1;

print "1..4\n";
require "t/libs.pl";

$top = Conf::testconfig( \*DATA );

# find object
$o = $MonEl::byname{'Top:G1:Ping_localhost'};
die unless $o;
$d = $MonEl::byname{'Top:G1:DNS2'};
die unless $d;

$o->Service::start();
$o->isdown( 'test' );			# ping -> down

# test depedency
$d->Service::start();
$d->isdown( 'test' );			# dns -> down
t( $d->{ovstatus} eq 'depends' );

$o->Service::start();
$o->isup( 'test' );			# ping -> up
t( $d->{ovstatus}   eq 'down' );
t( $top->{ovstatus} eq 'down' );

# everything back up
$d->Service::start();			# dns -> up
$d->isup();

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
	    depends:    Top:G1:Ping_localhost
	    zone:	example.com
	    test:	answer
	}
    }

