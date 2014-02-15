# -*- perl -*-

# Copyright (c) 2004 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2004-Dec-23 16:46 (EST)
# Function: 
#
# $Id: Argus::SIP::UDP.pm,v 1.1 2004/12/24 20:09:58 jaw Exp $

package Argus::SIP::UDP;
use Argus::SIP;
@ISA = qw(Argus::SIP UDP);

use strict qw(refs vars);
use vars qw($doc @ISA);

$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [qw(Argus::SIP UDP Service MonEl BaseIO)],
    methods => {},
    versn => '3.4',
    fields => {

    },

};


sub probe {
    my $name = shift;

    return [7, \&config] if $name =~ /UDP\/SIP/;
}


sub config {
    my $me = shift;
    my $cf = shift;

    bless $me;
    $me->{udp}{port} = 5060; 		# possibly overridden by config
    $me->UDP::config($cf);
    $me->Argus::SIP::config($cf);

    $me->{udp}{send}     = 'xxx';
    $me->{udp}{connectp} = 1;
    $me->{udp}{build}    = \&build;
    
    $me->{uname}  = "UDPSIP_";
    $me->{uname} .= $me->{ip}{hostname};
    
    $me;
}

sub build {
    my $me = shift;
    $me->{udp}{send} = $me->build_pkt( 'UDP' );
}


################################################################

sub about_more {
    my $me = shift;
    my $ctl = shift;
    my( $k, $v );

    $me->SUPER::about_more($ctl);	# NB: SUPER = UDP
    $me->more_about_whom($ctl, 'sip');
}



################################################################
Doc::register( $doc );
push @Service::probes, \&probe;
1;

