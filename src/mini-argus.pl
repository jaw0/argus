#!/usr/local/bin/perl
# -*- perl -*-

# Copyright (c) 2003 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2003-Dec-09 16:41 (EST)
# Function: for testing
#
# $Id: mini-argus.pl,v 1.16 2011/10/26 15:42:22 jaw Exp $

use lib './bin';
BEGIN {
    require "conf.pl";
    require "misc.pl";
}
use Argus::HashDir;
use Diag;
use Doc;
use Control;
use BaseIO;
use Cron;
use Server;
use Commands;
use Conf;
use Configable;
use MonEl;
use Group;
use Alias;
use Service;
use Error;
use Notify;
use Graph;
use NullConf;
use UserCron;
use TestPort;
use Resolv;
use Argus::Schedule;
use DARP;

$opt_f = 1;
$starttime = $^T;
$datadir = '/tmp/mini';

$SIG{PIPE} = 'IGNORE';
$SIG{HUP} = $SIG{QUIT} = $SIG{INT} = $SIG{TERM} = sub {exit};

foreach my $dir (qw(html gdata stats)){
    for my $a ('A'..'Z'){
	mkdir "$datadir/$dir/$a";
	for my $b ('A'..'Z'){
	    mkdir "$datadir/$dir/$a/$b";
	}
    }
}

Conf::testconfig( \*DATA );
Control->Server::new_local( '/tmp/mini/control', '777' );
BaseIO::mainloop( maxperiod => 600 );

################################################################
__END__

autoack: 1
# debug: yes
# community: crayola64
    
DARP "master0" {
	  debug:	yes

	  slave "slave1" {
		  hostname:	192.168.200.2
		  secret:		hush!
		  remote_url:	http://www.example.com/argus
	  }
	  slave "slave2" {
		  hostname:	127.0.0.1
		  secret:		hush!
	  }
}

    Resolv {
	  timeout:     30
	  frequency:   5
	  max_queries: 5000
	  # debug:     yes
    }

Group "Foo" {

        Service Ping {
		hostname:	127.0.0.1
                debug:          yes
                darp_mode:      distributed
                darp_tags:      slave1
        }
	Service UDP/SNMPv2c {
		uname:		athena_snmpv2
#		hostname:	127.0.0.1
                  hostname: gw1-r1.ccsphl.adcopy-inc.com
                    community: purple23
#                port:           1234
                debug:          yes
		oid:		ifInOctets[Level3 - BBHP2941]
#                darp_mode:      distributed
#                darp_tags:      slave1
	}

}

