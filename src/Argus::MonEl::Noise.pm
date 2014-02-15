# -*- perl -*-

# Copyright (c) 2007 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2007-Feb-14 12:19 (EST)
# Function: MonEl logging + noise making
#
# $Id: Argus::MonEl::Noise.pm,v 1.4 2007/12/31 01:24:30 jaw Exp $

package MonEl;
use strict;
use vars qw(%byname %severity_sort);

sub debug {
    my $me  = shift;
    my $msg = shift;

    return unless $me->{debug} || $::Top->{config}{debug};
    
    my $f = $me->{fd} ? fileno($me->{fd}) : '';
    $me->loggit( msg => "[$f] $msg",
		 tag => 'DEBUG' );
}

# { tag msg lpf slp }
# lpf: bool, log to logfile?
# slp: bool, add to object log?
# lss: log status
# also logs to syslog, consoles, STDERR (-f)
sub loggit {
    my $me = shift;
    my %p  = @_;
    my( $m, $msg );

    $msg = $p{msg} || $me->{ovstatus};

    $p{slp} ||= $p{objlog};
    $p{lpf} ||= $p{logfile};
    
    if( $p{slp} ){
	push @{$me->{stats}{log}}, [ $^T, $me->{status}, $me->{ovstatus}, $p{tag}, $msg ];
	# and trim...
	if( @{$me->{stats}{log}} > $me->{logsize} ){
	    my( $l );
	    
	    $l = @{$me->{stats}{log}};
	    splice @{$me->{stats}{log}}, 0, $l - $me->{logsize}, ();
	}
    }
    
    $m = $p{tag} . ($p{tag} ? ' - ' : '') .
	( $p{lss} ? "$me->{ovstatus} - " : '') .
	$me->unique() . " - $msg";
    
    ::loggit( $m, $p{lpf} );
}

# for warnings post-config
sub warning {
    my $me = shift;
    my $msg = shift;
    my( $m );

    $m = "WARNING: ";
    if( $me->{definedinfile} ){
	$m .= "in file '$me->{definedinfile}' on line $me->{definedonline} - ";
    }
    $m .= $me->unique() . ' - ';
    $m .= $msg;
    ::loggit( $m, 1 );
    undef;
}

################################################################

sub cmd_loggit {
    my $ctl = shift;
    my $param = shift;

    my $x = $byname{ $param->{object} };
    if( $x ){
	$x->loggit( %$param );
	$ctl->ok_n();
    }else{
	$ctl->bummer(404, 'Object Not Found');
    }
}
    
################################################################
Control::command_install( 'loggit',   \&cmd_loggit, 'add message to log',
			  'object msg lpf slp lss tag' );


1;
