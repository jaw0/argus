#!/usr/local/bin/perl
# -*- perl -*-

# Copyright (c) 2004 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2004-Feb-06 17:04 (EST)
# Function: 
#
# $Id: graph-dump.pl,v 1.6 2011/11/19 19:03:39 jaw Exp $

use lib './bin';
use Argus::Graph::Data;
require "conf.pl";
use Getopt::Std;

getopts('hSHD');
# -h   header
# -S   samples
# -H   hourlies
# -D   dailies

foreach my $f (@ARGV){
    my $g = Argus::Graph::Data->new_file( 'file', $f );

    dump_head( $g ) if $opt_h;
    dump_samp( $g ) if $opt_S;
    dump_hour( $g ) if $opt_H;
    dump_days( $g ) if $opt_D;
    
}

sub dump_samp {
    my $g = shift;

    $g->readallsamples();

    print "Samples:\n";
    my $n = 0;
    foreach my $s ( @{ $g->{samples} } ){
	print "  $n:\t", scalar( localtime $s->{time} ), "  $s->{flag}  $s->{value}\n";
	$n ++;
    }
}

sub dump_hour {
    my $g = shift;

    $g->readsummary( 'hours', $g->{hours_nmax} );

    print "Hourly:\n";
    foreach my $s ( @{ $g->{samples} } ){
	print "\t", scalar( localtime $s->{time} ),
	"  $s->{flag} $s->{ave} \t[$s->{ns} $s->{min}-$s->{max} $s->{stdv}; $s->{expect} $s->{delta}]\n";
    }
}

sub dump_days {
    my $g = shift;

    $g->readsummary( 'days', $g->{hours_nmax} );

    print "Daily:\n";
    foreach my $s ( @{ $g->{samples} } ){
	print "\t", scalar( localtime $s->{time} ),
	"  $s->{flag} $s->{ave} \t[$s->{ns} $s->{min}-$s->{max} $s->{stdv}]\n";
    }
}

sub dump_head {
    my $g = shift;

    print "Header:\n";
    print "\tLast_T: ", scalar(localtime $g->{lastt} ), "\n";

    print "\tSamples: CUR=$g->{sampl_index}\tN=$g->{sampl_count}\tMAX=$g->{sampl_nmax}\n";
    print "\tHourly:  CUR=$g->{hours_index}\tN=$g->{hours_count}\tMAX=$g->{hours_nmax}\n";
    print "\tDaily:   CUR=$g->{days_index}\tN=$g->{days_count}\tMAX=$g->{days_nmax}\n";

    print "\tCur Hr:  N=$g->{hours_nsamp}, MIN=$g->{hours_min}, MAX=$g->{hours_max}\n";
    print "\t         F=$g->{hours_flags}, S=$g->{hours_sigma}, S2=$g->{hours_sigm2}\n";

    print "\tCur Dy:  N=$g->{days_nsamp}, MIN=$g->{days_min}, MAX=$g->{days_max}\n";
    print "\t         F=$g->{days_flags}, S=$g->{days_sigma}, S2=$g->{days_sigm2}\n";
}

sub error {
    die @_;
}
