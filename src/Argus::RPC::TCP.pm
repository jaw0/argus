# -*- perl -*-

# Copyright (c) 2004 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2004-Dec-26 13:41 (EST)
# Function: tcp sunrpc testing
#
# $Id: Argus::RPC::TCP.pm,v 1.5 2005/02/14 04:06:28 jaw Exp $

package Argus::RPC::TCP;
use Argus::RPC;
@ISA = qw(Argus::RPC TCP);

use strict qw(refs vars);
use vars qw($doc @ISA);

$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [qw(Argus::RPC TCP Service MonEl BaseIO)],
    methods => {},
    versn => '3.4',
    fields => {
	
    },

};


sub probe {
    my $name = shift;

    return [7, \&config] if $name =~ /TCP\/RPC/;
    return [7, \&config] if $name =~ /RPC\/TCP/;
}


sub config {
    my $me = shift;
    my $cf = shift;

    bless $me;
    $me->{tcp}{port} = 111;	# placeholder, not used
    $me->TCP::config($cf);
    $me->Argus::RPC::config($cf);

    $me->{uname} = "TCPRPC_" . $me->{ip}{hostname} . '_' . $me->{rpc}{prognum};
    $me->{uname} .= '_' . $me->{rpc}{version} if $me->{rpc}{version}; 

    $me;
}

sub start {
    my $me = shift;

    $me->{rpc}{state} = 'portmap';
    $me->{tcp}{port}  = $me->{rpc}{portmap_port};
    $me->{tcp}{readhow} = 'toeof';
    # query portmapper for port
    my $rpc =  pack( "NN NN NN x16 NNNN", 
		     $$, 0,  2, 100000, $me->{rpc}{portmap_version}, 3,
		     $me->{rpc}{prognum}, $me->{rpc}{version}, 6, 0);

    $me->{tcp}{send} = pack('N', length($rpc) | 0x80000000) . $rpc;
    
    $me->SUPER::start();
    
}

sub readable {
    my $me = shift;

    my( $fh, $i, $l, $testp );

    $fh = $me->{fd};
    $i = sysread( $fh, $l, 8192 );

    if( $i ){
	$me->debug( "TCP - read data $i" );
	$me->{tcp}{rbuffer} .= $l;
    }
    elsif( defined($i) ){
	$me->debug( 'TCP - read eof' );
	$testp = 1;
    }
    else{
	# $i is undef -> error
	return $me->isdown( "TCP read failed: $!", 'read failed' );
    }

    # do we have a complete rpc reply?
    if( length($me->{tcp}{rbuffer}) >= 4){
	my $len = unpack('N', $me->{tcp}{rbuffer});
	$len &= 0xFFFF;
	$len += 4;
	$testp = 1 if length($me->{tcp}{rbuffer}) >= $len;
    }
    
    if( $testp ){
	if( $me->{rpc}{state} eq 'portmap' ){
	    $me->portmap_result($me->{tcp}{rbuffer});
	}else{
	    return $me->generic_test( $me->{tcp}{rbuffer}, 'TCP/RPC' );
	}
    }else{
	$me->wantread(1);
    }
}

sub portmap_result {
    my $me = shift;
    my $b  = shift;

    my( $xid, $type, $status, $port ) = unpack('x4 NNN x12 N', $b);
    
    return $me->isdown( "TCP/RPC portmapper returned garbage", 'portmap failed' )
	unless $xid == $$ && $type == 1;

    return $me->isdown( "TCP/RPC portmapper lookup failed", 'portmap failed')
	unless $status == 0;

    $me->debug( "TCP/RPC portmapper returned port=$port" );
    $me->debug( "TCP/RPC querying new port" );
    
    # send query to new port
    $me->{rpc}{state} = 'testing';
    $me->{rpc}{port}  = $port;
    $me->{tcp}{port}  = $port;
    my $rpc = pack("NN NN NN x16", $$, 0,  2, $me->{rpc}{prognum}, $me->{rpc}{version}, 0);
    $me->{tcp}{send} = pack('N', length($rpc) | 0x80000000) . $rpc;

    $me->shutdown();
    $me->SUPER::start();
}


################################################################

sub about_more {
    my $me = shift;
    my $ctl = shift;

    $me->SUPER::about_more($ctl);	# NB: SUPER = TCP
    $me->more_about_whom($ctl, 'rpc');
}

################################################################
Doc::register( $doc );
push @Service::probes, \&probe;
1;

