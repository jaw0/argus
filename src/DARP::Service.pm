# -*- perl -*-

# Copyright (c) 2003 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2003-Dec-03 17:44 (EST)
# Function: override various Service methods
#
# $Id: DARP::Service.pm,v 1.38 2012/10/02 01:38:25 jaw Exp $

package DARP::Service;
use Argus::Color;
use Argus::Encode;
use strict qw(refs vars);
use vars qw($doc);


$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [],
    versn => '3.3',
    html  => 'darp',
    methods => {},

    fields => {
      darp::darp_gravity => {
	  descr => 'multi monitor decision algorithm',
	  attrs => ['config', 'inherit'],
	  vals  => ['up', 'down', 'vote', 'self', 'ietf'],
	  default => 'down',
      },
      darp::darp_on_web => {
	  descr => 'display DARP data on web page',
	  attrs => ['config', 'inherit', 'bool'],
	  default => 'yes',
      },

      darp::statuses => {},
      darp::synced   => { descr => 'status has been synchronized with master' },

    },
};

sub init {
    my $me = shift;
    my $cf = shift;

    $me->init_from_config( $cf, $doc, 'darp' );

    $me->{darp}{statuses}{ $DARP::info->{tag} } = $me->{status}
    if $DARP::info && $DARP::info->{tag};

    $me->Service::init( $cf, @_ );	# MonEl::init

    $me;
}

sub pre_start_check {
    my $me = shift;

    $me->debug( 'DARP pre-start check' );

    # does this server run this test?
    my $test = $me->monitored_here();

    if( $test ){
	$me->Service::pre_start_check( @_ );
    }else{
	$me->debug( 'DARP - skipping test' );
	$me->reschedule();
    }
}

# sub done {
#     my $me = shift;
#
#     $me->debug( 'DARP done' );
#     $me->Service::done( @_ );
# }

sub update {
    my $me = shift;
    my $st = shift;
    my $sv = shift;

    unless( $DARP::info && $DARP::info->{tag} ){
	# handle common case, and leave
	return $me->Service::update( $st, $sv, @_ );
    }

    $sv ||= ($st eq 'up') ? 'clear' : $me->{severity};
    my $aggrst = $st;
    my $aggrsv = $sv;
    my $aggros = $st;
    my $mode   = $me->{darp}{darp_mode} || 'none';
    my $grav   = $me->{darp}{darp_gravity};
    my $mytag  = $DARP::info->{tag};
    my $change = 0;	# has local status changed
    my $hasov  = ($me->{override} || $me->{anc_in_ov}) ? 1 : 0;

    $change = 1 if $st && $me->{darp}{statuses}{$mytag}   ne $st;
    $change = 1 if $sv && $me->{darp}{severities}{$mytag} ne $sv;
    $change = 1 if $hasov != $me->{darp}{prev_local_override};

    # update my own status
    $me->{darp}{statuses}{$mytag}    = $st  if $st;
    $me->{darp}{severities}{$mytag}  = $sv  if $sv;
    $me->{darp}{prev_local_override} = $hasov;

    if( $st && !$me->monitored_here() ){
        ::sysproblem("status update '$st' on non-monitored object " . $me->unique());
        return;
    }

    $me->debug("darp update: $mytag, $mode, grav=$grav, status=$st, sever=$sv");


    # calculate aggregate status
    # failover+none  => status = my status
    # gravity = self => status = my status
    # no slaves      => status = my status

    if( $DARP::info->{slaves} && @{$DARP::info->{slaves}}
	&& ($mode eq 'distributed' || $mode eq 'redundant')
	&& $grav ne 'self' ){

    	# check gravity, mode, status - calc new status

	my( %stat, $minsev, $maxsev );
	if( $grav eq 'ietf' ){

	    # look at me and my slaves, skip those not up at the moment,
	    # nb: masters will aways be unk unless s+m
	    foreach my $d ( $DARP::info, @{ $DARP::info->{slaves} } ){
		my $t = $d->{name};
		next unless $me->{darp}{tags}{$t};
		next unless $d->{status} eq 'up';

		my $s  = $me->{darp}{statuses}{$t} || 'unk';
		$stat{$s} ++;

                my $sv = $me->{darp}{severities}{$t};
                if( $sv ne 'clear' ){
                    $minsev = $sv if !$minsev || $MonEl::severity_sort{$sv} < $MonEl::severity_sort{$minsev};
                    $maxsev = $sv if !$maxsev || $MonEl::severity_sort{$sv} > $MonEl::severity_sort{$maxsev};
                }
	    }
	}else{
            # look at everyone configured to monitor
	    foreach my $t ( keys %{ $me->{darp}{tags} } ){
		my $s = $me->{darp}{statuses}{$t} || 'unk';
		$stat{$s} ++;

                my $sv = $me->{darp}{severities}{$t};
                if( $sv ne 'clear' ){
                    $minsev = $sv if !$minsev || $MonEl::severity_sort{$sv} < $MonEl::severity_sort{$minsev};
                    $maxsev = $sv if !$maxsev || $MonEl::severity_sort{$sv} > $MonEl::severity_sort{$maxsev};
                }
	    }
	}

        ($aggrst, $aggros, $aggrsv) = aggr_status( $grav, \%stat, $minsev, $maxsev, $aggrsv );
    }

    # NB: remote might not provide severity, try to avoid severity flap.
    if( $aggrst eq 'down' ){
	$aggrsv = $me->{severity} if $aggrsv eq 'clear';
    }else{
	$aggrsv = 'clear';
    }

    $me->debug("darp_update aggregate: $aggrst, $aggros, $aggrsv");

    # update self first, then masters
    $me->Service::update( $aggrst, $aggrsv, $aggros );

    $me->darp_transition($change);

}

sub transition {
    my $me = shift;

    foreach my $m ( @{ $DARP::info->{masters}} ){
        $me->{darp}{synced}{ $m->{tag} } = undef;
    }

    # if this is an "administrative" transition, send update
    $me->darp_transition(1) unless @_;

    $me->Service::transition(@_);
}

sub darp_transition {
    my $me = shift;
    my $change = shift;

    return unless $DARP::info->{masters};
    my $mode    = $me->{darp}{darp_mode} || 'none';
    return if $mode eq 'none';

    my $mytag   = $DARP::info->{tag};
    my $localst = $me->{darp}{statuses}{$mytag};
    my $localsv = $me->{darp}{severities}{$mytag};

    $localst = 'override' if ($me->{override} || $me->{anc_in_ov}) && $localst ne 'up';

    foreach my $m ( @{ $DARP::info->{masters}} ){
        next unless $m;

        # NB: synced is set in DARP::Slave when we rcv a response
        $me->{darp}{synced}{ $m->{name} } = undef if $change;

        next unless $m->{darps}{state} eq 'up';
        next if $me->{darp}{synced}{ $m->{name} };

        # send the update to master

        # Masters, I have to tell a tale of woe,
        #   -- William Morris, The Earthly Paradise

        $me->debug( "DARP Slave - sending update to $m->{name} status=$localst/$localsv" );
        $m->debug(  "DARP Slave - sending update to $m->{name} status=$localst/$localsv" );

        $m->send_command( 'darp_update',
                          object   => $me->unique(),
                          status   => $localst,
                          severity => $localsv,
                         );
    }

}


sub aggr_status {
    my $grav   = shift;
    my $stat   = shift;
    my $minsev = shift;
    my $maxsev = shift;
    my $cursev = shift;

    my($aggrst, $aggros, $aggrsv);

    if( $grav eq 'down' ){
        my $dn = $stat->{down} || $stat->{override} || !$stat->{up};
        $aggrst = $dn ? 'down' : 'up';
        $aggrsv = $dn ? $maxsev || $cursev : 'clear';
        $aggros = 'override' if $stat->{override} && !$stat->{down};

    }elsif( $grav eq 'up' ){
        my $up = $stat->{up} || (!$stat->{down} && !$stat->{override});
        $aggrst = $up ? 'up' : 'down';
        $aggrsv = $up ? 'clear' : ($minsev || $cursev);
        $aggros = 'override' if $stat->{override} && !$up;

    }elsif( $grav eq 'vote' || $grav eq 'ietf' ){
        my $up = $stat->{up} > $stat->{down} + $stat->{override};

        $aggrst = $up ? 'up' : 'down';
        $aggrsv = $up ? 'clear' : ($minsev || $cursev);
        $aggros = 'override' if $stat->{override} && ($stat->{override} >= $stat->{down}) && !$up;
    }

    return ($aggrst, $aggros, $aggrsv);
}

sub webpage {
    my $me   = shift;
    my $fh   = shift;
    my $topp = shift;

    $me->Service::webpage($fh, $topp);

    return unless $me->{darp};
    return unless $me->{darp}{darp_on_web};
    return unless $me->{darp}{tags};

    print $fh "<!-- start of darp web -->\n";
    print $fh "<HR>\n<B class=heading>DARP Info</B>\n<TABLE CLASS=DARP>\n";
    # print $fh "<TR><TD COLSPAN=2>mode</TD><TD>$me->{darp}{darp_mode}</TD></TR>\n";

    foreach my $d ( $DARP::info, @{$DARP::info->{slaves}} ){
	my $t = $d->{name};
	next unless $me->{darp}{tags}{$t};	# only those monitoring this object
	my $s  = $me->{darp}{statuses}{$t}   || 'unknown';
        my $sv = $me->{darp}{severities}{$t} || 'critical';
	my $c  = web_status_color($s, $sv, 'back' );
	next if $d->{darpc} && $d->{darpc}{hidden};

	my $l = $d->{darpc}{label} || $t;

	# embolden this host
	$l = "<B>$l</B>" if $t eq $DARP::info->{tag};

	# make link if url configured
	if( $d->{darpc} && $d->{darpc}{remote_url} ){
	    $l = "<A HREF=\"$d->{darpc}{remote_url}?object="
		. $me->filename() . ";func=page\">$l</A>";
	}

	print $fh "<TR><TD>$l </TD><TD>status</TD><TD BGCOLOR=\"$c\">$s</TD></TR>\n";
    }

    print $fh "</TABLE>\n";
    print $fh "<!-- end of darp web -->\n";

}

sub about_more {
    my $me = shift;
    my $ctl = shift;

    $me->Service::about_more($ctl);
    $me->more_about_whom($ctl, 'darp', 'darp::statuses', 'darp::synced', 'darp::severities');
}

################################################################
# graph data tagging
sub graph_tag {
    my $me = shift;

    return unless $DARP::info;
    return unless $DARP::info->{tag};
    return unless $me->{darp};
    return unless $me->{darp}{darp_mode};
    return if $me->{darp}{darp_mode} eq 'none';

    return $DARP::info->{tag};
}

# [obj, label, tag]...
sub graphlist {
    my $me = shift;

    return () unless $me->{graph};

    my $dgl   = ::topconf('darp_graph_location');
    my $mytag = $DARP::info->{tag};
    my @tags  = keys %{$me->{darp}{tags}};

    # just my local graph, same as non-darp:
    my @l = ({ obj => $me, file => $me->pathname(), label => '', tag => $mytag, link => encode($me->unique()) });

    # on master, dgl = master => all tags
    # on master, dgl = slave  => myself | none
    # on slave,  dgl = master => none
    # on slave,  dgl = slave  => myself | none

    if( $DARP::mode eq 'slave' ){
        if( $dgl eq 'master' ){
            return;
        }else{
            if( $me->{darp}{tags}{$mytag} ){
                return @l;
            }
            return;
        }
    }
    # else mode eq master

    if( $dgl eq 'slave' ){
        # on master, dgl = slave  => myself | none
        if( $me->{darp}{tags}{$mytag} ){
            return @l;
        }
        return;
    }

    # on master, dgl = master

    if( @tags > 1 ){
        # slave graphs
        @l = map { {
            obj   => $me,
            file  => $me->pathname("$_:"),
            label => '@'.$_,
            tag   => $_,
            link  => encode($me->unique()) . ";tag=$_",
        } } grep {$_ ne $mytag } @tags;

        # plus my graph
        unshift @l, {
            obj   => $me,
            file  => $me->pathname(),
            label => '@'.$mytag,
            tag   => $mytag,
            link  => encode($me->unique()) . ";tag=$mytag",
        } if $me->{darp}{tags}{$mytag};

        return @l;
    }elsif( $me->{darp}{tags}{$mytag} ){
        # only monitored here
        return @l;
    }else{
        # not monitored here => return slave graphs
        return map { {
            obj   => $me,
            file  => $me->pathname("$_:"),
            label => '',
            tag   => $_,
            link  => encode($me->unique()) . ";tag=$_",
        } } grep {$_ ne $mytag } @tags;
    }

}

################################################################
# initialize
sub enable {
    no strict;
    foreach my $srvc (qw(DataBase Self Ping Prog TCP UDP Argus::Compute)){
	unshift @{ "${srvc}::ISA" }, __PACKAGE__;
    }
}
################################################################
Doc::register( $doc );


1;
