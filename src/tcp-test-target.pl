#!/usr/local/bin/perl
# -*- perl -*-

# Copyright (c) 2007 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2007-Mar-02 16:09 (EST)
# Function: 
#
# $Id: tcp-test-target.pl,v 1.4 2007/12/31 01:24:35 jaw Exp $



use lib './bin';
BEGIN {
    require "conf.pl";
    require "misc.pl";
}
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

$opt_f = 1;
$starttime = $^T;
$datadir = '/tmp/mini';

Banner ->Server::new_inet( 54322 );
BaseIO::mainloop( maxperiod => 600 );

################################################################

sub Banner::new {
    my $class = shift;
    my $fh    = shift;

    syswrite $fh, "Banner 200 OK\n";
    undef;
}

################################################################
