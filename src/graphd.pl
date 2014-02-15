#!__PERL__
# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Oct-31 15:45 (EST)
# Function: server side of graph data collector
#
# $Id: graphd.pl,v 1.18 2011/11/03 02:13:41 jaw Exp $

# read in data from argusd, save to data files
# uses a large number of file descriptors, be sure
# that the system limit is sufficient (eg. limit/ulimit openfile/maxfiles/...)


use lib('__LIBDIR__');
require "conf.pl";

package Argus::Graph::Data;
use Argus::Graph::Data;
use Sys::Syslog qw(:DEFAULT setlogsock);
use POSIX qw(:errno_h);
use strict;

my $DEBUG = 0;
my %obj = ();
my @lru = ();
my $nopen;
my $DATADIR = $ENV{ARGUS_DATA} || $::datadir;

my $syslog = $ENV{ARGUS_SYSLOG};
if( $syslog ){
    eval {
	if( defined &setlogsock && $Sys::Syslog::VERSION < 0.03 ){
	    setlogsock( 'unix' );
	}
    };
    openlog( 'graphd', 'pid ndelay', $syslog );
}
loggit( "restarted" );

while( <> ){
    chop;

    if( /^sample/ ){
	# sample T obj st val samps hrs days
	my(undef, $t, $name, $st, $val, $ss, $hs, $ds, $expect, $delta #...
	   ) = split;
	newobj( $name, $ss, $hs, $ds ) unless defined $obj{$name};
	add_sample( $name, $t, $st, $val, $expect, $delta );
	update_lru( $name );
    }
}

# It adds a precious seeing to the eye
#   -- Shakespeare, Love's Labour 's Lost
sub add_sample {
    my $name = shift;
    my $time = shift;
    my $stat = shift;
    my $valu = shift;
    my $expt = shift;
    my $delt = shift;
    my( $me, $fh, $off, $flg );

    $me = $obj{$name};
    openfile($me) unless $me->{fd};
    $fh = $me->{fd};

    # updating too fast?
    my $delay = $time - $me->{lastt};
    return if $delay < 30;

    # keep running average of delay
    $me->{pdelay} = $me->{delay};
    $me->{delay}  = ($me->{delay} + $delay) / 2 if $me->{lastt};

    $off = $me->{sampl_index} * $SAMP_SIZE + $me->{sampl_start};
    sysseek( $fh, $off, 0 );
    syswrite($fh, pack("NfNff",
		       $time, $valu, flags($stat), $expt, $delt
		       ), $SAMP_SIZE);

    $me->{sampl_index} ++;
    $me->{sampl_index} %= $me->{sampl_nmax};
    $me->{sampl_count} ++
	unless $me->{sampl_count} >= $me->{sampl_nmax};


    # update hourly stats
    $me->{hours_min} = $valu
	if !$me->{hours_nsamp} || ($valu < $me->{hours_min});
    $me->{hours_max} = $valu
	if !$me->{hours_nsamp} || ($valu > $me->{hours_max});
    $me->{hours_sigma} += $valu;
    $me->{hours_sigm2} += $valu * $valu;
    $me->{hours_expect} += $expt;
    $me->{hours_delta}  += $delt;
    $me->{hours_nsamp} ++;
    $me->{hours_flags} = sum_flags( $me->{hours_flags}, $stat );


    # update daily stats
    $me->{days_min} = $valu
	if !$me->{days_nsamp}  || ($valu < $me->{days_min});
    $me->{days_max} = $valu
	if !$me->{days_nsamp}  || ($valu > $me->{days_max});
    $me->{days_sigma} += $valu;
    $me->{days_sigm2} += $valu * $valu;
    $me->{days_expect} += $expt;
    $me->{days_delta}  += $delt;
    $me->{days_nsamp} ++;
    $me->{days_flags} = sum_flags( $me->{days_flags}, $stat );

    # roll?
    my( @lt, @ct );
    @lt = localtime $me->{lastt};
    @ct = localtime $time;
    if( $me->{lastt} && ($lt[2] != $ct[2]) ){
	# add hour data
	my($ave, $std) = ave_sdev( $me->{hours_sigma},
				   $me->{hours_sigm2},
				   $me->{hours_nsamp});
	$off = $me->{hours_index} * $HOURS_SIZE + $me->{hours_start};
	sysseek( $fh, $off, 0 );
	syswrite($fh, pack("NffffNNx4ff",
			   $time,
			   $me->{hours_min}, $me->{hours_max},
			   $ave, $std,
			   $me->{hours_nsamp},
			   $me->{hours_flags},
                           $me->{hours_expect} / $me->{hours_nsamp},
                           $me->{hours_delta}  / $me->{hours_nsamp},
			   ), $HOURS_SIZE);
	$me->{hours_index} ++;
	$me->{hours_index} %= $me->{hours_nmax};
	$me->{hours_count} ++
	    unless $me->{hours_count} >= $me->{hours_nmax};

	# reset stats
	$me->{hours_min} = $me->{hours_max} =
            $me->{hours_expect} = $me->{hours_delta} =
	    $me->{hours_nsamp}  = $me->{hours_sigma} =
	    $me->{hours_sigm2}  = $me->{hours_flags} = 0;
    }

    if( $me->{lastt} && ($lt[3] != $ct[3]) ){
	# add day data
	my($ave, $std) = ave_sdev( $me->{days_sigma},
				   $me->{days_sigm2},
				   $me->{days_nsamp});
	$off = $me->{days_index} * $DAYS_SIZE + $me->{days_start};
	sysseek( $fh, $off, 0 );
	syswrite($fh, pack("NffffNNx4ff",
			   $time,
			   $me->{days_min}, $me->{days_max},
			   $ave, $std,
			   $me->{days_nsamp},
			   $me->{days_flags},
                           $me->{days_expect} / $me->{days_nsamp},
                           $me->{days_delta}  / $me->{days_nsamp},
			   ), $DAYS_SIZE);

	$me->{days_index} ++;
	$me->{days_index} %= $me->{days_nmax};
	$me->{days_count} ++
	    unless $me->{days_count} >= $me->{days_nmax};

	# reset stats
	$me->{days_min} = $me->{days_max} =
            $me->{days_expect} = $me->{days_delta} =
	    $me->{days_nsamp}  = $me->{days_sigma} =
	    $me->{days_sigm2}  = $me->{days_flags} = 0;
    }

    $me->{lastt} = $time;
    $me->write_header();
}

# Yet, for necessity of present life,
# I must show out a flag and sign of love,
# Which is indeed but sign. That you shall surely find him,
#   -- Shakespeare, Othello
sub flags {
    my $st = shift;

    {
	up       => 0,
	down     => 1,
	override => 2,
    }->{$st};
}

sub sum_flags {
    my $o = shift;
    my $n = flags( shift );

    return 1 if $o == 1 || $n == 1;
    return 2 if $o == 2 || $n == 2;
    0;
}

sub update_lru {
    my $name = shift;
    my $me = $obj{$name};

    my $fp = int( $me->{pdelay} );
    my $fd = int( $me->{delay}  );

    return if $fp == $fd;

    # remove from pdelay list
    my @a = grep { $_ != $me } @{$lru[ $fp ]};
    $lru[ $fp ] = \@a;

    # add to delay list
    push @{$lru[ $fd ]}, $me;
}

# close some things to make room
# close the objects that get updated least often
sub close_lru {

    my @close;
    my $i = @lru;

    while($i){
	$i --;

	next unless $lru[$i];
	debug("close file lrui=$i files=" . scalar(@{$lru[$i]}) . " nop=$nopen");
	push @close, @{$lru[$i]};
	$lru[$i] = undef;
	last if @close > $nopen/4;
    }

    for my $obj (@close){
	my $fd = $obj->{fd};
	next unless $fd;
	close $fd;
	delete $obj->{fd};
	$nopen --;
	debug( "closed file $obj->{name} nop=$nopen" );
    }
}

sub openfile {
    my $me = shift;

    my $fh   = anon_fh();
    my $name = $me->{name};
    my $x;
    my $err;

    my $file = "$DATADIR/gdata/$name";

    if( -f $file ){
	$x = "+< $file";
    }else{
	$x = "+> $file";
	$me->{need_init} = 1;
    }

    for my $i (0 .. 1){
	for my $n (0 .. 1){
	    if( open( $fh, $x ) ){
		$me->{fd} = $fh;
		$nopen ++;
		return;
	    }
	    $err = $!;

	    # close something
	    close_lru();
	}

	# close everything
	debug("close everything");
	for my $obj (values %obj){
	    my $fd = $obj->{fd};
	    next unless $fd;
	    close $fd;
	    delete $obj->{fd};
	    $nopen --;
	    debug( "closed file $obj->{name} nop=$nopen" );
	}
	@lru = ();
    }

    loggit( "$name on too tight, won't open: $err" );
    die "$err\n";
}

sub newobj {
    my $name = shift;
    my $ss   = shift;
    my $hs   = shift;
    my $ds   = shift;

    my $me = $obj{$name} = {
	name => $name,
    };

    bless $me;

    openfile($me);
    my $fh = $me->{fd};

    binmode $fh;
    if( $me->{need_init} ){
	$me->initfile($ss,$hs,$ds);
	delete $me->{need_init};
    }else{
	$me->initstats($ss,$hs,$ds);
    }

}

################################################################

# create new file
sub initfile {
    my $me = shift;
    my $ss = shift;
    my $hs = shift;
    my $ds = shift;
    my $fh = $me->{fd};

    loggit( "creating data file $me->{name}" );

    # set section sizes on new file if requested
    $me->{sampl_nmax} = $ss if $ss;
    $me->{hours_nmax} = $hs if $hs;
    $me->{days_nmax}  = $ds if $ds;

    $me->header_init();

    # pre-extend
    truncate $fh, ($me->{days_start} + $DAYS_SIZE * $me->{days_nmax});

    $me->write_header();
}

# load existing file
sub initstats {
    my $me = shift;
    my $ss = shift;
    my $hs = shift;
    my $ds = shift;

    my $magic = $me->read_header();

    unless( $magic eq $MAGIC){

        # do we need to upgrade?
        $magic = $me->upgrade();

        if( $magic eq $MAGIC ){
            loggit("upgraded data file: $me->{name}");
        }else{
            loggit( "corrupt data file: $me->{name}" );
            close $me->{fd};
        }
    }

    # do we need to resize?
    if(    ($ss && $ss != $me->{sampl_nmax})
        || ($hs && $hs != $me->{hours_nmax})
        || ($ds && $ds != $me->{days_nmax})
	){
	loggit( "resizing data file: $me->{name}" );
	$me->resize($ss,$hs,$ds);
    }

}

sub ave_sdev {
    my $s  = shift;
    my $s2 = shift;
    my $n  = shift;
    my( $u, $x, $v );

    # things may overflow and we may try taking sqrt of a negative
    # (like if some wiseguy tries graphing uptime)

    if( $n ){
	$u = $s  / $n;
	$x = $s2 / $n - $u * $u;
    }else{
	$u = $x = $v = 0;
    }
    if( $x > 0 ){
	$v = sqrt( $x );
    }

    ($u, $v);
}


################################################################

sub loggit {
    my $msg = shift;

    eval {
	syslog( 'info', $msg )  if $syslog;
    };
    print STDERR "GRAPHD: $msg\n";
}

sub debug {
    return unless $DEBUG;
    loggit(@_);
}
