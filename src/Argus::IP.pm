# -*- perl -*-

# Copyright (c) 2004 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2004-Sep-18 12:17 (EDT)
# Function: common IP functions
#
# $Id: Argus::IP.pm,v 1.13 2012/09/30 19:37:41 jaw Exp $

package Argus::IP;

use Socket;
BEGIN {
    eval { require Socket6; import Socket6; $HAVE_S6 = 1; };
}

use strict qw(refs vars);
use vars qw($doc $HAVE_S6);


my $IPPROTO_IP = 0;	# standard?
my $IPOPT_NOP  = 1;	# RFC 791
my $IPOPT_LSRR = 131;	# RFC 791
my $IPOPT_SSRR = 137;	# RFC 791

# NetBSD, FreeBSD, OpenBSD, Solaris, SunOS, Darwin, Windows,
my $IP_OPTIONS = 1;
my $IP_TOS     = 3;
my $IP_TTL     = 4;

if( $^O eq 'linux' ){
    # linux has to be f***ing different...
    $IP_TOS     = 1;
    $IP_TTL     = 2;
    $IP_OPTIONS	= 4;
}

$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [],
    methods => {},
    html   => 'services',
    versn  => '3.4',
    fields => {
      ip::ipopts  => {
	  descr => 'informational',
      },
      ip::hostname => {
	  descr => 'hostname or IP address to test',
	  attrs => ['config', 'inherit'],
      },
      ip::addr => {
	  descr => 'encoded IP address',
      },
      ip::srcaddr => {
	  descr => 'local IP address',
	  attrs => ['config', 'inherit'],
      },
      ip::srcip => {
	  descr => 'encoded local IP address',
      },
      ip::ttl => {
	  descr => 'numeric IP TTL',
	  attrs => ['config', 'inherit'],
      },
      ip::tos => {
	  descr => 'numeric IP TOS',
	  attrs => ['config', 'inherit'],
      },
      ip::lsrr => {
	  descr => 'IP loose source route',
	  exmpl => '1.2.3.4  2.3.4.5  4.5.6.7',
	  attrs => ['config', 'inherit'],
      },
      ip::ssrr => {
	  descr => 'IP strict source route',
	  exmpl => '1.2.3.4  2.3.4.5  4.5.6.7',
	  attrs => ['config', 'inherit'],
      },
      ip::ipversion => {
          descr => 'IP version precedence',
	  attrs => ['config', 'inherit'],
          default => '4 6',
          versn => '3.7',
      },

      ip::srcport => {},
      ip::resolvp => {},
      ip::resolvt => {},

    },
};

sub init {
    my $me = shift;
    my $cf = shift;

    $me->init_from_config( $cf, $doc, 'ip' );
}

sub config {
    my $me = shift;
    my $cf = shift;

    unless( $me->{ip}{hostname} ){
	return $cf->error( "Hostname not specified" );
    }

    $me->{ip}{addr} = Argus::Resolv::IP->new( $me->{ip}{hostname}, $me->{ip}{ipversion}, $cf );

    if( $me->{ip}{srcaddr} ){
	$me->{ip}{srcip} = ::resolve($me->{ip}{srcaddr});
	$cf->warning( "Cannot resolve $me->{ip}{srcaddr}" ) unless $me->{ip}{srcip};

	if( $me->{ip}{addr} && (length($me->{ip}{srcip}) != length($me->{ip}{addr})) ){
	    $cf->warning( "SRC + DST addresses have mismatched IP version" );
	    delete $me->{ip}{srcip};
	}
    }

    if( $me->{ip}{ssrr} ){
	$me->{ip}{ipopts} .= ' ssrr';
	my @a;

	foreach my $h (split /\s+/, $me->{ip}{ssrr}){
	    my $a = ::resolve($h);
	    unless( $a ){
		$cf->warning( "cannot resolve host $h" );
		next;
	    }
	    push @a, $a;
	    last if @a >= 7;
	}

	$me->{ip}{ssrr} = \@a;
	delete $me->{ip}{lsrr};		# cannot have both
    }


    if( $me->{ip}{lsrr} ){
	$me->{ip}{ipopts} .= ' lsrr';
	my @a;

	foreach my $h (split /\s+/, $me->{ip}{lsrr}){
	    my $a = ::resolve($h);
	    unless( $a ){
		$cf->warning( "cannot resolve host $h" );
		next;
	    }
	    push @a, $a;
	    last if @a >= 7;
	}

	$me->{ip}{lsrr} = \@a;
    }

    $me->{ip}{ipopts} .= ' tos' if $me->{ip}{tos};
    $me->{ip}{ipopts} .= ' ttl' if $me->{ip}{ttl};

    1;
}

sub set_src_addr {
    my $me  = shift;
    my $bp  = shift;
    my $i;

    my $fh  = $me->{fd};
    my $src = $me->{ip}{srcip};
    my $ip  = $me->{ip}{addr}->addr();

    if( $src && length($src) != length($ip) ){
	$me->loggit( msg => "cannot set requested src addr - version mismatch",
		     tag => 'IP',
		     lpf => 1 );
	$src = undef;
    }

    # randomize port
    my $portr = int(rand(0xffff)) ^ $^T;
    for my $portn (0..65535){
	my $port = ($portr ^ $portn) & 0xffff;
	next if $port <= 1024;
	my $v;

	if( ! $src ){
	    if( $bp ){
		if( length($ip) == 4 ){
		    $i = bind( $fh, sockaddr_in($port, INADDR_ANY) );
		}elsif( $HAVE_S6 ){
		    $i = bind($fh, pack_sockaddr_in6($port, in6addr_any) );
		}else{
		    $i = 1;
		    last;
		}
	    }else{
		$i = 1;
		last;
	    }
	}elsif( length($src) == 4 ){
	    $i = bind( $fh, sockaddr_in($port, $src) );
	}elsif( $HAVE_S6 ){
	    $i = bind( $fh, pack_sockaddr_in6($port, $src) );
	}else{
	    # don't bind
	    $i = 1;
	    last;
	}

	if($i){
	    $me->debug("binding to port $port");
	    last;
	}
    }

    unless($i){
	my $m = "bind failed: $!";
	::sysproblem( "IP $m" );
	$me->debug( $m );
	return 0;
    }

    # set various ip options
    # if the setsockopt fails, just warn and continue, don't fail the test

    if( $me->{ip}{ttl} ){
	$i = setsockopt( $fh, $IPPROTO_IP, $IP_TTL, pack("I",$me->{ip}{ttl}) );
	unless($i){
	    my $m = "set ttl failed: $!";
	    ::sysproblem( "IP: $m");
	    $me->debug( $m );
	}
    }

    if( $me->{ip}{tos} ){
	$i = setsockopt( $fh, $IPPROTO_IP, $IP_TOS, pack("I",$me->{ip}{tos}) );
	unless($i){
	    my $m = "set tos failed: $!";
	    ::sysproblem( "IP: $m");
	    $me->debug( $m );
	}
    }

    # Routed were they, and turned into the bitter
    # Passes of flight; and I, the chase beholding,
    #   -- Dante, Divine Comedy

    if( $me->{ip}{lsrr} ){
	my $i = @{ $me->{ip}{lsrr} } + 1;
	my $opt = pack("CCCC", $IPOPT_NOP, $IPOPT_LSRR, $i * 4 + 3, 4);
	$opt .= $_ foreach @{ $me->{ip}{lsrr} };
	$opt .= $ip;

	$i = setsockopt( $fh, $IPPROTO_IP, $IP_OPTIONS, $opt );

	unless($i){
	    my $m = "set lsrr failed: $!";
	    ::sysproblem( "IP: $m");
	    $me->debug( $m );
	}
    }

    if( $me->{ip}{ssrr} ){
	my $i = @{ $me->{ip}{ssrr} } + 1;
	my $opt = pack("CCCC", $IPOPT_NOP, $IPOPT_SSRR, $i * 4 + 3, 4);
	$opt .= $_ foreach @{ $me->{ip}{ssrr} };
	$opt .= $ip;

	$i = setsockopt( $fh, $IPPROTO_IP, $IP_OPTIONS, $opt );

	unless($i){
	    my $m = "set ssrr failed: $!";
	    ::sysproblem( "IP: $m");
	    $me->debug( $m );
	}
    }

    1;
}

sub done {
    my $me = shift;
}

sub done_done {
    my $me = shift;

    $me->{ip}{addr}->next_needed( $me->{srvc}{nexttesttime} );
}

sub webpage_more {
    my $me = shift;
    my $fh = shift;

    print $fh "<TR><TD><L10N hostname></TD><TD>$me->{ip}{hostname}</TD></TR>\n";
    print $fh "<TR><TD><L10N ipopts></TD><TD>$me->{ip}{ipopts}</TD></TR>\n"
	if $me->{ip}{ipopts};
}



################################################################

Doc::register( $doc );

1;
