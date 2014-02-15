#!/usr/local/bin/perl
# -*- perl -*-

# Copyright (c) 2003 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2003-May-25 10:57 (EDT)
# Function: re-lookup hostnames
#
# $Id: resolv.pl,v 1.1 2003/05/27 21:10:43 jaw Exp $

use lib('__LIBDIR__');
use ArgusCtl;

$argusd = ArgusCtl->new( "$datadir/control",
			 encode => 1 );

my $tcp = $argusd->command( func   => 'getchildrenparam',
			    param  => 'tcp::hostname',
			    object => 'Top',
			    );
my $udp = $argusd->command( func   => 'getchildrenparam',
			    param  => 'udp::hostname',
			    object => 'Top',
			    );
my $tcp = $argusd->command( func   => 'getchildrenparam',
			    param  => 'ping::hostname',
			    object => 'Top',
			    );
