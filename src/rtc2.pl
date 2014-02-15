#!/usr/local/bin/perl
# -*- perl -*-

# Copyright (c) 2007 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2007-Aug-26 16:06 (EDT)
# Function: 
#
# $Id$

use Getopt::Std;
use strict;
my %opt;
getopts('cnv', \%opt);

my %BLK =
(
 group		=> { parent => ['top', 'group'] },
 host		=> 'group'
 service	=> { parent => ['top', 'group'] },
 cron		=> { parent => ['group', 'service'] },
 method		=> { parent => ['top'] },
 resolv		=> { parent => ['top'] },
 darp		=> { parent => ['top'] },
 slave		=> { parent => ['darp'] },
 master	        => { parent => ['darp'] },
 );



sub V {
    my $msg = shift;
    return unless $opt{v};
    print STDERR "$msg\n";
}


# read config file
readconf(undef, undef);


