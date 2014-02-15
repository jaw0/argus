# -*- perl -*-

# Copyright (c) 2003 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2003-Jan-23 21:57 (EST)
# Function: DARP Slave Client
#
# $Id: DARP::Slave.pm,v 1.31 2012/10/27 03:12:18 jaw Exp $

package DARP::Slave;
@ISA = qw(TCP);
use Argus::Encode;
BEGIN {
    eval {
	require Digest::MD5;
        Digest::MD5->import('md5_hex');
    };
}
use Socket;

# master "name" { ... }

use strict qw(refs vars);
use vars qw(@ISA $doc);

my $CHKTIME = 1800;	# be sure to check for master updates at least this often
my $fetching_p;

$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [qw(TCP Service BaseIO)],
    versn => '3.3',
    html  => 'darp',
    methods => {},
    conf => {
	quotp => 1,
	bodyp => 1,
    },
    fields => {
	tag    => {},
	status => {},

	debug => {
	    descr => 'send all sorts of gibberish to the log',
	    default => 'no',
	    attrs => ['config', 'inherit', 'bool'],	# normally, not inherited...
      },
      tcp::port => {
	  descr => 'TCP port',
	  attrs => ['config', 'inherit'], 		# normally, not inherited...
	  default => 2055,				# XXX not officially assigned
      },
      darps::secret => {
	  descr => 'authentication secret',
	  attrs => ['config', 'inherit'],
      },
      darps::username => {
	  descr => 'alternate name to use',
	  attrs => ['config'],
      },
      darps::fetchconfig => {
	  descr => 'should slave fetch config from its master',
	  attrs => ['config', 'inherit', 'bool'],
	  default => 'yes',
      },
      darps::remote_url => {
	  descr => 'base URL of remote master',
	  attrs => ['config', 'inherit'],
      },

      darps::seqno => {},
      darps::state => {},
      darps::conflist => {},
      darps::currconf => {},
      darps::prevconf => {},
      darps::updtime => {}, # last config
      darps::kaptime => {}, # last keep alive
      darps::localconf => {},
    },
};

sub probe {
    my $name = shift;

    return ( $name =~ /^__DARP/ ) ? [ 4, \&config ] : undef;
}

sub config {
    my $me = shift;
    my $cf = shift;
    my $more = shift;

    # the excellent swineherd, who was so devoted a servant to his master
    #   -- Homer, Odyssey

    $me->init_from_config( $cf, $doc, '' );
    $me->init_from_config( $cf, $doc, 'tcp' );
    $me->init_from_config( $cf, $doc, 'darps' );

    return $cf->error( "DARP config not permitted outside of DARP block" )
	unless $more->{darp};
    return $cf->error( "DARP Master secret not specified" )
	unless $me->{darps}{secret};
    return $cf->error( "DARP Master tag not specified" )
	unless $more->{tag};

    if( $fetching_p && $me->{darp}{darp_mode} ){
	return $cf->warning( "fetchconfig permitted only on one master - disabling" );
	$me->{darps}{fetchconfig} = 0;
    }
    $fetching_p = 1 if $me->{darps}{fetchconfig};


    $me->{darps}{state} = 'down';
    $me->{darps}{updtime} = 0;
    $me->{darps}{kaptime} = $^T;

    # save local conf data
    for my $k (keys %{$::Top->{config}}){
	$me->{darps}{localconf}{$k} = $::Top->{config}{$k};
    }

    $me->{tag}  = $more->{tag};
    $me->{type} = 'Master';	# so we can gen_conf
    $me->{name} = $more->{master};

    $me->SUPER::config( $cf, $more );

    $me->{uname} = "Slave_$me->{tag}";
    $me->{darp}{darp_mode} = 'none';	# make sure we don't DARP DARP...

    bless $me;
}

sub readable {
    my $me = shift;
    my( $fh, $i, $l );

    # Speak to us, Master!  Speak to us!
    #   -- Monty Python, Life of Bryan

    $fh = $me->{fd};
    $i = sysread( $fh, $l, 8192 );

    if( $i ){
	$me->debug( "DARP Slave - read data $i" );
	$me->{tcp}{rbuffer} .= $l;
    }
    elsif( defined($i) ){
	# $i is 0 -> eof

	# The silent organ loudest chants
	# The master's requiem.
        #   -- Emerson, Dirge
	$me->debug( 'DARP Slave - read eof' );
	return $me->isdown( 'DARP Slave - remote closed the connection', 'eof' );
    }
    else{
	# $i is undef -> error

	# You must speak louder; my master is deaf
	#   -- Shakespeare, 2 King Henry IV
	return $me->isdown( "DARP Slave read failed: $!", 'read failed' );
    }

    $me->state( 'read' ) if $me->{tcp}{rbuffer};
    return unless defined $me->{fd};

    $me->settimeout( $me->{srvc}{timeout} );
    $me->wantwrit(0) unless $me->{tcp}{wbuffer};

}

sub writable {
    my $me = shift;

    # That my master, being scribe, to himself should write the letter?
    #   -- Shakespeare, Two Gentlemen of Verona
    $me->debug( 'DARP Slave write' );

    if( $me->{srvc}{state} eq 'connecting' ){
	my $fh = $me->{fd};
	my $i = unpack('L', getsockopt($fh, SOL_SOCKET, SO_ERROR));
	if( $i ){
	    $! = $i;
	    # QQQ, should I try to sort out errors, down on some, sysproblem on others?
	    return $me->isdown( "DARP connect failed: $!", 'connect failed' );
	}
	# Thou art my master
	#   -- Dante, Divine Comedy
	$me->debug( 'DARP Slave - connected' );
	$me->{srvc}{state} = 'connected';
	$me->state( 'connected' );
    }

    if( $me->{tcp}{wbuffer} ){
	my( $b, $i, $l, $fh );

	$fh = $me->{fd};
	$b = $me->{tcp}{wbuffer};
	$l = length($b);
	# And I said unto my master:
	#   -- Genesis 24:39
	$i = syswrite( $fh, $b, $l );
	if( defined $i ){
	    $me->debug( "DARP Slave - wrote $i bytes of $l" );
	}else{
	    return $me->isdown( "DARP Slave write failed: $!", 'write failed' );
	}
	$b = substr( $b, $i, $l );
	$me->{tcp}{wbuffer} = $b;
    }

    $me->settimeout( $me->{srvc}{timeout} );
    $me->wantwrit(0) unless $me->{tcp}{wbuffer};
    $me->wantread(1);

}

sub done {
    my $me = shift;

    $me->{darps}{state} = 'down';
    $me->{darps}{seqno} = 0;
    $me->{tcp}{wbuffer} = undef;
    $me->debug( "done" );
    $me->SUPER::done();
}

sub timeout {
    my $me = shift;

    if( $me->{darps}{state} eq 'up' && ! $me->{tcp}{wbuffer} ){
	# connection is idle - push down a keepalive
	$me->ping();
	$me->settimeout( $me->{srvc}{timeout} );
    }else{
	# I heard no letter from my master
	#   -- Shakespeare, Cymbeline
	$me->SUPER::timeout();
    }
}

sub ping {
    my $me = shift;

    $me->debug( 'DARP Slave - sending keepalive');

    if( $me->{darps}{fetchconfig} ){
	$me->send_command( 'getparam', param => 'definedattime', object => 'Top' );
    }else{
	$me->send_command( 'echo' );
    }
    $me->{darps}{kaptime} = $^T;
}

sub state {
    my $me = shift;
    my $st = shift;

    if( $st eq 'connected' ){
	$me->{darps}{state} = 'pre-auth';
	# the servant shall plainly say, I love my master
	#   -- Exodus, 21:5
	$me->debug( 'DARP Slave - sending pre-authentication request' );
	$me->send_command( 'auth', tag => ($me->{darps}{username} || $DARP::info->{tag}), method => 'APOP' );
	$me->{darps}{kaptime} = $^T;
	return;
    }

    if( $me->{darps}{state} eq 'pre-auth' && $st eq 'read' ){
	my( $r ) = $me->{tcp}{rbuffer} =~ /^\S+\s+(.*)/;

	return $me->isdown( "DARP Error - $r" )
	    unless $r =~ /^200/;
	$me->{tcp}{rbuffer} = undef;
	# APOP style auth
	my( $noise ) = $r =~ /(<.*>)/;
	my $digst = md5_hex( $noise . $me->{darps}{secret} );

	$me->{darps}{state} = 'auth';
	$me->debug( 'DARP Slave - sending authentication request' );
	$me->send_command( 'auth', tag => ($me->{darps}{username} || $DARP::info->{tag}),
			   secret => $digst, method => 'APOP' );
	return;
    }

    if( $me->{darps}{state} eq 'auth' && $st eq 'read' ){
	my( $r ) = $me->{tcp}{rbuffer} =~ /^\S+\s+(.*)/;

	return $me->isdown( "DARP Error - $r" )
	    unless $r =~ /^200/;
	$me->{tcp}{rbuffer} = undef;

	if( $me->{darps}{fetchconfig} ){
	    $me->debug( 'DARP Slave - fetching config list' );
	    $me->{darps}{state} = 'config-list';
	    $me->send_command( 'darp_list' );
	    $me->{darps}{updtime} = $^T;
	}else{
	    $me->debug( 'DARP Slave - active' );
	    $me->{darps}{state} = 'up';
	    $me->update( 'up' );
	}
	return;
    }

    if( $me->{darps}{state} eq 'config-list' && $st eq 'read' ){
	if( $me->{tcp}{rbuffer} =~ /\n\n/s ){
	    my( $r ) = $me->{tcp}{rbuffer} =~ /^\S+\s+(.*)/s;
	    $me->{tcp}{rbuffer} = undef;
	    return $me->isdown( "DARP Error - $r" )
		unless $r =~ /^200/;

	    $r =~ s/:\s+1$//mg;
	    my @lines = split /\n/, $r;
	    shift @lines; 		# remove response code

	    my $o = shift @lines;
	    $me->{darps}{prevconf} = $me->{darps}{currconf};
	    $me->{darps}{currconf} = undef;

	    if( $o ){
		# Tell me, my Master, tell me
		#   -- Dante, Divine Comedy
    		$me->debug( "DARP Slave - fetching config: $o" );
		$me->send_command( 'getconfigdata', object => $o, andmore => 1 );
		$me->{darps}{conflist} = [ @lines ];
		$me->{darps}{state} = 'config-fetch';
		$me->darp_fetchlist_hook() if $me->can('darp_fetchlist_hook');
	    }else{
		$me->debug( 'DARP Slave - list empty' );
		$me->conf_done();
		$me->debug( 'DARP Slave - active' );
		$me->{darps}{state} = 'up';
		$me->update( 'up' );
	    }
	}
	return;
    }

    if( $me->{darps}{state} eq 'config-fetch' && $st eq 'read' ){
	if( $me->{tcp}{rbuffer} =~ /\n\n/s ){
	    my( $r ) = $me->{tcp}{rbuffer} =~ /^\S+\s+(.*)/s;
	    $me->{tcp}{rbuffer} = undef;
	    return $me->isdown( "DARP Error - $r" )
		unless $r =~ /^200/;

	    # parse response
	    my( @lines, %param );
	    @lines = split /\n/, $r;
	    shift @lines;		# remove response code
	    foreach (@lines){
		s/\s*$//;
		s/^\s*//;
		my($k, $v) = split /\s*:\s+/, $_, 2;
		$param{lc($k)} = decode($v) if $k;
		# $me->debug( "DARP - rcvd config: '$k => $v'" );
	    }

	    my $name = $param{'::_uname'};
	    # RSN - support for name mapping

	    # keep track of objects
	    delete $me->{darps}{prevconf}{$name};
	    $me->{darps}{currconf}{$name} = 1;

	    # create the object
	    eval{
		$me->darp_config_obj_hook(\%param) if $me->can('darp_config_obj_hook');
		my $status = $param{"::=status"};
		my $sever  = $param{"::=severity"};
		delete $param{"::=status"};
		delete $param{"::=severity"};

		my $x = $MonEl::byname{$name};
		if( $x && ( $x->{definedattime} < ($param{definedattime} || $^T)
			    || $x->{transient}
			    || ($x->{definedinfile}!~ /^DARP/) ) # force replace local Top with remote Top
		    ){

		    $me->debug( "DARP - config: recycling $name" );
		    $x->recycle( 'cascade' );
		    $x = undef;
		}
		if( $x ){
		    $me->debug( "DARP - config: updating $name" );
		    # QQQ - should we warn if the status actually is different?
		}else{
		    my $cf = NullConf->new();
		    $me->debug( "DARP - config: creating $name" );

		    # for Top, copy local params.
		    if( $name eq 'Top' ){
			$param{"config::$_"} = $me->{darps}{localconf}{$_}
			    for keys %{$me->{darps}{localconf}};
		    }

		    eval {
			$x = MonEl::create_object( $cf, { %param,
						     definedinfile => "DARP\@$me->{name}",
						     notypos => 1 } );
                        $x->{darp_configured} = $^T;
			$x->loggit( msg => "Created Object $x->{name}",
				    tag => 'CREATE' ) unless $param{quiet};
		    };
		    if( $@ && ref $@ ){
			# create failed, (try to) create error object
			$x = MonEl::create_object( $cf, { %param,
						     type  => 'Error',
						     error => $@->{error},
						     definedinfile => "DARP\@$me->{name}",
						     notypos => 1 } );
			$x->loggit( msg => "Created ERROR Object",
				    tag => 'CREATE' ) unless $param{quiet};
		    }
		}

		if( $x ){
		    $x->{darp}{synced}{ $me->{name} } = undef;
		    # setting prev* prvents jiggle from sending notifications
		    $x->{status} = $x->{ovstatus} = $x->{prevstatus} = $x->{prevovstatus}
		    = $status if $status;
                    $x->{currseverity} = $sever if $sever;
		    # gets jiggled when we finish, below
		}
	    };
	    if( $@ ){
		# return $me->isdown( "DARP Error" );		# QQQ
	    }

	    # get config for next object
	    my $o = shift @{ $me->{darps}{conflist} };
	    if( $o ){
		$me->debug( "DARP Slave - fetching config: $o" );
		$me->send_command( 'getconfigdata', object => $o, andmore => 1 );
	    }else{
		# QQQ jiggle?
		$me->conf_done();
		$me->darp_configured_hook() if $me->can('darp_configured_hook');
		$me->debug( 'DARP Slave - active' );
		$me->{darps}{state} = 'up';
		$me->update( 'up' );
		my $top = $MonEl::byname{Top};
		if( $top ){
                    $top->{darp_configure_done} = $^T;
		    $top->jiggle();
		}else{
		    # something really bad has happened...
		    ::warning( 'Configuration failed' );
		    return $me->isdown( 'Configuration failed' );
		}
                DARP::MonEl::send_master_overrides();
	    }
	}
	return;
    }

    # misc read - should be a keepalive or update response
    if( $st eq 'read' ){
	while( $me->{tcp}{rbuffer} =~ /\n\n/s ){
	    my($a, $b) = $me->{tcp}{rbuffer} =~ /^(.*?)\n\n(.*)$/s;
	    $me->{tcp}{rbuffer} = $b;

	    my $rs = parse_response( $a );

	    if( $rs->{resultcode} == 200 && $rs->{param} eq 'definedattime' ){
		# keep alive timestamp

		if( $rs->{value} > $me->{darps}{updtime} ){
		    # drop connection
		    $me->{tcp}{rbuffer} = undef;
		    $me->debug( "master change detected - reseting" );
		    return $me->isup();
		}
	    }

	    if( $rs->{resultcode} == 200 && $rs->{param} eq 'darp_update' ){
		# sync successful
		my $x = $MonEl::byname{ $rs->{object} };
		if( $x ){
		    $x->{darp}{synced}{ $me->{name} } = $^T;
		}
	    }


	    # QQQ ?
	    # return $me->isdown( "DARP Error - $rs->{resultmsg}" )
	    # 	  unless $rs->{resultcode} == 200;
	}

	$me->ping() if( $^T - $me->{darps}{kaptime} > $CHKTIME );

	return;
    }

}

sub conf_done {
    my $me = shift;

    # perform config garbage collection
    # remove anything previously added, but not this time

    # reverse sort: services before their containing group
    foreach my $n (reverse sort keys %{ $me->{darps}{prevconf} }){
	delete $me->{darps}{prevconf}{$n};
	next if $n eq 'Top';
	my $x = $MonEl::byname{$n};
	next unless $x;

	$me->debug( "DARP $n no longer relevant, recycling" );

	$x->loggit( msg => "Recycling Object $n",
		    tag => 'DELETE' );

	$x->recycle();
    }
}

sub send_command {
    my $me    = shift;
    my $func  = shift;
    my %param = @_;
    my $w;

    return $me->isdown( '?' ) unless $me->{fd};

    $w = "GET / ARGUS/2.0\n";

    $param{func}  = $func;
    $param{hmac}  = ::calc_hmac($me->{darps}{secret},
                                %param, SEQNO => ++ $me->{darps}{seqno});

    foreach my $k (keys %param){
	my $v = $param{$k};
	next unless defined $v;
	$v = encode($v);
	$w .= "$k: $v\n";
    }
    $w .= "\n";

    $me->{tcp}{wbuffer} .= $w;
    $me->wantwrit(1);
}

sub parse_response {
    my $buf = shift;
    my( $l, @l, $k, $v, %r );

    @l = split /\n/, $buf;
    $l = shift @l;
    (undef, $k, $v) = split /\s+/, $l, 3;
    $r{resultcode} = $k;
    $r{resultmsg}  = $v;

    foreach (@l){
	last if /^$/;
	($k, $v) = split /:\s+/, $_, 2;
	$r{$k} = decode($v) if $k && $v;
    }

    \%r;
}

################################################################

sub transition {
    my $me = shift;
    my $st = shift;
    my $sv = shift;

    if( $st ){
	$me->{prevstatus}   = $me->{status};
	$me->{prevovstatus} = $me->{ovstatus};
	$me->{status}    = $st;
	$me->{ovstatus}  = $st;
	$me->{transtime} = $^T;

	$me->loggit( msg => $me->{ovstatus},
		     tag => 'TRANSITION',
		     slp => 1 ) if $me->{prevovstatus} ne $me->{ovstatus};

    }else{
	$me->{prevovstatus} = $me->{ovstatus};
	$me->{ovstatus}     = $me->{status};
    }

    $me->{currseverity} = ($me->{status} eq 'down') ? ($sv || $me->{severity}) : 'clear';

}
################################################################
sub web_side_buttons {}



################################################################
Doc::register( $doc );
push @Service::probes, \&probe;

1;
