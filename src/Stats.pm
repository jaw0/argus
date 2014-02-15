# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Apr-05 10:28 (EST)
# Function: maintain object statistics
#
# $Id: Stats.pm,v 1.54 2012/09/23 15:44:53 jaw Exp $

package MonEl;

use strict;
use vars qw(@statuses);

# RSN - from config file?
my $STATS_KEEP_DAYS   = 14;
my $STATS_KEEP_MONTHS = 14;
my $STATS_KEEP_YEARS  = 10;
my $STATS_KEEP_LOGS   = 1000;
my $SAVE_TIME_MIN = 30;

# for self testing, etc
@statuses = ();	# [start, idle, tests, loops]

sub stats_load {
    my $me = shift;
    my( $foo, $lastt, @l );

    return if $me->{transient} || ::topconf('_test_mode') || $::opt_t;
    $me->{stats}{status}    = $me->{status};
    $me->{stats}{lasttime}  = $^T;

    # compat with old directory structure
    my $file = "$::datadir/stats/" . $me->pathname();

    if( open( FILE, $file ) ){
	while( <FILE> ){
	    chop;

	    if( /^status/ ){
		(undef, $me->{status}, $me->{ovstatus},
		 $me->{alarm}, $me->{transtime}) = split;

		$me->{stats}{status} = $me->{status};
	    }

	    elsif( /^2status/ ){
		(undef, $lastt,
		 $me->{web}{transtime},
		 $me->{sirentime} ) = split;
	    }

	    elsif( /^severity/ ){
		(undef, $me->{currseverity}) = split;
	    }

	    elsif( /^snmp/ ){
		# the name snmp is historical...
		(undef, $me->{test}{calcdata}{ave},
		 $me->{test}{calcdata}{lastv},
		 undef	# toss lastt
		 ) = split;
	    }

	    elsif( /^annotation/ ){
		(undef, $foo) = split /\s+/, $_, 2;
		$me->{annotation} = decode($foo);
	    }

	    elsif( /^tries/ ){
		(undef, $foo) = split /\s+/, $_, 2;
		$me->{srvc}{tries} = $foo;
	    }

	    elsif( /^reason/ ){
		(undef, $foo) = split /\s+/, $_, 2;
		$me->{srvc}{reason} = decode($foo);
	    }

	    elsif( /^depends/ ){
		(undef, $me->{depend}{culprit}) = split  /\s+/, $_, 2;
	    }
	    elsif( /^depending/ ){
		(undef, $me->{depend}{onme}) = split  /\s+/, $_, 2;
	    }

	    elsif( /^darp-status/ ){
		my( $tag, $st );
		(undef, $tag, $st) = split /\s+/, $_, 3;
		$me->{darp}{statuses}{$tag} = $st;
	    }
	    elsif( /^darp-severity/ ){
		my(undef, $tag, $sv) = split /\s+/, $_, 3;
		$me->{darp}{severities}{$tag} = $sv;
	    }

	    elsif( /^notify/ ){
		(undef, $foo) = split /\s+/, $_, 2;
	        Notify::load( $me, $foo );
	    }

	    elsif( /^log/ ){
		(undef, @l) = split /\s+/, $_, 6;
		push @{$me->{stats}{log}},
 	        [ @l[0,1,2],
		  ($l[3] eq '_' ? undef : decode($l[3])),
		  ($l[4] eq '_' ? undef : decode($l[4])) ];
	    }

	    # override
	    elsif( /^override/ ){
		(undef, @l) = split /\s+/, $_, 7;
		$me->{override} = {
		    user    => ($l[0] eq '_' ? undef : decode($l[0])),
		    mode    => $l[1],
		    time    => $l[2],
		    expires => $l[3],
		    ticket  => ($l[4] eq '_' ? undef : decode($l[4])),
		    text    => ($l[5] eq '_' ? undef : decode($l[5])),
		};
		$me->override_set(0, 0);
	    }

	    # daily/monthly/yearly stats
	    elsif( /^(daily|monthly|yearly)/ ){
		@l = split;
		my $d = shift @l;
		my @k = qw(start elapsed up down ndown clear warning minor major critical);
		my %h;
		@h{@k} = @l;
		push @{$me->{stats}{$d}}, \%h;
	    }

	    else{
		$me->loggit( msg => "invalid entry in stats file: $_",
			     tag => 'STATS' );
	    }
	}
	close FILE;
    }

    $me->{stats}{daily}[0] = stats_initstats( $^T )
	unless( $me->{stats}{daily} && @{$me->{stats}{daily}} );

    $me->{stats}{monthly}[0] = stats_initstats( $^T )
	unless( $me->{stats}{monthly} && @{$me->{stats}{monthly}} );

    $me->{stats}{yearly}[0] = stats_initstats( $^T )
	unless( $me->{stats}{yearly} && @{$me->{stats}{yearly}} );

    if( $lastt ){
	my(@ct, @lt);
	@ct = localtime $^T;
	@lt = localtime $lastt;
	# if we were not running at midnite we would have missed the stats_update
	# we need to roll over stats ourself
	if( $ct[3] != $lt[3] ){
	    $me->stats_roll_over(\@ct, \@lt);
	}
    }

}


sub stats_save {
    my $me = shift;
    my( $file, $p, $l );

    return if $me->{transient} || ::topconf('_test_mode') || $::opt_t;

    $file = "$::datadir/stats/" . $me->pathname();
    open( FILE, ">$file" ) ||
	return $me->loggit( msg => "cannot save stats to '$file': $!",
			    tag => 'STATS' );

    print FILE "status $me->{status} $me->{ovstatus} $me->{alarm} $me->{transtime}\n";
    # these could be combined, but this gives us backwards compaty
    print FILE "2status ",
    	($me->{stats}{lasttime} || 0), " ",  ($me->{web}{transtime} || 0), " ",
        ($me->{sirentime} || 0), "\n";
    print FILE "severity $me->{currseverity}\n" if $me->{currseverity};
    print FILE "annotation ", encode($me->{annotation}), "\n" if $me->{annotation};
    print FILE "tries $me->{srvc}{tries}\n" if $me->{srvc} && $me->{srvc}{tries};
    print FILE "reason ", encode($me->{srvc}{reason}), "\n" if $me->{srvc} && $me->{srvc}{reason};

    if( $me->{test} && $me->{test}{calcdata} ){
	print FILE "snmp ", ($me->{test}{calcdata}{ave} || 0);
	print FILE " $me->{test}{calcdata}{lastv} $me->{test}{calcdata}{lastt}"
	    if $me->{test}{calcdata}{lastt};
	print FILE "\n";
    }
    print FILE "depends $me->{depend}{culprit}\n"
	if $me->{depend} && $me->{depend}{culprit};
    print FILE "depending $me->{depend}{onme}\n"
	if $me->{depend} && $me->{depend}{onme};

    if( exists $me->{darp} ){
	foreach my $tag ( sort keys %{ $me->{darp}{statuses} } ){
            next unless $me->{darp}{tags}{$tag};
	    print FILE "darp-status $tag $me->{darp}{statuses}{$tag}\n";
	    print FILE "darp-severity $tag $me->{darp}{severities}{$tag}\n";
	}
    }

    foreach my $p (@{$me->{notify}{list}}){
	print FILE "notify $p->{idno}\n";
    }

    # override
    if( $me->{override} ){
	print FILE "override ",
	(encode($me->{override}{user}) || '_'), " ",
	($me->{override}{mode} || 'auto'), " ",
	($me->{override}{time} || 0), " ",
	($me->{override}{expires} || 0), " ",
	(encode($me->{override}{ticket}) || '_'), " ",
	(encode($me->{override}{text}) || '_'), "\n";
    }


    unless( $me->{nostats} ){
	# daily/monthly/yearly stats
	foreach $p (qw(daily monthly yearly)){
	    foreach $l ( @{$me->{stats}{$p}} ){
		print FILE "$p";
		for my $x (qw(start elapsed up down ndown clear warning minor major critical)){
		    print FILE " ", ($l->{$x} || 0);
		}
		print FILE "\n";
	    }
	}
    }

    my $nlog = 0;
    foreach $l ( @{$me->{stats}{log}} ){
	last if $nlog ++ > $STATS_KEEP_LOGS;
	# [ time, status, ovstatus, tag, msg ]
	print FILE "log $l->[0] $l->[1] $l->[2] ",
	(encode($l->[3]) || '_'), ' ',
	(encode($l->[4]) || '_'), "\n";
    }

    close FILE;
}

sub stats_transition {
    my $me = shift;
    my( $save );

    return if $me->{nostats};
    return if $me->{transient} || ::topconf('_test_mode');

    $save = 1 if $^T - $me->{stats}{lasttime} > $SAVE_TIME_MIN;
    $me->stats_update_and_maybe_roll();

    if( ($me->{stats}{status} ne $me->{status}) && $me->{status} eq 'down' ){
	$me->{stats}{daily}  [0]{ndown} ++;
	$me->{stats}{monthly}[0]{ndown} ++;
	$me->{stats}{yearly} [0]{ndown} ++;
	$save = 1;
    }
    $me->{stats}{status} = $me->{status};

    if( $save && !::topconf('_save_less') ){
	$me->stats_save();
    }
}

sub stats_update {
    my $me = shift;
    my $t  = shift || $^T;
    my( $dt );

    return if $me->{nostats};
    $dt = $t - $me->{stats}{lasttime};
    return unless $dt;

    for my $d (qw(daily monthly yearly)){
	$me->{stats}{$d}[0]{elapsed}                += $dt;
	$me->{stats}{$d}[0]{ $me->{stats}{status} } += $dt;
	$me->{stats}{$d}[0]{ $me->{currseverity} }  += $dt;
    }

    $me->{stats}{lasttime} = $t;
}

sub stats_update_and_maybe_roll {
    my $me = shift;
    my( $t, @lt, @ct );

    return if $me->{nostats};

    @lt = localtime $me->{stats}{lasttime};
    @ct = localtime $^T;

    # Skulking in corners? wishing clocks more swift?
    # Hours, minutes? noon, midnight?
    #   -- Shakespeare, Winters Tale

    if( $ct[3] != $lt[3] ){	# [3] => mday
	my( $ssm, $midnite );

	# seconds since midnight:
	$ssm = ($ct[2] * 60 + $ct[1]) * 60 + $ct[0];
	$midnite = $^T - $ssm;

	# update yesterday's stats
	$me->stats_update( $midnite );
	$me->stats_roll_over(\@ct, \@lt, $midnite);
	# A rolling log gathers no moss
    }

    # update current stats
    $me->stats_update();
}

# called by cron
# Take I your wish, I leap into the seas,
# Where's hourly trouble for a minute's ease.
#   -- Shakespeare, Pericles Prince of Tyre
sub stats_hourly {
    my $me = shift;
    my( $t, @lt, @ct );

    return if $me->{nostats};

    $me->stats_update_and_maybe_roll();
    $me->{web}{transtime} = $^T;
}


# roll over daily, etc. stats
sub stats_roll_over {
    my $me = shift;
    my $ct = shift;
    my $lt = shift;
    my $midnite = shift || $^T;

    unshift @{$me->{stats}{daily}}, stats_initstats( $midnite );
    # There were ($STATS_KEEP_DAYS + 1) in the bed,
    # and the little one said, "Roll over! Roll over!"
    # So they all rolled over and one fell out,
    # There were $STATS_KEEP_DAYS in the bed,
    #   -- nursery rhyme
    splice  @{$me->{stats}{daily}}, $STATS_KEEP_DAYS, @{$me->{stats}{daily}}, ();

    # O, swear not by the moon, the inconstant moon,
    # That monthly changes in her circled orb,
    #   -- Shakespeare, Romeo+Juliet
    if( $ct->[4] != $lt->[4] ){
	# roll over monthly stats
	unshift @{$me->{stats}{monthly}}, stats_initstats( $midnite );
	splice  @{$me->{stats}{monthly}}, $STATS_KEEP_MONTHS, @{$me->{stats}{monthly}}, ();
    }

    # That the daughters of Israel went yearly to lament
    #   -- judges 11:40
    if( $ct->[5] != $lt->[5] ){
	# roll over yearly stats
	unshift @{$me->{stats}{yearly}}, stats_initstats( $midnite );
	splice  @{$me->{stats}{yearly}}, $STATS_KEEP_YEARS, @{$me->{stats}{yearly}}, ();
    }
}


sub stats_initstats {
    my $t = shift;

    { start => $t, map { ($_ => 0) } qw(elapsed down up ndown clear warning minor major critical) };
}

################################################################

sub cmd_log {
    my $ctl = shift;
    my $param = shift;
    my( $x, $l );

    $x = $MonEl::byname{ $param->{object} };
    if( $x ){
	$ctl->ok();
	foreach $l ( @{$x->{stats}{log}} ){
	    $ctl->write( "$l->[0] $l->[1] $l->[2] " .
			 (encode($l->[3])||'none') . " " .
			 (encode($l->[4])||'none') . "\n" );
	}
	$ctl->final();
    }else{
        $ctl->bummer(404, 'Object Not Found');
    }
}

sub cmd_stats {
    my $ctl = shift;
    my $param = shift;
    my( $x, $b, $l );

    $x = $MonEl::byname{ $param->{object} };
    $b = $param->{stat};

    if( $x && $x->{stats}{$b} ){
	$ctl->ok();
	foreach $l ( @{$x->{stats}{$b}} ){
	    $ctl->write( "$l->{start} $l->{elapsed} $l->{up} $l->{down} $l->{ndown}\n" );
	}
	$ctl->final();
    }else{
        $ctl->bummer(404, 'Object Not Found');
    }
}

sub stats_cron_job_hourly {
    foreach my $x (@MonEl::all){
	$x->stats_hourly();
    }
}

sub stats_cron_job_save {
    # save a few at a time
    my $n = int $^T / 300;
    foreach my $x (@MonEl::all){
        next if $n++ % 47;
        $x->stats_save();
    }
}

# update some global status
sub status_update {
    unshift @statuses, [$^T, $::idletime, $Service::n_tested, $::loopcount ];
    while( @statuses > 20 ){ pop @statuses }
}


################################################################
# global init
################################################################

Control::command_install( 'log',   \&cmd_log,   "return log data on object", "object" );
Control::command_install( 'stats', \&cmd_stats, "return stats on object",    "object stat" );

Cron->new(
	  time => $^T + (3600 - ($^T % 3600)),
	  freq => 3600,
	  text => 'Stats hourly update',
	  func => \&stats_cron_job_hourly,
      );

Cron->new(
	  freq => 60,
	  text => 'Status update',
	  func => \&status_update,
      );

1;
