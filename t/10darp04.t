# -*- perl -*-
# Function: test of DARP - slave failover

# $opt_f = 1;
require "t/libs.pl";

unless( $HAVE_DARP ){
    print "1..0 \# Skipped: no DARP\n";
    exit;
}
print "1..3\n";

$top = Conf::testconfig( \*DATA );

$o = $MonEl::byname{'Top:G1:S1'};

# master is down - test happens
$DARP::info->{masters}[0]->{status} = 'down';

$o->me_start();
t( $o->{srvc}{state} eq 'connecting' );

while( ! $o->{srvc}{finished} ){
    BaseIO::oneloop( maxperiod => 10 );
}
t( $o->{srvc}{state} eq 'done' );


# master is up - test skipped
$DARP::info->{masters}[0]->{status} = 'up';
$o->me_start();
t( $o->{srvc}{state} eq 'done' );


exit 0;
################################################################

__END__
    
    _test_mode: 1
    debug: yes
    
    DARP "slave1" {

	master "master0" {
	    frequency: 10
	    timeout:   60

	    hostname: 127.0.0.1
	    port:     54321
	    secret:   hush!
	    fetchconfig: no
	}
    }

    Group "G1" {
        darp_mode: failover

	Service TCP/SMTP {
	    hostname: 127.0.0.1
	    uname: S1
	}
    }

