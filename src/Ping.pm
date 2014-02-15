# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Apr-03 23:24 (EST)
# Function: ping service test
#
# $Id: Ping.pm,v 1.59 2012/12/02 22:21:40 jaw Exp $

package Ping;
@ISA = qw(Service);

use Argus::Encode;

use strict qw(refs vars);
use vars qw(@ISA $doc);

my $FPING_ARGS = " -r 3 -t 500 -e";
my $MAX_PING   = 250;

# -e   => show elapsed time
# -r   => retry limit
# -t   => timeout

# this works by getting a bunch of objects at a time
# and fping'ing them all at once
# it plays some games with the scheduling to accomplish this

$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [@ISA],
    methods => {},
    fields => {
      ping::hostname => {
	  descr => 'hostname or IP address to test',
	  attrs => ['config', 'inherit'],
      },
      ping::ipversion => {
          descr => 'IP version precedence',
	  attrs => ['config', 'inherit'],
          default => '4 6',
          versn => '3.7',
      },

      ping::addr => {
	  descr => 'address to ping',
      },
      ping::rbuffer => {
	  descr => 'read buffer',
      },
      ping::running => {
	  descr => 'is a ping already running?',
      },
      ping::data => {
	  descr => 'data returned by fping',
      },
      ping::ipver => {
	  descr => 'IP version (4 or 6)',
      },
      ping::rtt => {
	  descr => 'round trip time of last ping test',
      },
      ping::pid => {},
      ping::killed  => {},
      ping::resolvp => {},
      ping::resolvt => {},
    },
};

my @pending = ();	# [$fn]{$ip} = [objs...]

sub probe {
    my $name = shift;

    return ( $name =~ /^Ping/ ) ? [ 4, \&config ] : undef;
}

sub config {
    my $me = shift;
    my $cf = shift;
    my( $ip );

    $me->init_from_config( $cf, $doc, 'ping' );

    unless( $me->{ping}{hostname} ){
	return $cf->error( "Hostname not specified" );
    }

    $me->{ping}{addr} = Argus::Resolv::IP->new( $me->{ping}{hostname}, $me->{ping}{ipversion}, $cf );

    return $cf->error('fping not configured')
	unless $::path_fping || $::path_fping6;

    # XXX
    if( length($ip) == 4 ){
	$me->{ping}{ipver} = 4;
	return $cf->error( "fping not configured" )
	    unless $::path_fping;
    }elsif( length($ip) == 16 ){
	$me->{ping}{ipver} = 6;
	return $cf->error( "fping6 not configured" )
	    unless $::path_fping6;
    }

    $me->{uname} = "Ping_$me->{ping}{hostname}";

    bless $me if( ref($me) eq 'Service' );
    $me;
}

sub configured {
    my $me = shift;

    $me->{ping}{addr}->next_needed( $me->{srvc}{nexttesttime} );
}

sub start {
    my $me = shift;
    my $pg = $me->{ping};
    my( $fh, $fn, $pid, $to, $n, $fping );

    if( $pg->{running} ){
	$me->debug( 'already pinging' );
	return;
    }
    $me->debug( 'start ping' );
    $me->SUPER::start();

    $me->{ping}{addr}->refresh($me);

    if( $me->{ping}{addr}->is_timed_out() ){
        return $me->isdown( "cannot resolve hostname" );
    }

    unless( $me->{ping}{addr}->is_valid() ){
        $me->debug( 'Test skipped - resolv still pending' );
        # prevent retrydelay from kicking in
        $me->{srvc}{tries} = 0;
        return $me->done();
    }

    my $ip  = $me->{ping}{addr}->addr();
    my $ipv = $me->{ping}{addr}->ipver();

    if( $ipv == 4 ){
	$fping = $::path_fping;
    }else{
	$fping = $::path_fping6;
    }

    unless( $fping ){
	# make other noises?
	return $me->isdown( "fping is not configured" );
    }

    $me->{fd} = $fh = BaseIO::anon_fh();

    # Jack shall pipe and Gill shall dance.
    #   -- George Wither, Poem on Christmas.

    # open pipes to fping, and fork,exec
    unless( pipe($fh, FPW) ){
	my $m = "pipe failed: $!";
	::sysproblem( "PING $m" );
	$me->debug( $m );
	$me->done();
	return;
    }
    unless( pipe(FPR, FPD) ){
	my $m = "pipe failed: $!";
	close FPW;
	::sysproblem( "PING $m" );
	$me->debug( $m );
	$me->done();
	return;
    }

    $pid = fork();

    if( !defined($pid) ){
	# fork failed
	my $m = "fork failed: $!";
	close FPD;
	::sysproblem( "PING $m" );
	$me->debug( $m );
	return $me->done();
    }

    unless( $pid ){
        # child
        BaseIO::closeall();
        close STDIN;  open( STDIN, "<&FPR" );  close FPR;
	close STDOUT; open( STDOUT, ">&FPW" ); close FPW;
        # close STDERR; open( STDERR, ">/dev/null" );
        close $fh;
        close FPD;
	# Execute their airy purposes.
        #   -- John Milton, Paradise Lost
	exec( "$fping $FPING_ARGS" );
	# no, I didn't mean system() when I said exec()
	# and yes, I am aware the following statement is unlikely to be reached.
	syswrite( STDERR, "bummer dude, couldn't fping, what's that about? $!\n" );
        _exit(-1);
    }

    # First Musician Faith, we may put up our pipes, and be gone.
    #   -- Shakespeare, Romeo+Juliet
    close FPR;
    close FPW;


    $pg->{pid} = $pid;
    delete $pg->{killed};
    $me->baseio_init();

    $fn = fileno($fh);
    $pg->{rbuffer} = '';
    $to = $me->{srvc}{timeout};
    $pg->{running} = 1;
    $me->{srvc}{state} = 'running';

    Prog::register( $me );
    $n = 1;

    # the profiler suggested that I find a better way to do this
    # in the name of speed, we'll poke around in what was formerly
    # BaseIO's private data...
    # ick!
    # but 0.0030s -> 0.0010s

    # find all of the things scheduled to be pinged (or is it pung) at the same time
    # send them all to fping and do some bookkeeping so we can find
    # everything later
    foreach my $t (@BaseIO::bytime){
	last if $t->{time} > $^T;
	foreach my $x ( @{$t->{elem}} ){
	    next unless $x;
	    my $o  = $x->{obj};
	    my $op = $o->{ping};
	    next unless defined $op;
	    my $os = $o->{srvc};
	    next if $os->{disabled};
            next if $op->{running};
            next unless $o->monitored_here();
            next unless $o->monitored_now();

            my $opa = $op->{addr};
            $opa->refresh($o);
            next unless $opa->is_valid();
	    # fping can do one or the other, we do all v4 pings in one bunch, v6 another...
	    next unless $ipv == $opa->ipver();

	    $op->{pid} = $pid;
	    delete $op->{killed};
	    # save effort for BaseIO and self, clean up after ourself
	    $x = undef;

	    $o->SUPER::start();
	    my $oip = ::xxx_inet_ntoa($opa->addr());

	    print FPD "$oip\n";
	    push @{ $pending[$fn]{$oip} }, $o;
	    $op->{running} = 1;
	    $os->{state} = 'running';
	    $o->debug( 'ping start' );
	    $to = $os->{timeout} if $os->{timeout} > $to;
	    $n ++;
	    last if $n >= $MAX_PING;
	}
    }

    # also add current obj (it has already been removed from @bytime)
    my $ipa = ::xxx_inet_ntoa($ip);
    print FPD "$ipa\n";
    push @{ $pending[$fn]{$ipa} }, $me;
    $me->wantread(1);
    $me->wantwrit(0);
    $to = 10 unless $to > 10;
    $me->settimeout( $to + int($n/2) + 5 );	# to account for overhead...
    $me->debug( 'pinging' );

    # print STDERR "pinging: $n\n";

    close FPD;
}


sub progdone {
    my $me = shift;

    $me->debug( "reaped" );
    # NYI

    $me->{ping}{pid} = 0;
    $me->{srvc}{state} = 'done';
}

sub timeout {
    my $me = shift;

    return if $me->{srvc}{state} eq 'done';

    $me->debug( 'Ping Timeout' );
    unless( defined($me->{prog}{exit}) ){
	$me->debug( 'killing' );
	kill 9, $me->{ping}{pid} if $me->{ping}{pid};
	$me->{srvc}{state}  = 'reaping';
	$me->{ping}{killed} = 1;
    }

    # try jit reap
    Prog::reap() if $me->{ping}{pid};

}

sub readable {
    my $me = shift;
    my( $fh, $i, $l );

    $fh = $me->{fd};
    $i = sysread $fh, $l, 8192;
    if( $i ){
	$me->debug( "ping - read data ($l)" );
	$me->{ping}{rbuffer} .= $l;
    }else{
	$me->finish(0);
    }
}

# fping gives us lines like:
#   ip is alive (100 msec)
#   ip is unreachable
# for each line, find the correct ping object (from the table built in start)
# and mark them all as up/down
sub finish {
    my $me = shift;
    my( $n, $fh, $fn, @l );

    my $killedp = $me->{ping}{killed};
    $fh = $me->{fd};
    $fn = fileno($fh);

    @l = split /\n/, $me->{ping}{rbuffer};
    $me->{ping}{rbuffer} = '';
    $me->wantread(0);
    foreach (@l){
	my( $ip, $rtt );
	if( /bummer/i ){
	    ::sysproblem( "PING failed - $_" );
	    next;
	}
	($ip)  = /^([^\s]+)\s/;
	($rtt) = /\((.*) ms(ec)?/;
	foreach my $x ( @{$pending[$fn]{$ip}} ){
	    next unless $x;
	    my $xp = $x->{ping};
	    $n ++;
	    $xp->{running} = undef;
	    $x->debug( "PING: $_" );
	    # keep the rtt, and full line available for debugging
	    $xp->{rtt}    = $rtt;
	    $xp->{data}   = $_;
	    $x->{srvc}{result} = $rtt || 0;	# QQQ - what value if down?

	    if( /alive/ ){
		if( $x->{test}{testedp} ){
		    $x->generic_test( $rtt );
		}else{
		    $x->isup();
		}
	    }else{
		s/$ip\s+//;
		$x->isdown( $_ );
                $xp->{addr}->try_another();
	    }
	}
	delete $pending[$fn]{$ip};
    }

    ::sysproblem( 'PING failed - returned no data' )
	if( !$n && !$killedp );

    # make sure fping returned what it was supposed to
    foreach my $ip ( keys %{$pending[$fn]} ){
	# most likely, fping timed out and we killed it
	::sysproblem( "fping failed to return data about $ip" )
	    unless $killedp;
	foreach my $x ( @{$pending[$fn]{$ip}} ){
	    next unless $x;
	    my $xp = $x->{ping};
	    undef $xp->{running};
	    undef $xp->{data};
	    undef $xp->{rtt};
	    $xp->{result} = 0;
	    if( $killedp ){
		$x->isdown( 'timeout - fping killed' );
	    }else{
		$x->isdown( 'ERROR - fping failed us' );
	    }
	}
	delete $pending[$fn]{$ip};
    }
    $pending[$fn] = undef;
}

sub done {
    my $me = shift;

    $me->Service::done();
    $me->{ping}{addr}->next_needed( $me->{srvc}{nexttesttime} );
}

sub friendly_messagesup {
    my $me = shift;
    '%o{ping::hostname} is UP (pingable)';
}
sub friendly_messagesdn {
    my $me = shift;

    '%o{ping::hostname} is %s/%y (NOT PINGABLE)';
}

sub about_more {
    my $me = shift;
    my $ctl = shift;
    my( $k, $v );

    $me->SUPER::about_more($ctl);
    $me->more_about_whom($ctl, 'ping');
}

# sub webpage_more {
#     my $me = shift;
#     my $fh = shift;
#     my( $k, $v );
#
#     foreach $k (qw(rtt)){
# 	  $v = $me->{ping}{$k};
# 	  print $fh "<TR><TD>$k</TD><TD>$v</TD></TR>\n" if defined($v);
#     }
# }


################################################################
# global config
################################################################
Doc::register( $doc );
push @Service::probes, \&probe;

1;
