# -*- perl -*-

# Copyright (c) 2003 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2003-Jan-23 21:23 (EST)
# Function: Distributed Argus Redundancy Protocol
#
# $Id: DARP.pm,v 1.33 2012/09/29 21:23:01 jaw Exp $

package DARP;
@ISA = qw(Configable);

BEGIN {
    eval {
	require Digest::MD5;
	require Digest::HMAC;

	$::HAVE_DARP = 1;
    };
}

use DARP::Conf;
use DARP::Master;
use DARP::Slave;
use DARP::Service;
use DARP::MonEl;
use DARP::Watch;
use Argus::Encode;

use strict qw(refs vars);
use vars qw(@ISA $doc $mode $info);

$mode  = 'disabled';
$info  = undef;

$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [],
    versn => '3.3',
    html  => 'darp',
    methods => {},
    conf => {
	quotp => 1,
	bodyp => 1,
    },
    fields => {
	tag     => {},
	slaves  => {},
	masters => {},
	debug  => {
	    descr => 'send all sorts of gibberish to the log',
	    attrs => ['inherit', 'config'],
	},
	port => {
	    descr => 'TCP port to listen on for slave connections',
	    attrs => ['config'],
	    default => 2055,	# XXX not officially assigned
	},
	timeout => {
	    descr => 'maximum time to wait for input from slave',
	    attrs => ['config'],
	    default => 120,
	},

    },
};

sub config {
    my $me = shift;
    my $cf = shift;

    $me->{tag} = $me->{name};
    $me->init_from_config( $cf, $doc, '' );
    $me->cfcleanup();

    $me->{status} = 'up';
    $info = $me;

    $me->{masters} ||= [];
    $me->{slaves}  ||= [];

    $me->{all} = [ $me, @{$me->{masters}}, @{$me->{slaves}} ];

    if( @{$me->{masters}} && @{$me->{slaves}} ){
	# It's a lot like life
	# This play between the sheets
	# With you on top
	# And me underneath
	# Forget all about equality
	# Let's play master and servant
	#   -- Depeche Mode, Master and Servant
	::loggit( "DARP running in mixed master/slave mode", 0 );
	$mode = 'master/slave';
    }
    elsif( @{$me->{masters}} ){
	# We cannot all be masters
	#   -- Shakespeare, Othello
	::loggit( "DARP running in slave mode", 0 );
	$mode = 'slave';
    }
    elsif( @{$me->{slaves}} ){
	# Let every man be master
	#   -- Shakespeare, Macbeth
	::loggit( "DARP running in master mode", 0 );
	$mode = 'master';
    }
    else{
	# I climbed a high rock to reconnoitre,
	# but could see no sign neither of man nor cattle,
	# only some smoke rising from the ground.
	#   -- Homer, Odyssey

	# no master specified, no slaves specified, wtf?
	$cf->warning( "DARP enabled but not configured" );
	$mode = 'enabled';
    }

    DARP::Master->create( $me ) if @{$me->{slaves}};
    DARP::Service->enable();
    DARP::MonEl->enable();

    $me;
}

sub unique { 'DARP' };

sub gen_confs {

    my $r = '';
    if( $info ){
	$r = "\n" . $info->gen_conf();
    }
    $r;
}


################################################################

sub cmd_darpstatus {
    my $ctl = shift;
    my $param = shift;

    $ctl->ok();

    if( $DARP::info->{tag} ){
	foreach my $d ( @{$info->{all}} ){
	    my $t = encode( $d->{name} );
	    $ctl->write( "$t:\t$d->{type}:$d->{status}\n" );
	}
	$ctl->final();
    }else{
	$ctl->bummer(500, 'DARP not enabled');
    }
}

sub cmd_darp_tag {
    my $ctl = shift;

    if( $DARP::info->{tag} ){
	$ctl->ok();
	my $t = encode($DARP::info->{tag});
	$ctl->write( "self: $t\n" );
	$ctl->final();
    }else{
	$ctl->bummer(500, 'DARP not enabled');
    }
}


sub cmd_darp_master_info {
    my $ctl = shift;
    my $param = shift;

    $ctl->ok();

    my $mytag  = $DARP::info->{tag};
    my $passok = $param->{cookie} eq $::COOKIE;

    if( $mytag ){
	foreach my $d ( @{$DARP::info->{masters}} ){
	    my $tag  = encode($d->{name});
	    my $addr = encode($d->{ip}{hostname});
            my $port = $d->{tcp}{port};
            my $user = encode($d->{darps}{username} || $mytag );
            my $pass = $passok ? encode($d->{darps}{secret}) : '-';

	    $ctl->write( "$tag: $addr $port $user $pass\n" );
	}
	$ctl->final();
    }else{
	$ctl->bummer(500, 'DARP not enabled');
    }
}

################################################################
Doc::register( $doc );
Control::command_install( 'darp_status',     \&cmd_darpstatus,     "show darp status summary" );
Control::command_install( 'darp_mytag',      \&cmd_darp_tag,       "what is my tag" );
Control::command_install( 'darp_masters',    \&cmd_darp_master_info, "list masters info" );

1;
