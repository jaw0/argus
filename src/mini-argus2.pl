#!/usr/local/bin/perl
# -*- perl -*-

# Copyright (c) 2003 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2003-Dec-09 16:41 (EST)
# Function: for testing
#
# $Id: mini-argus2.pl,v 1.20 2012/10/29 00:50:32 jaw Exp $

use lib './bin';
BEGIN {
    require "conf.pl";
    require "misc.pl";
    require "common.pl";
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
use Argus::Resolv;
use Argus::Schedule;
use Argus::Dashboard;
use Argus::Ticket;
use DARP;

$opt_d = 1;
$opt_f = 1;
$starttime = $^T;
$datadir = '/tmp/mini';
$COOKIE  = $ENV{ARGUS_COOKIE} = random_cookie();

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
$ENV{ARGUS_CTL} = "$datadir/control";
Control->Server::new_local( $ENV{ARGUS_CTL}, '777' );
BaseIO::mainloop( maxperiod => 600 );

################################################################
__END__

autoack: 1
#_debug_svnsch: yes
debug: yes
sendnotify: no

Resolv {
    debug:  no
    timeout:   10
    frequency: 5
}

DARP "slave1" {
    debug:  no
    Master "master0" {
    debug:  no
        frequency: 5
        hostname: 192.168.200.2
	secret: hush!
        remote_url: http://master.example.com/
    }
}

