# -*- perl -*-

# Copyright (c) 2004 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2004-Sep-27 21:54 (EDT)
# Function: asterisk pbx testing
#
# $Id: Argus::Asterisk.pm,v 1.6 2007/12/31 01:24:30 jaw Exp $

# send commands over asterisk manager interface
# http://www.voip-info.org/wiki-Asterisk+Manager+API

# Ils sont fous ces [Asterisk Users]
#   -- Obelix

package Argus::Asterisk;
@ISA = qw(TCP);

use strict qw(refs vars);
use vars qw($doc @ISA);

my $PORT = 5038;

$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [qw(TCP Service MonEl BaseIO)],
    methods => {},
    versn => '3.4',
    html  => 'asterisk',
    fields => {
      ast::user => {
	  descr => 'Asterisk Manager Username',
	  attrs => ['config', 'inherit'],
      },
      ast::pass => {
	  descr => 'Asterisk Manager Password',
	  attrs => ['config', 'inherit'],
      },
      ast::cmd => {
	  descr => 'Asterisk Manager Command',
	  attrs => ['config', 'inherit'],
      },

	
    },

};


sub probe {
    my $name = shift;

    return [12, \&config] if $name =~ /TCP\/(Asterisk|\*)/;
}


sub config {
    my $me = shift;
    my $cf = shift;

    bless $me;
    $me->{tcp}{port} = $PORT; 		# possibly overridden by config
    $me->{tcp}{readhow} = 'toeof';
    
    $me->TCP::config($cf);
    $me->init_from_config( $cf, $doc, 'ast' );

    $me->{tcp}{send} = join( "\r\n", 
     "Action: Login",
     "Username: $me->{ast}{user}",
     "Secret: $me->{ast}{pass}",
     '',
     ($me->{ast}{cmd} ? ("Action: Command", "Command: $me->{ast}{cmd}", '') : ()),
     # ...
     "Action: Logoff",
     ''
     );
    $me->{tcp}{send} .= "\r\n";
    
    $me->{uname}  = "Asterisk_$me->{ip}{hostname}";
    $me->{uname} .= "_$me->{ast}{cmd}" if $me->{ast}{cmd};
    # ...

    
    $me;
}

################################################################
sub about_more {
    my $me = shift;
    my $ctl = shift;

    $me->SUPER::about_more($ctl);	# NB: SUPER = TCP
    $me->more_about_whom($ctl, 'ast');
}

################################################################
Doc::register( $doc );
push @Service::probes, \&probe;

1;
