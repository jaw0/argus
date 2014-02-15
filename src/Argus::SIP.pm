# -*- perl -*-

# Copyright (c) 2004 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2004-Dec-23 16:58 (EST)
# Function: test SIP (rfc 3261) server
#
# $Id: Argus::SIP.pm,v 1.6 2010/09/01 20:17:21 jaw Exp $

# Seeing only what is fair,
# Sipping only what is sweet,
# Thou dost mock at fate and care.
#   -- Emerson, To the humble Bee.

package Argus::SIP;

use Socket;
BEGIN {
    eval { require Socket6; import Socket6; $HAVE_S6 = 1; };
}

use strict qw(refs vars);
use vars qw($doc @ISA $HAVE_S6);

$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [],
    methods => {},
    versn => '3.4',
    html  => 'services',
    fields => {
	sip::to => {
	    descr => 'SIP Destination URI',
	    attrs => ['config'],
	    exmpl => 'sip:123@sip.example.com',
	},
	sip::from => {
	    descr => 'SIP From URI',
	    attrs => ['config'],
	    exmpl => 'sip:argus@sip.example.com',
	},
	sip::useragent => {
	    descr => 'SIP User-Agent',
	    attrs => ['config', 'inherit'],
	    default => "Argus/$::VERSION ($::ARGUS_URL)",
	},
    },
};

sub config {
    my $me = shift;
    my $cf = shift;
    my( $name, $t, $n, $z );

    $name = $me->{name};
    $name =~ s/^UDP\///;
    $name =~ s/^TCP\///;

    $me->build();
    $me->init_from_config( $cf, $doc, 'sip' );

    $me;
}

sub build_pkt {
    my $me = shift;
    my $pr = shift;

    my $srcip   = '127.0.0.1';
    my $srcport = 0;

    if( $me->{fd} ){
        eval {
            my $sk = getsockname($me->{fd});
            my $af = unpack('xC', $sk);

            if( $HAVE_S6 && $af == AF_INET6 ){
                ($srcport, $srcip) = unpack_sockaddr_in6($sk);
                $srcip = '[' . ::xxx_inet_ntoa($srcip) . ']';
            }else{
                ($srcport, $srcip) = sockaddr_in($sk);
                $srcip = ::xxx_inet_ntoa($srcip);
            }
        };
    }

    my $dstip  = ::xxx_inet_ntoa($me->{ip}{addr});
    my $tagid  = sprintf('%0.8X%0.4X', $^T, $srcport);
    my $branch = $tagid;
    my $callid = $tagid;

    my $to   = $me->{sip}{to}   || "sip:$dstip";
    my $from = $me->{sip}{from} || "sip:argus\@$srcip:$srcport";

    my $pkt = <<EOPKT;
OPTIONS $to SIP/2.0
Via: SIP/2.0/$pr $srcip:$srcport;branch=$branch
Max-Forwards: 70
From: <$from>;tag=$tagid
To: <$to>
Call-ID: $callid\@$srcip
Cseq: 1 OPTIONS
User-Agent: $me->{sip}{useragent}
Content-Length: 0
Accept: */*

EOPKT
    ;

    $me->debug( "SIP PKT: $pkt" );
    $pkt =~ s/\n/\r\n/g;

    $pkt;
}

################################################################
Doc::register( $doc );

1;
