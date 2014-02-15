# -*- perl -*-
# Function: test of config error recovery

# $opt_f = $opt_d = 1;

print "1..4\n";
require "t/libs.pl";

$top = Conf::testconfig( \*DATA );

# did config parse as expected?
t( $Conf::has_errors == 3 );

t( $MonEl::byname{ 'Top:G1' } );
t( $MonEl::byname{ 'Top:G1:S1' } );
t( $MonEl::byname{ 'Top:G2:S1' } );

exit 0;
################################################################

__END__
    
    _test_mode: 1


    # top level error with nested blocks
    XXX Foo {
	Service: Ping
	Service TCP {
		port: 666
	}
    }

    Group "G1" {
        hostname: localhost
	Service Ping
	Service TCP/HTTP
	Service UDP/Domain/example.com
	Service UDP/DNS {
	    uname:	S1
	    zone:	example.com
	    test:	answer

	    # deep error in service
	    gibberish
	}

	# error in group
	XXX Bar {
		foo: bar
	}
    }

    Group "G2" {
	Service Ping {
		hostname: localhost
		uname:	  S1
	}
    }
