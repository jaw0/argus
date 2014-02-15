# -*- perl -*-

# Copyright (c) 2011
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2011-Oct-15 14:21 (EDT)
# Function: holt-winters abberant behavior detection
#
# $Id: Argus::MHWAB.pm,v 1.8 2011/12/23 23:21:04 jaw Exp $

package Argus::MHWAB;
@ISA = qw(Argus::HWAB);
use POSIX;
use vars qw(@ISA);
use strict;

my $TWOWEEKS    = 2 * 7 * 24 * 3600;
my $BOOTK       = 0.025;
my $BOOTDK	= 0.90;
my $EPSILON     = 0.0001;

sub MAX {
    my $max = shift;

    for my $x (@_){
        $max = $x if $x > $max;
    }
    return $max;
}

# initialize params
sub _bootstrap {
    my $me  = shift;
    my $val = shift;
    my $sdv = shift;
    my $si  = shift;

    my $age    = $me->{current}{start} - $me->{created};
    my $nsamp  = $age / $me->{twin};

    my $btb = $me->_get("b boot");
    my($ctp, $dtp) = $me->_get_cd($si);
    my $ctb = $me->_get("c boot");
    my $dtb = $me->_get("d boot");
    $ctp = $val unless defined $ctp;
    $ctb = $val unless defined $ctb;
    # C = smoothed average observed value
    my $ct  = ($val + $ctp + $ctb) / 3;
    # D = maximum observed deviation
    my $dtx = MAX( abs($val - $ct), abs($val - $ctp), abs($val - $ctb), abs($ctb - $ctp) ) + $sdv;
    my $dt  = MAX( $dtp, 2 * $dtx, $dtb*$BOOTDK );
    $btb += $ctp ? $val / $ctp : 1;
    # B = average ratio
    my $bt  = $btb / ($nsamp + 1);

    $me->_put_ab($bt, $nsamp ? $bt / ($nsamp/2) : 0);
    $me->_put_cd($si, $ct, $dt);
    $me->_put("b boot", $btb);
    $me->_put("c boot", $val);
    $me->_put("d boot", $dt);

    $me->{expect} = {
        y	=> $ct,
        d	=> $dt,
        phase	=> 'bootstrap',
        index	=> $si,
    };
}

sub _init_expect {
    my $me = shift;

    my $si      = ($me->{current}{start} / $me->{twin}) % $me->{buckets};

    my($atp, $btp) = $me->_get_ab();
    my($ctp, $dtp) = $me->_get_cd($si);

    return unless $atp && $btp && $ctp && $dtp;

    $me->{expect} = {
        y	=> ($atp + $btp) * $ctp,
        d	=> $dtp,
    };
}

sub _hw {
    my $me  = shift;
    my $val = shift;
    my $sdv = shift;
    my $now = shift;

    my $buckets = $me->{buckets};
    my $si      = ($me->{current}{start} / $me->{twin}) % $buckets;
    my $age     = $me->{current}{start} - $me->{created};

    $me->debug("hw $val, si $si");

    return $me->_bootstrap($val, $sdv, $si) if $age < $me->{period_boot};


    my($atp, $btp) = $me->_get_ab();
    my($ctp, $dtp) = $me->_get_cd($si);

    # missing data - something stopped during boot phase, patch hole
    unless( defined $ctp ){
        my $max = $me->{buckets};
        my $pi = ($si - 1 + $max) % $max;
        my($cx, undef) = $me->_get_cd($pi);
        $cx  = $val unless defined $cx;
        $ctp = $dtp = $BOOTK * $val + (1 - $BOOTK) * $cx;
    }

    my $yt  = ($atp + $btp) * $ctp;
    my($alpha, $beta, $gamma) = $me->_alpha_beta_gamma($val);

    my($at, $bt);
    if( abs($ctp) > $EPSILON ){
        $at = $alpha * ($val / $ctp) +  (1 - $alpha) * ($atp + $btp);
        $bt = $beta  * ($at - $atp)  +  (1 - $beta)  * $btp;

    }else{
        $at = $atp;
        $bt = $btp;
    }

    if( $at + $bt < $EPSILON ){
        # QQQ - excessive shrinkage. reset+start over?
        $at = $EPSILON; $bt = 0;
    }

    my $ct = $gamma * ($val / $at)   +  (1 - $gamma) * $ctp;
    my $dt = $gamma * (abs($val - $yt) + $sdv) +  (1 - $gamma) * $dtp;

    my $nsi = ($si + 1) % $buckets;
    my($ctn, undef) = $me->_get_cd($nsi);
    my $ytn = ($at + $bt) * $ctn;

    $me->debug("hw $at, $bt, $ct, $dt => $ytn");

    $me->_put_ab($at, $bt);
    $me->_put_cd($si, $ct, $dt);

    $me->_smooth_c( $si );

    $me->{expect} = {
        y	=> $ytn,
        d	=> $dt,
        phase	=> 'active',
        index	=> $si,
    };

}

1;
