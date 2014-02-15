# -*- perl -*-
# Function: SSL/POPS

# $opt_f = 1;

require "t/libs.pl";
unless( $HAVE_SSL ){
    print "1..0 \# Skipped: no SSL\n";
    exit;
}
print "1..2\n";

$top = Conf::testconfig( \*DATA );

$o = $MonEl::byname{'Top:G1:S1'};
t( $o->{tcp}{ssl} );

alarm( 60 );
while( ! $o->{srvc}{finished} ){
    BaseIO::oneloop( maxperiod => 10 );
}
t( $o->{status} eq 'up' );

exit 0;


################################################################

__END__
    
    _test_mode: 1
    retries: 	0
    debug: yes
    
    Group "G1" {
	Service TCP/IMAPS {
	    uname:     S1
	    hostname:  mail.tcp4me.com
	    frequency: 5
        }
    }

