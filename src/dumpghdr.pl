#!/usr/local/bin/perl
# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Nov-12 16:08 (EST)
# Function: dump the graph data file header - for debugging
#
# $Id: dumpghdr.pl,v 1.3 2008/09/14 15:37:56 jaw Exp $

use lib('/home/athena/jaw/projects/argus/bin');
require "conf.pl";
use Argus::Graph::Data;
use Getopt::Std;
getopts('shd');

$file = shift @ARGV;


my $me = Argus::Graph::Data->new( $file );


foreach $k (sort keys %$me){
    print "$k\t$me->{$k}\n";
}

if( $opt_s ){
    $start = ($me->{sampl_index} - $me->{sampl_count} + $SAMP_NMAX) % $SAMP_NMAX;
    for( $i=0; $i<$me->{sampl_count}; $i++ ){
	my $n = ($i + $start) % $SAMP_NMAX;
	my $off = $n * $SAMP_SIZE + $SAMP_START;
	my $buf;
	sysseek( F, $off, 0 );
	sysread( F, $buf, $SAMP_SIZE );
	my( $t, $v, $f ) =
	    unpack( "NfN", $buf );
	unless( $t ){
	    print "--\n";
	    next;
	}
	$t = "[".scalar(localtime($t))."]";
	print "$t\t$f\t$v\n";
    }
}

if( $opt_h || $opt_d ){
    if( $opt_h ){
	$cnt = $me->{hours_count};
	$idx = $me->{hours_index};
	$start = $HOURS_START;
    }else{
	$cnt = $me->{days_count};
	$idx = $me->{days_index};
	$start = $DAYS_START;
    }
    $first = ($idx - $cnt + $HOURS_NMAX) % $HOURS_NMAX;

    for( $i=0; $i<$cnt; $i++ ){
	my $n = ($i + $first) % $HOURS_NMAX;
	my $off = $n * $HOURS_SIZE + $start;
	my $buf;
	sysseek( F, $off, 0 );
	sysread( F, $buf, $HOURS_SIZE );
	my( $t, $min, $max,
	    $ave, $sdv, $ns, $fl,
	    ) = unpack( "NffffNNx4", $buf );
	unless( $t ){
	    print "--\n";
	    next;
	}

	$t = "[".scalar(localtime($t))."]";
	print "$t\t$fl\t$ns\t[$min, $max]\t[$ave, $sdv]\n";
    }
}


sub error {
    my $msg = shift;
    die $msg;
}

