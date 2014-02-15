# -*- perl -*-

# Copyright (c) 2004 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2004-Dec-26 13:41 (EST)
# Function: udp sunrpc testing
#
# $Id: Argus::RPC::UDP.pm,v 1.6 2008/07/17 03:42:08 jaw Exp $

package Argus::RPC::UDP;
use Argus::RPC;
@ISA = qw(Argus::RPC UDP);

use strict qw(refs vars);
use vars qw($doc @ISA);

$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [qw(Argus::RPC UDP Service MonEl BaseIO)],
    methods => {},
    versn => '3.4',
    fields => {
	
    },

};


sub probe {
    my $name = shift;

    return [7, \&config] if $name =~ /UDP\/RPC/;
    return [7, \&config] if $name =~ /RPC\/UDP/;
}


sub config {
    my $me = shift;
    my $cf = shift;

    bless $me;
    $me->{udp}{port} = 111;	# placeholder, not used
    $me->UDP::config($cf);
    $me->Argus::RPC::config($cf);

    $me->{uname} = "UDPRPC_" . $me->{ip}{hostname} . '_' . $me->{rpc}{prognum};
    $me->{uname} .= '_' . $me->{rpc}{version} if $me->{rpc}{version}; 

    $me;
}

sub start {
    my $me = shift;

    $me->{rpc}{state} = 'portmap';
    $me->{udp}{port}  = $me->{rpc}{portmap_port};
    # query portmapper for port
    $me->{udp}{send}  = pack( "NN NN NN x16 NNNN", $$, 0,  2, 100000, $me->{rpc}{portmap_version}, 3,
			      $me->{rpc}{prognum}, $me->{rpc}{version}, 17, 0);
    
    $me->SUPER::start();
    
}

sub readable {
    my $me = shift;

    my( $fh, $i, $l );

    $fh = $me->{fd};
    $i = recv($fh, $l, 8192, 0);
    return $me->isdown( "UDP recv failed: $!", 'recv failed' )
	unless defined($i);

    return if $me->check_response($i);
    
    $me->debug( 'UDP recv data' );
    $me->{udp}{rbuffer} = $l;
    
    if( $me->{rpc}{state} eq 'portmap' ){
	$me->portmap_result( $l );
    }else{
	return $me->generic_test( $l, 'UDP/RPC' );
    }

}

sub portmap_result {
    my $me = shift;
    my $b  = shift;

    my( $xid, $type, $status, $port ) = unpack('NNN x12 N', $b);
    
    return $me->isdown( "UDP/RPC portmapper returned garbage", 'portmap failed' )
	unless $xid == $$ && $type == 1;

    return $me->isdown( "UDP/RPC portmapper lookup failed", 'portmap failed')
	unless $status == 0;

    $me->debug( "UPC/RPC portmapper returned port=$port" );
    $me->debug( "UDP/RPC querying new port" );
    
    # send query to new port
    $me->{rpc}{state} = 'testing';
    $me->{rpc}{port}  = $port;
    $me->{udp}{port}  = $port;
    $me->{udp}{send}  = pack("NN NN NN x16", $$, 0,  2, $me->{rpc}{prognum}, $me->{rpc}{version}, 0);

    $me->connect_and_send();
}

################################################################

sub about_more {
    my $me = shift;
    my $ctl = shift;

    $me->SUPER::about_more($ctl);	# NB: SUPER = UDP
    $me->more_about_whom($ctl, 'rpc');
}

################################################################
Doc::register( $doc );
push @Service::probes, \&probe;
1;

