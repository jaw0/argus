\#!/usr/local/bin/perl
# -*- perl -*-

# Copyright (c) 2005 by Jeff Weisberg
# Author: Jeff Weisberg <jaw @ tcp4me.com>
# Created: 2005-Feb-05 20:05 (EST)
# Function: find services using the most resources
#
# $Id: findhogs.pl,v 1.1 2011/10/29 15:36:13 jaw Exp $

use lib('__LIBDIR__');	# adjust me
use Getopt::Std;
use Argus::Ctl;
require "conf.pl";

getopts('c:t:');

my $TOP = $opt_t || 10;
my @srvc;
my %stats;
my @params = qw(reads writes timeouts inits shuts timefs);

# connect to argus
$argusd = Argus::Ctl->new( ($opt_c || "$datadir/control"),
			   retry  => 0,
			   encode => 1 );

exit -1 unless $argusd && $argusd->connectedp();

# get list of all services
$s = $argusd->command( func   => 'getchildrenparam',
		       object => 'Top',
		       param  => 'type' );

foreach my $x (keys %$s){
    next unless $s->{$x} eq 'Service';
    push @srvc, $x;
}

# get various params
foreach my $p (@params){
    my $st = $argusd->command( func   => 'getchildrenparam',
			       object => 'Top',
			       param  => "bios::$p" );

    foreach my $o (@srvc){
	$stats{$o}{$p}   = $st->{$o} || 0;
	$stats{$o}{all} += $st->{$o};
    }
}

# list top 10

@srvc = sort { $stats{$b}{all} <=> $stats{$a}{all} } @srvc;

for (1..$TOP){
    my $o = shift @srvc;
    last unless $o;

    print "$o\n";
    foreach my $p (@params){
	print "\t$p:  \t$stats{$o}{$p}\n";
    }
    print "\n";
}


exit;

