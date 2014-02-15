# -*- perl -*-

# Copyright (c) 2004 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2004-Apr-28 12:57 (EDT)
# Function: TCP based DNS functions
#
# $Id: DNS::TCP.pm,v 1.5 2004/09/18 21:05:22 jaw Exp $

package DNS::TCP;
use DNS;
@ISA = qw(DNS TCP);

use strict qw(refs vars);
use vars qw($doc @ISA);


$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [qw(DNS TCP Service MonEl BaseIO)],
    methods => {},
    versn => '3.4',
    html  => 'dns',
    fields => {

    },

};


sub probe {
    my $name = shift;

    return [11, \&config] if $name =~ /TCP\/(DNS|Domain)/;
}


sub config {
    my $me = shift;
    my $cf = shift;

    bless $me;
    $me->{tcp}{port} = 53; 		# possibly overridden by config
    $me->{tcp}{readhow} = 'toeof';	# to appease TCP::writable
    $me->TCP::config($cf);
    $me->DNS::config($cf);

    # RFC 1035 4.2.2
    my $pkt = $me->build_packet($cf, $me->{dns});
    $me->{tcp}{send} = pack('n', length($pkt)) . $pkt;
    
    if( $me->{dns}{zone} && $me->{dns}{zone} ne '.' ){
	$me->{label_right_maybe} = $me->{dns}{zone};
    }else{
	$me->{label_right_maybe} = $me->{dns}{name};
    }

    $me->{uname}  = "TCPDNS_";
    $me->{uname} .= $me->{dns}{zone}  . '_' if $me->{dns}{zone} && $me->{dns}{zone} ne '.';
    $me->{uname} .= $me->{dns}{query} . '_';
    $me->{uname} .= $me->{dns}{test}  . '_' if $me->{dns}{test} && $me->{dns}{test} ne 'none';
    $me->{uname} .= $me->{ip}{hostname};
    
    $me;
}

sub readable {
    my $me = shift;
    my( $fh, $i, $l, $buf, $len );

    $fh = $me->{fd};

    $i = sysread( $fh, $l, 8192 );

    # read until correct amount
    
    if( $i ){
	$me->debug( "DNS/TCP - read data $i" );
	$me->{tcp}{rbuffer} .= $l;
    }
    elsif( defined($i) ){
	$me->debug( 'DNS/TCP - read eof' );
	return $me->isdown( "DNS/TCP read premature eof" );
    }
    else{
	# $i is undef -> error
	return $me->isdown( "DNS/TCP read failed: $!", 'read failed' );
    }

    $buf = $me->{tcp}{rbuffer};
    if( length($buf) > 2 ){
	($len, $buf) = unpack( 'n a*', $buf );

	# we only read one answer message
	# XXX - AXFR only works with certain nameservers
	# http://cr.yp.to/djbdns/axfr-notes.html
	
	# print STDERR "DNS/TCP want=$len, have=", length($buf), "\n";
	# ::hexdump( $me->{tcp}{rbuffer} );
	
	if( length($buf) >= $len ){
	    return $me->testable( $buf );
	}
    }

    # else keep reading...
}

################################################################

sub webpage_more {
    my $me = shift;
    my $fh = shift;
    my( $k, $v );
    
    $me->SUPER::webpage_more($fh);
    
    foreach $k (qw(zone)){
	$v = $me->{dns}{$k};
	print $fh "<TR><TD>DNS <L10N $k></TD><TD>$v</TD></TR>\n" if defined($v);
    }
}

sub about_more {
    my $me = shift;
    my $ctl = shift;
    my( $k, $v );

    $me->SUPER::about_more($ctl);	# NB: SUPER = TCP
    $me->more_about_whom($ctl, 'dns');
}



################################################################
Doc::register( $doc );
push @Service::probes, \&probe;
1;

