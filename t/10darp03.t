# -*- perl -*-
# Function: test of DARP master - distributed mode

# $opt_f = 1;
require "t/libs.pl";

unless( $HAVE_DARP ){
    print "1..0 \# Skipped: no DARP\n";
    exit;
}
print "1..6\n";

$top = Conf::testconfig( \*DATA );

# gravity up
$o = $MonEl::byname{'Top:G1:S1'};
$o->{darp}{statuses}{master0} = 'up';
Control::func( 'darp_update', object => 'Top:G1:S1', tag => 'slave1', status => 'up' );
Control::func( 'darp_update', object => 'Top:G1:S1', tag => 'slave2', status => 'up' );
t( $o->{status} eq 'up' );

Control::func( 'darp_update', object => 'Top:G1:S1', tag => 'slave1', status => 'down' );
t( $o->{status} eq 'up' );
Control::func( 'darp_update', object => 'Top:G1:S1', tag => 'slave2', status => 'down' );
# remember - master status is not considered
t( $o->{status} eq 'down' );

# gravity down
$o = $MonEl::byname{'Top:G2:S1'};
$o->{darp}{statuses}{master0} = 'up';
Control::func( 'darp_update', object => 'Top:G2:S1', tag => 'slave1', status => 'up' );
Control::func( 'darp_update', object => 'Top:G2:S1', tag => 'slave2', status => 'up' );
t( $o->{status} eq 'up' );

$o->start();
$o->isdown( 'test' );
t( $o->{status} eq 'up' );
Control::func( 'darp_update', object => 'Top:G2:S1', tag => 'slave1', status => 'down' );
t( $o->{status} eq 'down' );


exit 0;
################################################################

__END__
    
    _test_mode: 1
    retries: 0
    
    DARP "master0" {
        port:  54321

	slave "slave1" {
	    hostname:  127.0.0.1
	    secret:    hush!
	}

	slave "slave2" {
	    hostname:  127.0.0.1
	    secret:    hush!
	}
    }

    Group "G1" {
        darp_mode: distributed
	darp_gravity: up

	Service TCP/SMTP {
	    hostname: 127.0.0.1
	    uname: S1
	}
    }

    Group "G2" {
        darp_mode: distributed
	darp_gravity: down

	Service TCP/SMTP {
	    hostname: 127.0.0.1
	    uname: S1
	}
    }

