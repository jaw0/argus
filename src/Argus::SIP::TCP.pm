# -*- perl -*-

# Copyright (c) 2004 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2004-Dec-23 16:46 (EST)
# Function: 
#
# $Id: Argus::SIP::TCP.pm,v 1.1 2004/12/24 20:09:58 jaw Exp $

package Argus::SIP::TCP;
use Argus::SIP;
@ISA = qw(Argus::SIP TCP);

use strict qw(refs vars);
use vars qw($doc @ISA);

$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [qw(Argus::SIP TCP Service MonEl BaseIO)],
    methods => {},
    versn => '3.4',
    fields => {

    },

};


sub probe {
    my $name = shift;

    return [7, \&config] if $name =~ /TCP\/SIP/;
}


sub config {
    my $me = shift;
    my $cf = shift;

    bless $me;
    $me->{tcp}{port} = 5060; 		# possibly overridden by config
    $me->{tcp}{readhow} = 'toblank';
    $me->{tcp}{expect}  = 'SIP';
    $me->TCP::config($cf);
    $me->Argus::SIP::config($cf);

    $me->{tcp}{build}  = \&build;
    
    $me->{uname}  = "TCPSIP_";
    $me->{uname} .= $me->{ip}{hostname};
    
    $me;
}

sub build {
    my $me = shift;
    $me->{tcp}{send} = $me->build_pkt( 'TCP' );
}


################################################################

sub about_more {
    my $me = shift;
    my $ctl = shift;
    my( $k, $v );

    $me->SUPER::about_more($ctl);	# NB: SUPER = TCP
    $me->more_about_whom($ctl, 'sip');
}



################################################################
Doc::register( $doc );
push @Service::probes, \&probe;
1;

