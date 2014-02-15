# -*- perl -*-

# Copyright (c) 2004 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2004-Apr-28 12:55 (EDT)
# Function: UDP based DNS functions
#
# $Id: DNS::UDP.pm,v 1.4 2010/09/11 19:10:42 jaw Exp $

package DNS::UDP;
use DNS;
@ISA = qw(DNS UDP);

use strict qw(refs vars);
use vars qw($doc @ISA);


$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [qw(DNS UDP Service MonEl BaseIO)],
    methods => {},
    versn => '3.4',
    html  => 'dns',
    fields => {

    },

};


sub probe {
    my $name = shift;

    return [7, \&config] if $name =~ /(DNS|Domain)/;
}


sub config {
    my $me = shift;
    my $cf = shift;

    bless $me;
    $me->{udp}{port} = 53; 	# possibly overridden by config
    
    $me->UDP::config($cf);
    $me->DNS::config($cf);
    
    $me->{udp}{send} = $me->build_packet($cf, $me->{dns});

    if( $me->{dns}{zone} && $me->{dns}{zone} ne '.' ){
	$me->{label_right_maybe} = $me->{dns}{zone};
    }else{
	$me->{label_right_maybe} = $me->{dns}{name};
    }

    $me->{uname}  = "DNS_";
    $me->{uname} .= $me->{dns}{zone}  . '_' if $me->{dns}{zone} && $me->{dns}{zone} ne '.';
    $me->{uname} .= $me->{dns}{query} . '_';
    $me->{uname} .= $me->{dns}{test}  . '_' if $me->{dns}{test} && $me->{dns}{test} ne 'none';
    $me->{uname} .= $me->{ip}{hostname};
    
    $me;
}

sub readable {
    my $me = shift;
    my( $fh, $i, $l );

    $fh = $me->{fd};
    $i = recv($fh, $l, 8192, 0);
    return $me->isdown( "DNS/UDP recv failed: $!", 'recv failed' )
	unless defined($i);

    $me->debug("readable");
    return if $me->check_response($i);

    $me->debug( "DNS/UDP recv data" );
    $me->{udp}{rbuffer} = $l;		# for debugging

    $me->testable( $l );
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

    $me->SUPER::about_more($ctl);	# NB: SUPER = UDP
    $me->more_about_whom($ctl, 'dns');
}



################################################################
Doc::register( $doc );
push @Service::probes, \&probe;
1;

