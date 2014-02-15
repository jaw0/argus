# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Nov-16 14:45 (EST)
# Function: implement DARP Master (Server)
#
# $Id: DARP::Master.pm,v 1.27 2012/10/14 21:42:18 jaw Exp $

package DARP::Master;
@ISA = qw(Control BaseIO Server);

use strict qw(refs vars);
use vars qw(@ISA $doc %remote_override);

eval {
    Digest::HMAC->import('hmac_hex');
    Digest::MD5->import('md5_hex');
};

$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [qw(Control Server BaseIO)],
    versn => '3.3',
    html  => 'darp',
    methods => {
    },
    fields => {
      darpm::slave => {},
      darpm::noise => {},
      darpm::seqno => {},
    },
};


# slaves can only execute these functions
my @ALLOWED = qw(auth echo darp_list darp_update getconfigdata getparam darp_override_list darp_graphd);



sub create {
    my $class = shift;
    my $info  = shift;

    return unless $::HAVE_DARP;
    return if $::opt_t;
    my $me = DARP::Master->Server::new_inet( $info->{port} );
    $me->{debug} = $info->{debug} if $me;
}


sub unique {
    my $me = shift;

    "Connection from ".
	($me->{darpm}{slave} ? $me->{darpm}{slave}->{darpc}{tag}
                            : $me->{control}{srcaddr});
}

# new client connection
sub new {
    my $class = shift;
    my $fh    = shift;
    my $addr  = shift;
    my $me = {};
    bless $me, $class;

    $me->{fd} = $fh;
    $me->{control}{srcaddr} = $addr;
    $me->{type}    = 'DARP_Server';
    $me->{debug}   = $DARP::info->{debug};
    $me->{control}{timeout} = 2 * $DARP::info->{timeout};

    my $noise = ::random_cookie(64);
    $me->{darpm}{noise} = "<$noise\@$DARP::info->{tag}>";
    $me->debug( "new connection from $addr" );
    $me->{control}{authok} = 0;

    $me->wantread(1);
    $me->wantwrit(0);
    $me->settimeout($me->{control}{timeout});
    $me->baseio_init();

    $me;
}

sub readable {
    my $me = shift;

    if( $me->{darpm}{slave} ){
	$me->{darpm}{slave}->{status} = 'up';
    }
    $me->SUPER::readable(@_);
    $me->settimeout($me->{control}{timeout}) if $me->{fd};
}

sub writable {
    my $me = shift;

    if( $me->{darpm}{slave} ){
	$me->{darpm}{slave}->{status} = 'up';
    }
    $me->SUPER::writable(@_);
    $me->settimeout($me->{control}{timeout}) if $me->{fd};
}

sub done {
    my $me = shift;

    if( $me->{darpm}{slave} ){
	$me->{darpm}{slave}->{status} = 'down';
    }
    $me->SUPER::done();
}

sub authrzd_func {
    my $me = shift;
    my $data = shift;

    ++ $me->{darpm}{seqno};
    return 1 if $data->{func} eq 'auth';

    my $hmac = ::calc_hmac( $me->{darpm}{slave}->{darpc}{secret},
                            %$data, SEQNO => $me->{darpm}{seqno} );

    # print STDERR "got $data->{func} $data->{hmac}, $hmac\n";
    return 0 unless $hmac eq $data->{hmac};

    return 1 if grep { $data->{func} eq $_ } @ALLOWED;

    0;
}

################################################################
sub cmd_auth {
    my $ctl = shift;
    my $param = shift;
    my ($k, $v );

    my $addr = $ctl->{control}{srcaddr};
    my $pass = $param->{secret};
    my $tag  = $param->{tag};

    if( $pass ){
	foreach my $slave ( @{$DARP::info->{slaves}} ){

	    if( $addr eq $slave->{darpc}{addr}
		&& $tag  eq $slave->{darpc}{tag} ){

		# APOP syle auth
		my $digst = md5_hex( $ctl->{darpm}{noise} . $slave->{darpc}{secret} );
		next unless $digst eq $pass;

		# A faithful and good servant is a real godsend
		#   -- Martin Luther, Table-Talk
		$ctl->ok_n();
		$ctl->{control}{authok} = 1;
		$ctl->{darpm}{slave} = $slave;
		$slave->{status} = 'up';

		$ctl->{debug} = $slave->{debug};
		$ctl->{control}{timeout} = 2 * $slave->{darpc}{timeout};
		$ctl->{name}  = "DARP_Master/$tag";
		return;
	    }
	}
	::loggit( "DARP Authentication Failed from $ctl->{control}{srcaddr}", 0 );
	$ctl->bummer( 400, 'Authentication Failed' );
    }else{
	$ctl->bummer( 200, $ctl->{darpm}{noise} );
    }
}

sub cmd_darplist {
    my $ctl = shift;
    my $param = shift;
    my $tag = $param->{tag} || $ctl->{darpm}{slave}->{darpc}{tag};

    $ctl->ok();

    # get list of srvcs for slave
    # and parents...
    my( @srvc, @group, %group );
    foreach my $o (values %MonEl::byname){
	next unless ($o->{type} eq 'Service') || ($o->{type} eq 'Alias');
	next unless exists $o->{darp};
	next unless $o->{darp}{tags}{$tag};
        next if $o->{darp}{darp_mode} eq 'none';
        next if $o->{name} eq '_SNMP_HELPER';

	push @srvc, $o;

	my $p = $o->{parents}[0];
	while( $p ){
	    $group{ $p->unique() } = $p;
	    $p = $p->{parents}[0];
	}
    }

    my @snmpoid = map {"snmpoid $_->{_name}" } Argus::SNMP::get_user_conf();

    # On this he gave his orders to the servants
    #   -- Homer, Odyssey
    @srvc = map { $_->unique() } @srvc;
    foreach my $o (@snmpoid, sort keys %group, sort @srvc){
	$ctl->write( "$o: 1\n" );
    }

    $ctl->write("\n");
}

sub cmd_darpupdate {
    my $ctl = shift;
    my $param = shift;
    my $tag = $param->{tag} || $ctl->{darpm}{slave}->{darpc}{tag};

    my $x = $MonEl::byname{ $param->{object} };
    if( $x && $x->can('update') && $x->{darp} ){
	my $status = $param->{status};
	my $sever  = $param->{severity};

	if( $status ne 'up' && $status ne 'down' && $status ne 'override' ){
	    $ctl->bummer( 500, 'invalid status' );
	}else{
	    # Servant of God, well done;
	    #   -- Milton, Paradise Lost
	    $ctl->ok();
	    $ctl->debug("rcvd darp update: $tag sends $status, $sever - $param->{object}");
	    $x->debug(  "rcvd darp update: $tag sends $status, $sever - $param->{object}");
	    $x->{darp}{statuses}{ $tag }   = $status;
	    $x->{darp}{severities}{ $tag } = $sever;
	    $x->{web}{transtime} = $^T;		# doesn't belong here, but...
	    $x->update( undef );		# = darp::service::update()

	    $ctl->write( "object: $param->{object}\n" );
	    $ctl->write( "param: darp_update\n" );
	    $ctl->write( "\n" );

	    # RSN - proxy for mix-master mode?

	}
    }else{
	$ctl->bummer( 404, "DARP Object Not Found" );
    }
}

sub cmd_darp_note_overrides {
    my $ctl = shift;
    my $param = shift;
    my $tag = $param->{tag} || $ctl->{darpm}{slave}->{darpc}{tag};

    my @oo = map { $param->{$_} } (1 .. $param->{count});
    $remote_override{$tag} = \@oo;

    $::Top->{web}{transtime} = $^T;

    $ctl->ok_n();
}

################################################################
Doc::register( $doc );
Control::command_install( 'auth',        \&cmd_auth,      "authenticate a slave connection" );
Control::command_install( 'darp_list',   \&cmd_darplist,  "fetch object list" );
Control::command_install( 'darp_update', \&cmd_darpupdate, "update status" );
Control::command_install( 'darp_override_list', \&cmd_darp_note_overrides, 'make note of remote overrides');

1;

