# -*- perl -*-
# Function: test of config parsing

#$opt_f = 1;

print "1..4\n";
require "t/libs.pl";

$top = Conf::testconfig( \*DATA );

# did config parse ok?
t( ! $Conf::has_errors );

# did the # come out right?
t( $top->{note} eq 'Note # Note'
   );
t( $Service::n_services == 4 );

# find object
$o = $MonEl::byname{'Top:G1:Ping_localhost'};
t( $o );


exit 0;
################################################################

__END__
    
    _test_mode: 1
    retries: 	0
    note:    	Note \# Note
    resolv_autoconf: no

    Method "siren" {
        command:	echo whoop whoop
    }

    Group "G1" {
        hostname: localhost
        cron "50 * * * *" {
            func:	override
            text:	override test
            expires:	60
            mode:	manual
            quiet:  	yes
        }
	Service Ping
	Service TCP/HTTP
	Service UDP/Domain/example.com
	Service UDP/DNS {
	    zone:	example.com
	    test:	answer
	}
    }

    Group "G2" {
        Alias "G1P" "Top:G1:Ping_localhost"
    }


