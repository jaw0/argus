#!/usr/local/bin/perl
# -*- perl -*-

# Copyright (c) 2007 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2007-Feb-19 09:02 (EST)
# Function: argus run-time-configure
#
# $Id: rtc.pl,v 1.5 2007/12/31 01:24:35 jaw Exp $


# add configs to already running argus
# config files must contain groups, services
# does not handle all sorts of things...

use lib('__LIBDIR__');
use Socket;
use Getopt::Std;
use Argus::Ctl;
use Argus::Encode;
use Getopt::Std;
require "conf.pl";
use strict;
my %opt;
getopts('cnv', \%opt);

# connect to Argus
my $argusd = Argus::Ctl->new( ($opt{c} || "$::datadir/control"),
			 who    => 'argusctl',
			 retry  => 0,
			 encode => 1 ) unless $opt{n};

unless( $opt{n} ){
    exit -1 unless $argusd && $argusd->connectedp();
}

# read config file
readconf(undef, undef);


sub readconf {
    my $func  = shift;
    my $level = shift;

    my( $haveblocks, $havegrps, $srvcs, $objname, %param );
    # read params
    # maybe create object
    # read children

    while(<>){
	chop;
	s/#.*//;
	s/^\s*//;
	s/\s*$//;
	next unless $_;
	last if /^\s*\}/ && $func;

	if( /\\$/ ){
	    s/\\$//;
	    $_ .= <>;
	    redo;
	}

	if( /^(method|resolv|darp)\b/i ){
	    my $l = $_;
	    my $o = $1;
	    
	    if( $havegrps || $level ){
		warn "ERROR line $.: $1 not permitted here\n";
		eat_block();
		next;
	    }


	    $l = "Service $l" if $l =~ /^resolv/i;
	    my $type = readblock($objname, $l, $level);
	    $haveblocks = 1;
	    next;
	}
	if( /^(slave|master)\b/i ){
	    my $l = $_;
	    my $o = $1;
	    
	    if( lc($level) ne 'darp' ){
		warn "ERROR line $.: $1 not permitted here\n";
		eat_block();
		next;
	    }

	    unless( $haveblocks ){
		# create object
		if( $func ){
		    $objname = $func->( \%param );
		}
	    }
	    
	    # XXX ?
	    $l = "Service $l" if $l =~ /^resolv/i;
	    my $type = readblock($objname, $l, $level);
	    $haveblocks = 1;
	    next;
	}
	
	if( /^(group|host|service|cron)\b/i ){
	    my $l = $_;
	    unless( $haveblocks ){
		# create object
		if( $func ){
		    $objname = $func->( \%param );
		}
	    }

	    my $type = readblock($objname, $l, $level);
	    $haveblocks = $havegrps = 1;
	    $srvcs ++ if $type =~ /service/i;
	    next;
	}

	elsif( /:/ ){
	    if( $haveblocks ){
		warn "ERROR line $.: additional data not permitted here\n";
		next;
	    }
	    
	    my($k, $v) = split /:\s*/, $_, 2;
	    $param{"config::$k"} = $v;
	}
	else{
	    # syntax error
	    warn "ERROR: line $.: syntax error ($_)\n";
	    eat_block() if /\{$/;
	}
    }

    if( $func && !$haveblocks ){
	# create object
	$objname = $func->( \%param );
    }


    if( $objname && $srvcs ){
	# or better: jiggle-lightly
	print STDERR "jiggling: $objname\n" if $opt{v};
	$argusd->command( func   => 'jiggle',
			  object => $objname ) unless $opt{n}
    }
}

sub readblock {
    my $parent = shift;
    my $line   = shift;
    my $level  = shift;

    my($type, $name, $open) = $line =~ /(\S+)\s+(.*[^\{\s]+)(\s*\{)?/;
    $type =~ s/:$//;
    $name =~ s/\"(.*)\"/$1/;

    my $create = sub {
	my $param = shift;
	print STDERR "creating $type($name)\n" if $opt{v};
	return if $opt{n};
	my $r = $argusd->command( func   => 'add_object',
				  type   => $type,
				  name   => $name,
				  parent => ($parent || 'Top'),
				  jiggle => 0, # do it at group end (see above)
				  %$param );
	
	if( $r->{resultcode} == 200 ){
	    # return object name
	    return $r->{object};
	}else{
	    # error
	    warn "ERROR: line $.: could not create $type($name): $r->{resultmsg}\n";
	}
    };

    if( $open ){
	readconf( $create, $type );
    }else{
	$create->();
    }
    
    return $type;
}


sub eat_block {
    while(<>){
	last if /\s*\}/;
    }
}

__END__

Conf: Params [ignored] Blocks [jiggle]
Block: TYPE NAME { Params [create] Blocks [jiggle] }

