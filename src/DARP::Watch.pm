# -*- perl -*-

# Copyright (c) 2003 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2003-Dec-04 13:08 (EST)
# Function: monitor DARP slave connections
#
# $Id: DARP::Watch.pm,v 1.11 2007/01/12 05:35:10 jaw Exp $

# For some must watch, while some must sleep:
# So runs the world away.
#   -- Shakespeare, Hamlet

package DARP::Watch;
@ISA = qw(Service);
use Argus::Encode;

use strict qw(refs vars);
use vars qw(@ISA $doc);


$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [qw(Service MonEl BaseIO)],
    methods => {},
    versn  => '3.3',
    html   => 'darp',
    fields => {
      darpw::mode  => {
	  descr => 'what type of DARP connection to watch',
	  attrs => ['config'],
	  default => 'slave',
      },
      darpw::watch => {
	  descr => 'which DARP connection to watch',
	  attrs => ['config'],
      },
      darpw::obj => { descr => 'watched object' },
    },
};

sub probe {
    my $name = shift;

    return ( $name =~ /^DARP\/Watch/i ) ? [ 8, \&config ] : undef;
}

sub config {
    my $me = shift;
    my $cf = shift;
    
    bless $me;
    $me->init_from_config( $cf, $doc, 'darpw' );
    
    if( $me->{name} =~ /DARP\/Watch\/(.*)/i ){
	$me->{darpw}{watch} ||= $1;
    }

    my $t = $me->{darpw}{watch};
    my $m = $me->{darpw}{mode};
    # it doesn't really make sense to watch anything other than slaves, but we allow it...

    if( $DARP::info && $DARP::info->{all} ){
	foreach my $d ( @{$DARP::info->{all}} ){
	    next unless $t eq $d->{name};
	    next unless lc( $m ) eq lc( $d->{type} );
	    
	    $me->{darpw}{obj} = $d;
	    last;
	}
    }
    
    return $cf->error( "no such DARP entry '$t'" )
	unless $me->{darpw}{obj};
    
    $me->{label_right_maybe} ||= $t;
    $me->{uname} = "DARP_WATCH_${m}_$t";

    $me;
}

sub start {
    my $me = shift;
    my( $ru );

    $me->SUPER::start();
    $ru = $me->{darpw}{obj}->{status};

    if( $ru eq 'up' ){
	$me->isup();
    }else{
	$me->isdown( "connection is $ru", $ru );
    }
}

sub about_more {
    my $me = shift;
    my $ctl = shift;
    my( $k, $v );

    $me->SUPER::about_more($ctl);
    $me->more_about_whom($ctl, 'darpw');
}

    
################################################################
# global config
################################################################
Doc::register( $doc );
push @Service::probes, \&probe;

1;
