# -*- perl -*-

# Copyright (c) 2003 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2003-Dec-04 16:53 (EST)
# Function: DARP Master (Server) config for each slave
#
# $Id: DARP::Conf.pm,v 1.20 2010/01/10 22:23:18 jaw Exp $

# on darp master, darp::conf describes config for each slave.

package DARP::Conf;
@ISA = qw(Configable);

# slave "tag" { data }

use strict qw(refs vars);
use vars qw(@ISA $doc);

$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [],
    versn => '3.3',
    html  => 'darp',
    methods => {
    },
    conf => {
	quotp => 1,
	bodyp => 1,
    },
    fields => {
	status => {},
	debug => {
	    descr => 'send all sorts of gibberish to the log',
	    attrs => ['config', 'inherit'],
	},	    
      darpc::timeout => {
	  descr => 'how long to wait for a response before giving up',
	  attrs => ['config', 'inherit'],
	  default => 60,
      },
      darpc::hostname => {
	  descr => 'hostname or IP address of slave',
	  attrs => ['config', 'inherit'],
      },
      darpc::secret => {
	  descr => 'secret password used to authenticate slave',
	  attrs => ['config', 'inherit'],
      },
      darpc::remote_url => {
	  descr => 'base URL of remote slave',
	  attrs => ['config', 'inherit'],
      },
      darpc::label => {
	  descr => 'label on web page',
	  attrs => ['config', 'inherit'],
      },
      darpc::hidden => {
	  descr => 'not on web page',
	  attrs => ['config', 'inherit'],
      },
	
      darpc::tag  => {},
      darpc::addr => {},

    },
};


sub config {
    my $me = shift;
    my $cf = shift;

    # I should soon make them an excellent servant in all sorts of ways.
    #   -- Homer, Odyssey
    $me->init_from_config( $cf, $doc, '' );
    $me->init_from_config( $cf, $doc, 'darpc' );
    $me->cfcleanup();
    
    $me->{darpc}{tag}  = $me->{name};
    $me->{status} = 'down';
    
    return $cf->error( "DARP Slave secret not specified" )
	unless $me->{darpc}{secret};

    my $ip = ::resolve($me->{darpc}{hostname});
    return $cf->error( "cannot resolve hostname '$me->{darpc}{hostname}'" )
	unless $ip;
    $me->{darpc}{addr} = ::inet_ntoa( $ip );
    
}

################################################################
Doc::register( $doc );

1;
