# -*- perl -*-
# Function: SNMPv3 SHA1/DES

# $opt_f = 1;

eval{ require Digest::SHA1; $HAVE_SHA1 = 1; };
eval{ require Digest::HMAC; $HAVE_HMAC = 1; };
eval{ require Crypt::DES;   $HAVE_DES  = 1; };

require "t/libs.pl";

unless( $HAVE_SHA1 && $HAVE_HMAC && $HAVE_DES ){
    print "1..0 \# Skipped: no SNMPv3\n";
    exit;
}

print "1..2\n";

$top = Conf::testconfig( \*DATA );

$o = $MonEl::byname{'Top:G1:S1'};
alarm( 60 );
while( ! $o->{srvc}{result} ){
    BaseIO::oneloop( maxperiod => 10 );
}
t( $o->{status} eq 'up' );
t( $o->{srvc}{result} );

exit 0;


################################################################

__END__
    
    _test_mode: 1
    retries: 	0
    debug: yes
    
    Group "G1" {
	Service UDP/SNMPv3 {
	    uname:        S1
	    hostname:	  localhost
	    oid:	  ifInOctets.1
	    snmpuser:	  User1
	    snmppass:	  Password1
	    snmpprivpass: Privpass1
	    frequency:	  5
        }
    }

