# -*- perl -*-

# Copyright (c) 2010 by Jeff Weisberg
# Author: Jeff Weisberg <jaw @ tcp4me.com>
# Created: 2010-Aug-31 20:27 (EDT)
# Function: 
#
# $Id: DARP::MonEl.pm,v 1.7 2012/10/27 03:12:18 jaw Exp $

package DARP::MonEl;
use strict qw(refs vars);
use vars qw($doc);

my %tag_mode_dfl =
(
 distributed => 'SLAVES',
 failover    => '*',
 redundant   => '*',
 );


$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [],
    versn => '3.7',
    html  => 'darp',
    methods => {},

    fields => {
      darp::darp_mode => {
	  descr => 'what DARP mode to use',
	  attrs => ['config', 'inherit'],
	  vals  => ['none', 'failover', 'distributed', 'redundant'],
	  default => 'none',
      },
      darp::darp_tags => {
	  descr => 'list of DARP tags specfying who should monitor the service',
	  attrs => ['config', 'inherit'],
      },
      darp::slaves_keep_state => {
          descr => 'which servers keep status files',
          attrs => ['config', 'inherit'],
          default => '*',
      },
      darp::slaves_send_notifies => {
          descr => 'which servers should send notifications',
          attrs => ['config', 'inherit'],
          default => '*',
      },
      darp::master_notif_gravity => {
          descr => 'multi-master gravitation method',
          attrs => ['config', 'inherit'],
      },

      darp::url          => {},
      darp::tags     	 => {},
      darp::i_keep_state => {},
      darp::i_send_notif => {},
      darp::send_notif_tags => {},

    },
};


sub init {
    my $me = shift;
    my $cf = shift;

    $me->init_from_config( $cf, $doc, 'darp' );
    $me->{darp}{darp_tags} ||= $tag_mode_dfl{ $me->{darp}{darp_mode} };

    my @tags = $me->taglist( $me->{darp}{darp_tags} );

    $me->{darp}{tags}{$_} = 1 foreach @tags;
    $me->{darp}{darp_tags} = join ' ', sort @tags;

    # if it is not monitored here, what url should we use?
    if( !$me->monitored_here() ){
        my $t = (keys %{$me->{darp}{tags}})[0];
        my($d) = grep { $t eq $_->{name} } @{ $DARP::info->{all} };
        $me->{darp}{url} = $d->{darpc}{remote_url} if $d && $d->{darpc} && $d->{darpc}{remote_url};
    }

    if( $DARP::info && $DARP::info->{tag} ){
	my $self = $DARP::info->{tag};

	@tags = $me->taglist( $me->{darp}{slaves_keep_state} );
	$me->{darp}{i_keep_state} = 1 if grep { $self eq $_ } @tags;

	@tags = $me->taglist( $me->{darp}{slaves_send_notifies} );
	$me->{darp}{i_send_notif} = 1 if grep { $self eq $_ } @tags;
	$me->{darp}{send_notif_tags}{$_} = 1 foreach @tags;

    }else{
	# DARP not enabled
	$me->{darp}{i_keep_state} = 1;
	$me->{darp}{i_send_notif} = 1;
    }

    $me->MonEl::init( $cf, @_ );

    $me;
}


sub url {
    my $me = shift;
    my @param = @_;
    my $n = $me->filename();

    my $base = '__BASEURL__';
    my($func) = $param[0] =~ /func=(.*)/;

    # if the object is not monitored on this server, rewrite urls

    if( $func =~ /^(graph|graphpage)$/ ){
        my $dgl = ::topconf('darp_graph_location');
        my $dmo = $DARP::mode;
        my $glo ;

        # where is graph data?
        if( ::topconf('darp_graph_location') eq $DARP::mode ){
            $glo = 'here';
            # here - nop
        }elsif( $DARP::mode eq 'master' ){
            # on the slave
            $glo = 'slave';
            $base = $me->{darp}{url} if $me->{darp}{url};
        }else{
            # on the master
            $glo = 'master';
            $base = $DARP::info->{masters}[0]{darps}{remote_url} if $DARP::info->{masters}[0]{darps}{remote_url};
        }
    }

    if( $func =~ /^(checknow|override|rmoverride)$/ ){
        $base = $me->{darp}{url} if $me->{darp}{url};
    }

    return join(';', "$base?object=$n", @param);
}

sub stats_load {
    my $me = shift;

    return unless $me->{darp}{i_keep_state};
    $me->MonEl::stats_load( @_ );
}

sub stats_save {
    my $me = shift;

    return unless $me->{darp}{i_keep_state};
    $me->MonEl::stats_save( @_ );
}

sub notify {
    my $me = shift;

    return unless $me->{darp}{i_send_notif};

    my $ngrav = $me->{master_notif_gravity};

    if( $ngrav eq 'low' || $ngrav eq 'high' ){
	my $self = $DARP::info->{tag};

	# be semi-pessimistic, rather send 2 than none
	my %candidate;
	if( $DARP::info && $DARP::info->{all} ){
	    foreach my $d ( @{ $DARP::info->{all} } ){
		my $t = $d->{name};
		next unless $me->{darp}{send_notif_tags}{$t};

		push @{$candidate{$t}}, $d;
	    }
	}

	T: foreach my $t (keys %candidate){
	    # all connections to T must be up in S+M mode
	    foreach my $d ( @{$candidate{$t}} ){
		next T if $d->{status} ne 'up';
		next T if $d->{srvc} && $d->{srvc}{status} ne 'up';
	    }

	    # T looks good, is it better than me?
	    if( $ngrav eq 'low' ){
		return if $t lt $self;
	    }else{
		return if $t gt $self;
	    }
	}
    }

    $me->MonEl::notify( @_ );

}

sub _i_am_master {
    return $DARP::info->{slaves} && @{$DARP::info->{slaves}};
}

# does this get monitored here?
sub monitored_here {
    my $me = shift;

    my $mode = $me->{darp}{darp_mode} || 'none';
    my $self = $DARP::info->{tag};

    # check if:
    # mode = none
    # mode = dist|redund & tags{self}
    # mode = fail & tags{self} & ( self=master | master=down )

    # does this server run this test?
    return 1 unless $DARP::info && $DARP::info->{tag};
    return 1 if $mode eq 'none';
    return 1 if $mode eq 'distributed' && $me->{darp}{tags}{$self};
    return 1 if $mode eq 'redundant'   && $me->{darp}{tags}{$self};

    if( $mode eq 'failover' && $me->{darp}{tags}{$self} ){
	# I am master | all masters down

        return 1 if _i_am_master();

        my $upp;
        foreach my $m ( @{$DARP::info->{masters}} ){
            $upp = 1 if $m->{status} eq 'up';
        }
        return 1 unless $upp; # none are up
    }

    return undef;
}

sub taglist {
    my $me   = shift;
    my $tags = shift;
    my %tags;

    foreach my $t ( split /\s+/, $tags ){

	if( $t eq '*' ){
	    foreach my $s ( @{$DARP::info->{all}} ){
		my $t = $s->{name};
		$tags{$t} = 1;
	    }
	}
	elsif( $t eq 'SLAVES' ){
	    foreach my $s ( @{$DARP::info->{slaves}} ){
		my $t = $s->{name};
		$tags{$t} = 1;
	    }

	    # slaves includes me, if I have masters
	    $tags{$DARP::info->{tag}} = 1
		if @{ $DARP::info->{masters} };
	}
	elsif( $t eq 'MASTERS' ){
	    foreach my $s ( @{$DARP::info->{masters}} ){
		my $t = $s->{name};
		$tags{$t} = 1;
	    }

	    # masters includes me, if I have slaves
	    $tags{$DARP::info->{tag}} = 1
		if @{ $DARP::info->{slaves} };
	}
	elsif( $t eq 'LOCAL' ){
            # on the servers that monitor
            # (not for specifying which hosts monitor)
	    foreach my $t ( keys %{$me->{darp}{tags}} ){
		$tags{$t} = 1;
	    }
	}

	else{
	    $tags{$t} = 1;
	}
    }

    keys %tags;
}

sub override_set {
    my $me = shift;

    my $r = $me->MonEl::override_set(@_);
    send_master_overrides();
    return $r
}

sub override_remove {
    my $me = shift;

    my $r = $me->MonEl::override_remove(@_);
    send_master_overrides();
    return $r;
}

sub send_master_overrides {

    my @oo = keys %MonEl::inoverride;

    my $n = 1;
    my @send = map { ($n++, $_) } @oo;

    foreach my $m ( @{ $DARP::info->{masters}} ){
        next unless $m->{darps}{state} eq 'up';

        $m->debug( "DARP Slave - sending override list to '$m->{tag}' @send" );
        $m->send_command( 'darp_override_list',
                          count	=> scalar(@oo),
                          @send,
                         );
    }
}

sub about_more {
    my $me = shift;
    my $ctl = shift;

    $me->more_about_whom($ctl, 'darp');
}



################################################################
# initialize
sub enable {
    no strict;
    foreach my $p (qw(Group Service Alias)){
	unshift @{ "${p}::ISA" }, __PACKAGE__;
    }

    Cron->new(
        freq => 900,
        text => 'DARP override sync',
        func => \&send_master_overrides,
       );

}
################################################################
Doc::register( $doc );


1;
