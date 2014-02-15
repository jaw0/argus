# -*- perl -*-
# Function: test of DARP communication

# we create a schizo-argus that talks to itself...

#$opt_f = 1;
require "t/libs.pl";

unless( $HAVE_DARP ){
    print "1..0 \# Skipped: no DARP\n";
    exit;
}
print "1..5\n";

$top = Conf::testconfig( \*DATA );

# did config parse as expected
t( $Conf::has_errors == 0 );

$o = $MonEl::byname{'DARP:Slave_slave1'};
t( $o );

# attempt to connect, authenticate
alarm( 60 );
while( $o->{darps}{state} ne 'up' ){
    BaseIO::oneloop( maxperiod => 10 );
}
t( $o->{darps}{state} eq 'up' );


# several rounds of keepalives
$o->send_command('echo');
$s = $o->{darps}{seqno};

alarm( 60 );
while( $o->{darps}{seqno} != $s + 3 ){
    BaseIO::oneloop( maxperiod => 10 );
}
t( $o->{darps}{state} eq 'up' );
t( $o->{darps}{seqno} == $s + 3 );


exit 0;
################################################################

__END__
    
    _test_mode: 1
    
    DARP "slave1" {
        debug: yes
        port:  54321

	slave "slave1" {
	    hostname:  127.0.0.1
	    secret:    hush!
	}

	master "master0" {
	    frequency: 5
	    timeout:   5
	    hostname: 127.0.0.1
	    # port:     2055
	    secret:   hush!
	    fetchconfig: no
	}
    }

    Group "G1" {
        darp_mode: redundant
	Service TCP/SMTP {
	    hostname: 127.0.0.1
	    uname: S1
	}
    }

