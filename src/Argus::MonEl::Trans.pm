# -*- perl -*-

# Copyright (c) 2007 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2007-Feb-14 12:23 (EST)
# Function: MonEl object transition
#
# $Id: Argus::MonEl::Trans.pm,v 1.10 2012/12/02 04:32:57 jaw Exp $

package MonEl;
use strict;
use vars qw(%byname %isdown %severity_sort);

# how in such short time, From eve to morn has the sun made his transit?
#      -- Dante, Divine Comedy

# something changed, determine current status
sub transition {
    my $me = shift;
    my $by = shift;
    my( %cr, %co, $calarm, %csv, $maxsirent, %summary );

    $maxsirent = $me->{sirentime} || 0;
    foreach my $c (@{$me->{children}}){
	my $cc = $c->aliaslookup();
	next if $cc->{nostatus};
	$cr{ $cc->{status} }++;
	$co{ $cc->{ovstatus} }++;
        $csv{ $cc->{currseverity} }++;

        if( $cc->{alarm} ){
            $calarm ++;
            my $cst = $cc->{sirentime} || 0;
            $maxsirent = $cst if $cst > $maxsirent;
        }

	# calculate ovstatus-summary data
	foreach my $k (qw(up down override depends)){
	    my $v = $cc->{ovstatussummary}{$k};
	    $summary{$k} += $v;
	    $summary{total} += $v;
	}
    }

    my($newrst, $newost, $newsev, $newsum) = $me->aggr_stat(\%cr, \%co, \%csv, \%summary);

    if( $newrst ne $me->{status} ){
	$me->{transtime} = $^T;
    }

    my $ps = $me->{status};
    my $po = $me->{ovstatus};
    my $pv = $me->{currseverity};
    $me->{status}       = $newrst;
    $me->{ovstatus}     = $newost;
    $me->{currseverity} = $newsev;

    if( $calarm && $me->alarming_p() ){
	$me->{alarm} = 1;
	# this may get cleared later if there is an override
    }else{
	$me->{alarm} = 0;
    }

    $me->transition2();
    $me->{prevstatus}   = $ps;
    $me->{prevovstatus} = $po;
    $me->{prevseverity} = $pv;
    $me->{sirentime}    = $maxsirent if $me->{alarm};

    # finish calculating ovstatus-summary
    if( $me->{countstop} ){
	$newsum = { $me->{ovstatus} => 1, total => 1, severity => $me->{currseverity} };
    }
    if( $me->{override} ){
	my $t = $summary{total};
	$newsum = { override => $t, total => $t, severity => $me->{currseverity} };
    }
    $me->{ovstatussummary} = $newsum;

    $me->loggit( msg => ($by->{label_left} || $by->{label} || $by->{name}),
		 tag => 'TRANSITION',
		 lss => 1,
		 slp => 1 ) if ($me->{prevovstatus} ne $me->{ovstatus})
		            || ($me->{prevseverity} ne $me->{currseverity});

    $me->transition_propagate();
}

sub aggr_stat {
    my $me      = shift;
    my $rstatus = shift;
    my $ostatus = shift;
    my $sever   = shift;
    my $summary = shift;

    my($minsev, $maxsev);
    for my $sev (qw(warning minor major critical)){
        next unless $sever->{$sev};
        $minsev ||= $sev;
        $maxsev   = $sev;
    }

    my $gravity = $me->{gravity};

    unless( keys %$rstatus ){
        # no children => up
        return ('up', 'up', 'clear', { up => 1, total => 1, severity => 'clear' });
    }

    if( $gravity eq 'down' ){
	my $nr  = ($rstatus->{down} || $rstatus->{override}) ? 'down' : 'up';
        my $no;
        $no ||= 'down'     if $ostatus->{down};
        $no ||= 'override' if $ostatus->{override};
        $no ||= 'depends'  if $ostatus->{depends};
        $no ||= 'up'       if $ostatus->{up};
        my $nsv = ($no eq 'down') ? $maxsev || 'critical' : 'clear';

        $summary->{severity} = $nsv;

        return( $nr, $no, $nsv, $summary );
    }

    if( $gravity eq 'up' ){
        my $nr = $rstatus->{up} ? 'up' : 'down';
        my $no;
        $no ||= 'up'       if $ostatus->{up};
        $no ||= 'override' if $ostatus->{override};
        $no ||= 'depends'  if $ostatus->{depends};
        $no ||= 'down'     if $ostatus->{down};
        my $nsv = ($no eq 'down') ? $minsev || 'critical' : 'clear';

        my $n = $summary->{$no};

        return( $nr, $no, $nsv, {
            $no => $n, total => $summary->{total}, severity => $nsv,
        } );
    }

    if( $gravity eq 'vote' ){
        my $total  = $rstatus->{up} + $rstatus->{down};
        my $winamt = 0.50;	# QQQ - configurable?

        my $nr = ($rstatus->{up} >= $winamt * $total) ? 'up' : 'down';
        my $no;

        if( $ostatus->{override} + $ostatus->{up} + $ostatus->{depends} >= $winamt * $total ){
            $no = ($ostatus->{up} > $ostatus->{override}) ? 'up' : 'override';
            $no = 'depends' if $ostatus->{depends} > $ostatus->{override} + $ostatus->{up};
        }

        $no ||= 'down';
        my $nsv = ($no eq 'down') ? $minsev || 'critical' : 'clear';

        my $n = $summary->{$no};

        return( $nr, $no, $nsv, {
            $no => $n, total => $summary->{total}, severity => $nsv,
        } );
    }

    # invalid gravity
    return( 'down', 'down', 'critical', { down => 1, total => 1, severity => 'critical' } );
}



sub transition2 {
    my $me = shift;

    if( $me->{override} ){
	# set override
	$me->{ovstatus} = 'override' unless $me->{status} eq 'up';

	# clear alarm, since we are in override
	$me->{alarm}    = 0;
	# clear severity
	$me->{currseverity} = 'clear';
	# clear override
	if( $me->{override} && $me->{status} eq 'up' && $me->{override}{mode} eq 'auto' ){
            if( $me->{definedinfile} =~ /^DARP\@/ ){
                $me->override_remove() if $::Top->{darp_configure_done};
            }else{
                $me->override_remove();
            }
	}
    }

    delete $me->{depend}{culprit};
    $me->check_depends() if $me->{depends} && ($me->{status} eq 'down');

    # update stats
    $me->stats_transition();

    # webpage
    $me->{web}{transtime} = $^T;

    # Canst thou draw out leviathan with an hook?
    #   -- Job 41:1
    if( $me->can('transition_hook') ){
	# so user can diddle things
	$me->transition_hook();
    }

}

# That labour on the bosom of this sphere, To propagate their states
#     -- Shakespeare, Timon of Athens

# propagate transition change to parents
sub transition_propagate {
    my $me = shift;


    # send page
    # NB - previously, this checked status, causing, if in override, a notify to
    # be created but immediately acked and not sent
    # RSN - also for change in severity
    if(    $me->{prevovstatus} && ($me->{ovstatus} ne $me->{prevovstatus})
	|| $me->{prevseverity} && ($me->{currseverity} ne $me->{prevseverity}) ){

	# audit trail notify channel
	if( $me->{notify}{notifyaudit} ){
	    Notify::new( $me,
			 audit  => 1,
			 detail => "$me->{prevovstatus}/$me->{prevseverity} -> $me->{ovstatus}/$me->{currseverity}",
			 );
	}

	if( $me->can('transition_audit_hook') ){
	    $me->transition_audit_hook();
	}

	# do not notify if an ancestor, or me is in override
	if( !$me->{anc_in_ov} && ($me->{ovstatus} ne 'override')
	# and not down/depends
	&& ($me->{ovstatus} ne 'depends')
	){
	    # but not if I just came out of override to up
	    unless( $me->{prevovstatus} eq 'override' && $me->{ovstatus} eq 'up'
		    || $me->{prevovstatus} eq 'depends'  && $me->{ovstatus} eq 'up'
		    ){
		# QQQ - why is the above code so ugly and complex?
		# QQQ - should it all be kicked to N:new? (making that ugly and complex)
	      Notify::new( $me );
	    }
	}
    }

    # update hushed sirens if me transitions
    if( $me->{prevovstatus} && ($me->{ovstatus} ne $me->{prevovstatus})
	&& ($me->{ovstatus} eq 'down') && $me->{alarm} ){
	$me->{sirentime} = $^T;
    }

    if( $me->{ovstatus} eq 'down' ){
	$isdown{ $me->unique() } = 1;
    }else{
	delete $isdown{ $me->unique() };
    }

    foreach my $p ( @{$me->{parents}} ){
	$p->transition( $me );
    }

    # and notify anything depending on me
    if( $me->{ovstatus} eq 'up' ){
	foreach my $d (split /\s+/, $me->{depend}{onme}){
	    my $dx = $byname{$d};
	    next unless $dx;
	    next unless $dx->{ovstatus} eq 'depends';
	    $dx->transition( $dx->{status} );
	}
	delete $me->{depend}{onme};
    }

}

sub alarming_p {
    my $me = shift;

    return 0 if $me->{ovstatus} ne 'down';
    my $s = $me->{"siren.$me->{currseverity}"};
    return $s if defined $s;
    return $me->{siren};
}

1;
