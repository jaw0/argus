# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Apr-05 15:32 (EST)
# Function: handle overrides
#
# $Id: Override.pm,v 1.28 2012/10/29 00:50:31 jaw Exp $

package MonEl;
use strict;
use vars qw(%inoverride);
%inoverride = ();

# and now that he is roused to such fury about his comrade,
# he will override fate itself
#   -- Homer, The Iliad

sub override {
    my $me = shift;
    my %param = @_;

    return undef unless $me->{overridable};

    $param{expires} += $^T if $param{expires} && $param{expires} < 314496000;

    $me->{override} = {
	user  => $param{user},
	mode  => $param{mode},
	quiet => $param{quiet} || 0,
	text  => $param{text},
	time  => $param{time},
	expires => $param{expires} || undef,
	ticket  => $param{ticket}  || undef,
    };

    return $me->override_set(1, 1);
}

sub override_set {
    my $me    = shift;
    my $prop  = shift;
    my $noise = shift;

    # TKT - remove old watch
    if( $me->{watch} && $me->can('tkt_watch_del') ){
	$me->tkt_watch_del();
    }

    unless( $me->{override}{user} ){
	delete $me->{override};
	$me->loggit( msg => 'invalid override',
		     tag => 'OVERRIDE' );
	return undef;
    }

    # enforce company override policy ?
    if( $me->can('override_policy') ){
	unless( $me->override_policy() ){
	    delete $me->{override};
	    return undef;
	}
    }

    $me->{override}{time} ||= $^T;
    $inoverride{ $me->unique() } = 1;

    # TKT - install ticket watch
    if( $me->{override}{ticket} && $me->can('tkt_watch_add') ){
	$me->tkt_watch_add($noise);
    }

    if( $noise ){
	if( $me->{override}{quiet} ){
	    $me->loggit( msg => "enabled by $me->{override}{user} - $me->{override}{text}",
			 tag => 'OVERRIDE' );
	}else{
	    $me->loggit( msg => $me->{override}{text},
			 tag => 'OVERRIDE',
			 slp => 1 ) if $me->{override}{text};
	    $me->loggit( msg => "enabled by $me->{override}{user}",
			 tag => 'OVERRIDE',
			 slp => 1 );
	    if( $me->{notify}{notifyaudit} ){
	        Notify::new( $me,
			     audit  => 1,
			     detail => "[override enabled]",
			     );
	      }
	}
    }

    # expire atjob
    if( my $exp = $me->{override}{expires} ){
	$exp = $^T if $exp < $^T;
        Cron->new( time => $exp,
		   text => 'override expire',
		   func => \&override_expire,
		   args => $me,
		   );
    }

    $me->ov_prop_dn();
    $me->transition() if $prop;
    1;
}

sub override_remove {
    my $me  = shift;
    my $by  = shift;
    my $why = shift;

    if( $me->{override}{quiet} ){
	$me->loggit( msg => "removed by $by - $why",
		     tag => 'OVERRIDE' );
    }else{
	$me->loggit( msg => $why,
		     tag => 'OVERRIDE',
		     slp => 1) if $why;
	$me->loggit( msg => "removed by $by",
		     tag => 'OVERRIDE',
		     slp => 1 ) if $by;

	if( $me->{notify}{notifyaudit} ){
	    Notify::new( $me,
			 audit  => 1,
			 detail => "[override removed]",
			 );
	  }
    }

    # TKT - clear ticket watch
    if( $me->{watch} && $me->can('tkt_watch_del') ){
	$me->tkt_watch_del();
    }

    delete $inoverride{ $me->unique() };
    delete $me->{override};

    $me->ov_prop_dn();
    $me->transition();
    1;
}

sub ov_prop_dn {
    my $me = shift;
    my $v = ($me->{override} || $me->{anc_in_ov}) ? 1 : 0;

    foreach my $x (@{$me->{children}}){
	$x->{anc_in_ov} = $v;
	$x->ov_prop_dn;
    }
}

sub override_expire {
    my $me = shift;

    return unless $me->{override};
    return unless $me->{override}{expires};
    return unless $me->{override}{expires} <= $^T;
    $me->override_remove( 'system', 'expired' );
}


################################################################

sub cmd_override {
    my $ctl   = shift;
    my $param = shift;

    if( $param->{expires} ){
	eval {
	    $param->{expires} = ::timespec( $param->{expires} );
	};
    }

    my $x = $MonEl::byname{ $param->{object} };

    if( $x ){
	if( ($param->{remove} eq 'yes') ? $x->override_remove($param->{user}, $param->{text})
	        : $x->override(%$param) ){
	    $x->{web}{transtime} = $^T;
	    $ctl->ok_n();
	}else{
	    $ctl->bummer(404, ($x->{overridable} ? 'Object Not Overridable' : 'Failed'));
	}
    }else{
        $ctl->bummer(404, "Object Not Found ($param->{object})" );
    }
}

sub cmd_ovinfo {
    my $ctl   = shift;
    my $param = shift;
    my( $x );

    $x = $MonEl::byname{ $param->{object} };
    if( $x && $x->{override} ){
	$ctl->ok();
	foreach my $f (qw(user mode quiet text time expires ticket)){
	    $ctl->write("$f: $x->{override}{$f}\n") if $x->{override}{$f};
	}
	$ctl->final();
    }else{
        $ctl->bummer(404, 'Object Not Found or Not in Override');
    }
}

sub cmd_ovlist {
    my $ctl = shift;

    $ctl->ok();
    foreach my $x (keys %inoverride){
	$ctl->write("$x\n");
    }
    $ctl->final();
}


################################################################

Control::command_install( 'override', \&cmd_override, "set or remove an override",
			  "object remove user text mode expires ticket quiet" );
Control::command_install( 'ovinfo',   \&cmd_ovinfo,  "return override details", "object" );
Control::command_install( 'ovlist',   \&cmd_ovlist,  "return all objects in override" );

1;
