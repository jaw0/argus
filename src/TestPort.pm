# -*- perl -*-

# Copyright (c) 2003 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2003-Dec-06 17:38 (EST)
# Function: tcp based test port
#
# $Id: TestPort.pm,v 1.7 2007/03/04 15:51:50 jaw Exp $

package TestPort;
@ISA = qw(BaseIO);

use strict;
use vars qw(@ISA);

# O Light divine! we need no fuller test
# That all is ordered well;
# We know enough to trust that all is best
# Where Love and Wisdom dwell.
#   -- Christopher Pearse Cranch, Oh Love supreme

# enable via:
#   test_port: 12345
#
# test using:
#   telnet argus.example.com 12345
# or
#   Service TCP/Argus {
# 	port: 12345
#       ...

sub new {
    my $class = shift;
    my $fh    = shift;
    my $addr  = shift;
    my $me = {
	type  => 'TestPort',
	state => 'testing',
    };
    bless $me, $class;

    $me->{fd} = $fh;
    $me->wantread(0);
    $me->wantwrit(0);
    $me->settimeout(1);
    $me->baseio_init();

    $me; 
}

sub timeout {
    my $me = shift;

    if( $me->{state} eq 'testing' ){
	$me->wantwrit(1);
	$me->settimeout( 60 );
	$me->{state} = 'writing';
    }else{
	$me->shutdown();
    }
}

sub writable {
    my $me = shift;
    my $fh = $me->{fd};

    syswrite $fh, "$::NAME running\n";
    # QQQ 'with errors' if has_errors?
    $me->shutdown();
}

1;
