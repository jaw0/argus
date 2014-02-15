# -*- perl -*-

# Copyright (c) 2004 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2004-Sep-27 21:54 (EDT)
# Function: freeswitch pbx testing
#
# $Id: Argus::Freeswitch.pm,v 1.1 2009/02/22 22:42:40 jaw Exp $

# send commands over freeswitch client interface
# wiki.freeswitch.org/wiki/Mod_commands

package Argus::Freeswitch;
@ISA = qw(TCP);

use strict qw(refs vars);
use vars qw($doc @ISA);

my $PORT = 8021;

$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [qw(TCP Service MonEl BaseIO)],
    methods => {},
    versn => '3.7',
    html  => 'freeswitch',
    fields => {
      freesw::pass => {
	  descr => 'FreeSWITCH client password',
	  attrs => ['config', 'inherit'],
	  default => 'ClueCon',
      },
      freesw::cmd => {
	  descr => 'FreeSWITCH API Command',
	  attrs => ['config', 'inherit'],
      },

	
    },

};


sub probe {
    my $name = shift;

    return [14, \&config] if $name =~ /TCP\/Freeswitch/i;
}


sub config {
    my $me = shift;
    my $cf = shift;

    bless $me;
    $me->{tcp}{port} = $PORT; 		# possibly overridden by config
    $me->{tcp}{readhow} = 'toeof';
    
    $me->TCP::config($cf);
    $me->init_from_config( $cf, $doc, 'freesw' );

    $me->{tcp}{send} = join( "\r\n",
			     "auth $me->{freesw}{pass}", "",
			     ($me->{freesw}{cmd} ?
			       ( "api $me->{freesw}{cmd}", "" ) : ()),
			     "exit", "");
    
    $me->{uname}  = "Freeswitch_$me->{ip}{hostname}";
    $me->{uname} .= "_$me->{freesw}{cmd}" if $me->{freesw}{cmd};
    # ...

    
    $me;
}

################################################################
sub about_more {
    my $me = shift;
    my $ctl = shift;

    $me->SUPER::about_more($ctl);	# NB: SUPER = TCP
    $me->more_about_whom($ctl, 'freesw');
}

################################################################
Doc::register( $doc );
push @Service::probes, \&probe;

1;
