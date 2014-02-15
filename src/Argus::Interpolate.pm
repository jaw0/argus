# -*- perl -*-

# Copyright (c) 2012
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2012-Oct-14 10:42 (EDT)
# Function: fill in values
#
# $Id: Argus::Interpolate.pm,v 1.2 2012/10/27 03:12:18 jaw Exp $

package Argus::Interpolate;
use strict;

# %fmt{GROUPOP OBJECT{param}}
#
# %{Top:Foo{srvc::frequency}}
# %{Top:Foo} 	=> %{Top:Foo{srvc::result}}
# %{GROUPOP Top:Foo}
# %{GROUPOP Top:Foo{srvc::result}}
# %.4f{...}
# %d{...}


my %OP = (
    SUM		=> \&op_sum,
    COUNT	=> \&op_count,
    MIN		=> \&op_min,
    MAX		=> \&op_max,
    AVE		=> \&op_ave,
    AVG		=> \&op_ave,
    STDEV	=> \&op_stdev,
    STDDEV	=> \&op_stdev,
   );


sub _getparam {
    my $me    = shift;
    my $obj   = shift;
    my $param = shift;

    return '#[not ready]' if $param eq 'srvc::result' && !$obj->{srvc}{result_valid};

    my $v = eval { $obj->getparam($param) || 0 };
    if(my $e = $@){
        $me->debug("does not compute. param not found: " . $obj->unique() . "{$param}");
        $v = "#[invalid param]";
    }

    return $v;
}

sub _groupop {
    my $me = shift;
    my $s  = shift;
    my $p  = shift;

    my($op, $grp) = $s =~ /(\S+)\s+(\S+)/;

    # flatten, get values
    my $do = MonEl::find($grp);
    return unless $do;
    my @do = ($do);
    my @v;

    while( @do ){
        my $x = pop @do;
        $x = $x->aliaslookup();
        unless( $x->{srvc} ){
            for my $c (@{$x->{children}}){
                push @do, $c;
            }
            next;
        }

        my $v = _getparam($me, $x, $p);
        push @v, $v;
    }

    $me->debug("compute $op @v");

    my $f = $OP{uc($op)};
    unless( $op ){
        $me->debug("does not compute. op '$op' not found");
        return '#[invalid op]';
    }

    return $f->( @v );
}

# Let ignorance talk as it will, learning has its value.
#   -- Jean de La Fontaine, The Use of Knowledge
sub value {
    my $me  = shift;
    my $fmt = shift;
    my $s   = shift;
    my $p   = shift;

    return _groupop($me, $s, $p) if $s =~ /\S\s+\S/;

    my $x = MonEl::find($s);

    unless($x){
	# Does not compute!
	#   -- Robot, Lost In Space
	$me->debug("does not compute. object not found: $s");
	return "#[invalid object]";
    }
    my $r = _getparam($me, $x, $p);
    $r = sprintf '%'.$fmt, $r if $fmt;
    $me->debug("computing $s\{$p\} => $r");

    $r;
}

sub interpolate {
    my $me  = shift;
    my $txt = shift;

    # %{OBJ} => %{OBJ{srvc::result}
    $txt =~ s/%([a-z0-9\.-]*)\{([^{}]+)\}/%$1\{$2\{srvc::result\}\}/g;

    # fill in values
    $txt =~ s/%([a-z0-9\.-]*)\{([^{}]+)\{([^{}]+)\}\}/value($me,$1,$2,$3)/ge;

    return $txt;
}

################################################################

sub op_count {
    return scalar @_;
}
sub op_sum {
    my $t = 0;
    $t += $_ for @_;
    return $t;
}
sub op_ave {
    my $t = 0;
    $t += $_ for @_;
    return $t / @_;
}
sub op_stdev {
    my($v,$v2);
    for my $x (@_){
        $v += $x;
        $v2 += $x*$x;
    }

    return sqrt($v2/@_ - ($v/@_)**2);
}
sub op_min {
    my $m;
    for my $v (@_){
        $m = $_ if $v < $m || !defined $m;
    }
    return $m;
}
sub op_max {
    my $m;
    for my $v (@_){
        $m = $_ if $v > $m || !defined $m;
    }
    return $m;
}

################################################################

sub import {
    my $pkg = shift;
    my $caller = caller;

    for my $f (qw(interpolate)){
        no strict;
        *{$caller . '::' . $f} = $pkg->can($f);
    }
}



1;
