# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Apr-03 18:25 (EST)
# Function: testing of UDP services
#
# $Id: UDP.pm,v 1.79 2012/12/02 22:21:40 jaw Exp $


package UDP;
use Argus::Encode;
use Argus::IP;
use Fcntl;
use Socket;
use DNS::UDP;
use Argus::SNMP;
use Argus::SIP::UDP;
use Argus::RPC::UDP;

use POSIX qw(:errno_h);
BEGIN {
    eval { require Socket6; import Socket6; };
}

@ISA = qw(Service Argus::IP);

use strict qw(refs vars);
use vars qw(@ISA $doc);

$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [qw(Service MonEl BaseIO)],
    methods => {},
    html   => 'services',
    fields => {
      udp::port => {
	  descr => 'UDP port to test',
	  attrs => ['config'],
      },
      udp::send => {
	  descr => 'text to send once connected',
	  attrs => ['config'],
      },
      udp::verify_response_ip => {
          descr => 'verify that responses come from the correct IP address',
          attrs => ['config', 'inherit', 'bool'],
          versn => 3.7,
          default => 'yes',
      },
      udp::verify_response_port => {
          descr => 'verify that responses come from the correct port',
          attrs => ['config', 'inherit', 'bool'],
          versn => 3.7,
          default => 'yes',
      },
      udp::rbuffer => {
	  descr => 'read buffer',
      },
      udp::wbuffer => {
	  descr => 'write buffer',
      },
      udp::connectp => {},
      udp::build    => {},

    },
};

my %config =
(
 # not supported by all radius servers
 RADIUS => {
     port => 1645, send => pack( "CCnx16", 12, ($$ & 0xFF), 20 ),
     timeout => 10,
 },

 SNMP => {
     port => 161,  timeout => 5,
 },

 NTP => { # RFC 2030
     port => 123,  timeout => 10,
     send => pack("CCCC x44", 0x23,0,0,0),
 },
 'NTP/Stratum' => {
     port => 123,  timeout => 10,
     send => pack("CCCC x44", 0x23,0,0,0),
     unpack => 'xC',
 },
 'NTP/Dispersion' => {
     # root dispersion in seconds
     port => 123,  timeout => 10,
     send => pack("CCCC x44", 0x23,0,0,0),
     unpack => 'x8N', scale => 65536,
 },

 # NFS = RFC 1094; RPC = RFC 1057; XDR = RFC 1014
 # NFSv2 - NFSPROC_NULL
 NFS => {
     port => 2049, timeout => 10,
     send => pack( "NN NN NN x16", $$, 0,  2, 100003, 2, 0),
     # xid, type, rpcver, prog, ver, func, cred(flavor, len, null), verf(flavor, len, null)
 },

 NFSv3 => {
     port => 2049, timeout => 10,
     send => pack( "NN NN NN x16", $$, 0,  2, 100003, 3, 0),
     #                                                ^
     #                                  only difference
 },

 Portmap => {
     port => 111, timeout => 10,
     send => pack( "NN NN NN x16", $$, 0,  2, 100000, 0, 0),
 },
 Portmap2 => {
     port => 111, timeout => 10,
     send => pack( "NN NN NN x16", $$, 0,  2, 100000, 2, 0),
 },
 Portmap3 => {
     port => 111, timeout => 10,
     send => pack( "NN NN NN x16", $$, 0,  2, 100000, 3, 0),
 },
 Portmap4 => {
     port => 111, timeout => 10,
     send => pack( "NN NN NN x16", $$, 0,  2, 100000, 4, 0),
 },

 IAX2 => {
     port => 4569, timeout => 10,
     send => pack('CCCC N CCCC', 0x80,0,0,0, 0, 0,0,6,2),
     # iax cmd, ping
 },


 );

my $PROTO_UDP = getprotobyname('udp');

sub probe {
    my $name = shift;

    return ( $name =~ /^UDP/ ) ? [ 3, \&config ] : undef;
}

sub config {
    my $me = shift;
    my $cf = shift;
    my( $name, $base );

    bless $me if( ref($me) eq 'Service' );

    $name = $me->{name};
    $name =~ s/^UDP\/?//;
    $base = $name;
    $base =~ s/\/.*// unless $config{$base};

    if( $config{$base} ){
	$me->{srvc}{timeout}     ||= $config{$base}{timeout};
	$me->{udp}{port}         ||= $config{$base}{port};
	$me->{udp}{send}         ||= $config{$base}{send};
	$me->{test}{expect}      ||= $config{$base}{expect};
	$me->{test}{unpack}      ||= $config{$base}{unpack};
	$me->{test}{scale}       ||= $config{$base}{scale};
    }

    $me->{label_right_maybe} ||= $name;

    $me->Argus::IP::init( $cf );
    $me->Argus::IP::config( $cf );
    $me->init_from_config( $cf, $doc, 'udp' );

    $me->{friendlyname} = ($config{$base} ? $base : "UDP/$me->{udp}{port}") . " on $me->{ip}{hostname}";

    if( $name ){
	$me->{uname} = "${name}_$me->{ip}{hostname}";
    }else{
	$me->{uname} = "UDP_$me->{udp}{port}_$me->{ip}{hostname}";
    }

    unless( $me->{udp}{port} ){
	return $cf->error( "Incomplete specification or unknown protocol for Service $name" );
    }

    $me;
}

sub configured {
    my $me = shift;

    $me->Argus::IP::done_done();
}

sub start {
    my $me = shift;

    $me->SUPER::start();

    $me->{ip}{addr}->refresh($me);

    if( $me->{ip}{addr}->is_timed_out() ){
        return $me->isdown( "cannot resolve hostname" );
    }

    unless( $me->{ip}{addr}->is_valid() ){
        $me->debug( 'Test skipped - resolv still pending' );
        # prevent retrydelay from kicking in
        $me->{srvc}{tries} = 0;
        return $me->done();
    }

    $me->open_socket();
    $me->connect_and_send();
}

sub open_socket {
    my $me = shift;
    my( $fh, $i, $ipv );

    my $ip = $me->{udp}{addr} = $me->{ip}{addr}->addr();
    $me->{fd} = $fh = BaseIO::anon_fh();

    if( length($ip) == 4 ){
	$i = socket($fh, PF_INET,  SOCK_DGRAM, $PROTO_UDP);
    }else{
	$i = socket($fh, PF_INET6, SOCK_DGRAM, $PROTO_UDP);
	$ipv = ' IPv6';
    }
    unless($i){
	my $m = "socket failed: $!";
	::sysproblem( "UDP $m" );
	$me->debug( $m );
	return $me->done();
    }

    $me->baseio_init();

    $me->debug( "UDP Start: connecting -$ipv udp/$me->{udp}{port}, ".
		"$me->{ip}{hostname}, try $me->{srvc}{tries}" );

    $me->set_src_addr( 1 )
	|| return $me->done();

}



sub connect_and_send {
    my $me = shift;
    my( $i );

    my $fh = $me->{fd};
    my $ip = $me->{udp}{addr};

    if( $me->{udp}{connectp} ){
	if( length($ip) == 4 ){
	    $i = connect( $fh, sockaddr_in($me->{udp}{port}, $ip) );
	}else{
	    $i = connect( $fh, pack_sockaddr_in6($me->{udp}{port}, $ip) );
	}

	unless($i){
	    my $m = "connect failed: $!";
	    ::sysproblem( "UDP $m" );
	    $me->debug( $m );
	    return $me->done();
	}
    }

    if( $me->{udp}{build} ){
	$me->{udp}{build}->($me);
    }

    # Like sending owls to Athens, as the proverb goes.
    #   -- Plato, Diogenes Laertius
    if( $me->{udp}{connectp} ){
	$i = send( $fh, $me->{udp}{send}, 0 );
    }else{
	if( length($ip) == 4 ){
	    $i = send( $fh, $me->{udp}{send}, 0, sockaddr_in($me->{udp}{port}, $ip) );
	}else{
	    $i = send( $fh, $me->{udp}{send}, 0, pack_sockaddr_in6($me->{udp}{port}, $ip) );
	}
    }
    unless($i){
	# QQQ, should I try to sort out errors, down on some, sysproblem on others?
        $me->{ip}{addr}->try_another();
	$me->isdown( "UDP send failed: $!", 'send failed' );
	return;
    }

    $me->debug( 'UDP sent data' );
    $me->wantread(1);
    $me->wantwrit(0);
    $me->settimeout( $me->{srvc}{timeout} );
    $me->{srvc}{state} = 'waiting';

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
    $me->{udp}{rbuffer} = $l;		# for debugging

    # yet I will read the writing unto the king, and make known to him the interpretation
    #   -- daniel 5:17

    return $me->generic_test( $l );
}

sub timeout {
    my $me = shift;

    $me->{ip}{addr}->try_another();
    $me->isdown( 'UDP timeout', 'timeout' );
}

# drop forged responses
sub check_response {
    my $me = shift;
    my $sa = shift;

    my $ip = $me->{udp}{addr};
    my $pt = $me->{udp}{port},

    my $ok = 1;
    eval {
	my($rport, $rip) = (length($ip) == 4) ? sockaddr_in( $sa ) : unpack_sockaddr_in6( $sa );
	my $ripa = ::xxx_inet_ntoa($rip);

        $ok = 0 if $me->{udp}{verify_response_ip}   && ($rip ne $ip);
        $ok = 0 if $me->{udp}{verify_response_port} && ($rport != $pt);

	$me->debug("unexpected response from $ripa:$rport") unless $ok;
    };
    $me->debug("udp recv check failed: $@") if $@;

    return $ok ? undef : 1;
}

################################################################
# and also object methods
################################################################

sub done {
    my $me = shift;

    $me->Argus::IP::done();
    $me->Service::done();
    $me->Argus::IP::done_done();
}

# sub isdown {
#     my $me = shift;
#     my $reason = shift;
#
#     $me->Service::isdown($reason);
# }
#
# sub isup {
#     my $me = shift;
#
#     $me->Service::isup();
# }

sub about_more {
    my $me = shift;
    my $ctl = shift;

    $me->SUPER::about_more($ctl);
    $me->more_about_whom($ctl, 'ip', 'udp');
}

sub webpage_more {
    my $me = shift;
    my $fh = shift;

    $me->Argus::IP::webpage_more($fh);
    print $fh "<TR><TD><L10N port></TD><TD>$me->{udp}{port}</TD></TR>\n";
}

################################################################
# global config
################################################################
Doc::register( $doc );
push @Service::probes, \&probe;

1;

