# -*- perl -*-
# Function: test of v4/v6 resolve

# $opt_f = 1;
require "t/libs.pl";

unless( $HAVE_S6 ){
    print "1..0 \# Skipped: no Socket6\n";
    exit;
}
print "1..6\n";

$top = Conf::testconfig( \*DATA );

# did config parse ok?
t( ! $Conf::has_errors );

# resloved as expected?
t( length($MonEl::byname{'Top:G1:S1'}{ping}{addr}{addr}[0]) == 16 );
t( length($MonEl::byname{'Top:G1:S2'}{ping}{addr}{addr}[0]) == 4 );
t( length($MonEl::byname{'Top:G1:S3'}{ping}{addr}{addr}[0]) == 16 );
t( length($MonEl::byname{'Top:G1:S4'}{ping}{addr}{addr}[0]) == 4 );
t( length($MonEl::byname{'Top:G1:S5'}{ping}{addr}{addr}[0]) == 16 );


exit 0;
################################################################

__END__
    
    _test_mode: 1
    resolv_autoconf: no

    Group "G1" {
	Service Ping {
	    hostname: localhost
	    uname: S1
	}
	Service Ping {
	    hostname: 127.0.0.1
	    uname: S2
	}
	Service Ping {
	    hostname: ::1
	    uname: S3
	}
	Service Ping {
	    hostname: localhost._ipv4
	    uname: S4
	}
	Service Ping {
	    hostname: localhost._ipv6
	    uname: S5
	}
    }

