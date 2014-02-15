# -*- perl -*-

# Copyright (c) 2003 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2003-Dec-15 10:47 (EST)
# Function: misc DARP stuff
#
# $Id: DARP::Misc.pm,v 1.13 2010/09/01 20:17:21 jaw Exp $

package DARP::Misc;

use strict qw(refs vars);
use vars qw($doc);

$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [],
    versn => '3.3',
    html  => 'darp',
    methods => {},

    fields => {

	slaves_keep_state => {
	    descr => 'which servers keep status files',
	    attrs => ['config', 'inherit'],
	    default => '*',
	},
	slaves_send_notifies => {
	    descr => 'which servers should send notifications',
	    attrs => ['config', 'inherit'],
	    default => '*',
	},

	master_notif_gravity => {
	    descr => 'multi-master gravitation method',
	    attrs => ['config', 'inherit'],
	},

      darp::i_keep_state => {},
      darp::i_send_notif => {},
      darp::send_notif_tags => {},

    },
};


# QQQ stats_hourly, stats_transition

################################################################



sub enable {

}




################################################################
Doc::register( $doc );

1;
