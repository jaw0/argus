# -*- perl -*-

# Copyright (c) 2011
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2011-Oct-15 14:21 (EDT)
# Function: holt-winters abberant behavior detection
#
# $Id: Argus::HWAB.pm,v 1.12 2012/09/03 15:24:53 jaw Exp $

package Argus::HWAB;
use POSIX;
use strict;

my $TWIN        = 300;
my $TWOWEEKS    = 2 * 7 * 24 * 3600;
my $START       = $^T;
my $BOOTK       = 0.025;
my $BOOTDK	= 0.90;
my $LONGK       = 0.0005;
my $KDEVIANT    = 1.5;
my $SMOOTH      = 2;

my %DB;
my $db;
my $init;
my %KNOWN;	# for fast cleanup of entries no longer in use

sub init {

    # init on first use
    return if $init;
    $init = 1;

    # tie db file
    my $file = "$::datadir/stats/hwab.db";

    $db = tie %DB, $::DATABASE, $file or die "cannot tie $::DATABASE $file: $!\n";
    ::loggit( "loading holt/winters from $file", 0);

    _mkknown();
    _cleanup();

    Cron->new( freq 	=> 35 * 3600,
               info	=> 'clean up hwab file',
               func	=> \&_cleanup,
    );
}

END {
    _save_known();
    $db = undef;
    untie %DB;
}

sub _cleanup {

    # clean out old/unused entries
    my @del;
    for my $kk ( keys %KNOWN ){
        my $start = $KNOWN{$kk};
        if( $start < $^T - $TWOWEEKS ){
            push @del, $kk;
        }
    }

    _delete( $_ ) for @del;
    _save_known();
    sync();
}

sub _delete {
    my $key = shift;

    # ::loggit("no longer keeping H/W data: $key", 0);

    my $buckets = $DB{"$key/buckets"};
    for my $k ('a', 'a boot', 'ab', 'b', 'b boot', 'c boot', 'd boot', 'created', 'cstart', 'conf', 'buckets'){
        delete $DB{"$key/$k"};
    }

    for my $i (0 .. $buckets){
        delete $DB{"$key/c $i"};
        delete $DB{"$key/d $i"};
        delete $DB{"$key/cd $i"};
    }

    delete $KNOWN{$key};
}

sub new {
    my $class  = shift;
    my $name   = shift;
    my $period = shift;
    my $alpha  = shift;
    my $beta   = shift;
    my $gamma  = shift;
    my $zeta   = shift;
    my $xdelta = shift;		# not used
    my $debug  = shift;

    init();

    my $me = bless {
        name		=> $name,
        period		=> $period,
        period_boot	=> $period * 2,
        buckets		=> $period / $TWIN,
        twin		=> $TWIN,
        alpha		=> $alpha,
        beta		=> $beta,
        gamma		=> $gamma,
        zeta		=> $zeta,
        xdelta  	=> $xdelta,
        debug		=> $debug,
    }, $class;

    $me->debug("new: $alpha, $beta, $gamma");
    $me->_start();

    return $me;
}

sub reset {
    my $me = shift;

    $me->debug("reseting");
    _delete( $me->{name} );
    delete $me->{current};
    delete $me->{expect};
    $me->_start();
}

sub debug {
    my $me  = shift;
    my $msg = shift;

    return unless $me->{debug};
    $me->{debug}->("hwab $msg");
}

sub _mkknown {

    my $all = $DB{_ALL};

    if( $all ){
        my @all = split /\0/, $all;
        if( $all[1] =~ /^\d+$/ ){
            # list of keys + times
            %KNOWN = @all;
        }else{
            # list of keys only
            %KNOWN = map {$_ => $DB{"$_/cstart"}} @all;
        }
        return;
    }

    # upgrade data
    while( my($k,$v) = each %DB ){
        next unless $k =~ /cstart$/;

        (my $kk = $k) =~ s|/cstart$||;
        $KNOWN{$kk} = $v;
    }

    _save_known();
}

sub _save_known {
    $DB{_ALL} = join("\0", %KNOWN);
}

sub _addknown {
    my $me = shift;

    return if defined $KNOWN{$me->{name}};

    $KNOWN{$me->{name}} = $^T;
    _save_known();
}

sub _touch {
    my $me = shift;

    $KNOWN{$me->{name}} = $^T;
}

sub _key {
    my $me  = shift;
    my $key = shift;

    return "$me->{name}/$key";
}

sub _put {
    my $me  = shift;
    my $key = shift;
    my $val = shift;

    $DB{ $me->_key($key) } = $val;
    $me->{_db}{$key} = $val unless $key =~ /\d/;
}

sub sync {
    $db->sync();
}

sub _get {
    my $me  = shift;
    my $key = shift;

    # try cache, then db
    return $me->{_db}{$key} if defined $me->{_db}{$key};
    return $DB{ $me->_key($key) };
}

sub _put_ab {
    my $me  = shift;
    my( $a, $b ) = @_;

    $me->_put('ab', "$a,$b");
}

sub _get_ab {
    my $me  = shift;

    my $ab = $me->_get('ab');
    if( $ab ){
        my($a, $b) = split /,/, $ab;
        return ($a, $b);
    }
    return ( $me->_get('a'), $me->_get('b') );
}

sub _put_cd {
    my $me  = shift;
    my $si  = shift;
    my( $c, $d ) = @_;

    $me->_put("cd $si", "$c,$d");
}

sub _get_cd {
    my $me  = shift;
    my $si  = shift;

    my $cd = $me->_get("cd $si");
    if( $cd ){
        my($c, $d) = split /,/, $cd;
        return ($c, $d);
    }
    return ( $me->_get("c $si"), $me->_get("d $si") );
}

sub _is_compat {
    my $me  = shift;
    my $cfa = shift;
    my $cfb = shift;

    my @cfa = split /,/, $cfa;
    my @cfb = split /,/, $cfb;
    # model, twin, + period
    return ($cfa[0] eq $cfb[0]) && ($cfa[1] eq $cfb[1]);
}

sub _start {
    my $me   = shift;

    # initialize

    return if $me->{current};

    # reset if params change
    my $new_conf = ref($me) . ";$me->{twin},$me->{period},$me->{alpha},$me->{beta},$me->{gamma}";
    my $old_conf = $me->_get('conf');

    if( $old_conf && !$me->_is_compat($old_conf, $new_conf) ){
        $me->debug("config changed. reseting ($old_conf)");
        _delete( $me->{name} );
    }

    my $create = $me->_get('created');

    $me->_put('conf', $new_conf) if !$create || !$old_conf;

    unless( $create ){
        $create = int($^T);

        $me->_put('created', $create);
        $me->_put('cstart',  $create);
        $me->_put('buckets', $me->{buckets});	# for cleanup
        $me->_addknown();
    }

    $me->{created} = $create;

    $me->{current} = {
        start	=> $me->_get('cstart'),
    };

    # extended downtime?
    if( $^T - $me->{current}{start} > 5 * $me->{twin} ){

        my($at,$bt) = $me->_get_ab();
        if( $at ){
            my $adj = int( ($^T - $me->{current}{start}) / $me->{twin} ) - 1;
            $me->{current}{start} += $adj * $me->{twin};
            $me->_put_ab($at + $adj*$bt, $bt);
        }else{
            # do nothing during boot phase?
        }
    }


    $me->_init_expect();

}

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
    my $dt  = MAX( $dtp, 2 * $dtx );
    $btb += $val - $ctb;
    # B = average derivative
    my $bt  = $btb / ($nsamp + 1);

    $me->debug("boot $btb, $ctp, $dtp => $bt, $ct, $dt");

    # A = intercept of B*t
    $me->_put_ab($nsamp * $bt, $bt);
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

# smooth out c + d. just a little bit.
sub _smooth_c {
    my $me = shift;
    my $si = shift;

    $me->debug("smoothing $si");
    my $max = $me->{buckets};
    $si --;

    my($ctot, $dtot);
    my $cnt;
    for my $j (- $SMOOTH .. $SMOOTH){
        my $i = ($si + $j + $max) % $max;
        my($c,$d) = $me->_get_cd($i);
        next unless $c;

        my $k = $j ? 1 : 2;	# weighed average
        $ctot += $c * $k;
        $dtot += $d * $k;
        $cnt += $k;
    }

    return unless $cnt;
    $me->_put_cd($si, $ctot / $cnt, $dtot / $cnt);
}

sub _init_expect {
    my $me = shift;

    my $si      = ($me->{current}{start} / $me->{twin}) % $me->{buckets};

    my($atp, $btp) = $me->_get_ab();
    my($ctp, $dtp) = $me->_get_cd($si);

    return unless $atp && $btp && $ctp && $dtp;

    $me->{expect} = {
        y	=> $atp + $btp + $ctp,
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
    my $age     =  $me->{current}{start} - $me->{created};
    my $nsp     = $age % $buckets;
    my $nsamp   = $age / $me->{twin};

    $me->debug("hw in: val $val, sdv $sdv, si $si");

    return $me->_bootstrap($val, $sdv, $si) if $age < $me->{period_boot};

    my($isdev, $dvdir);
    ($val, $sdv, $isdev, $dvdir) = $me->_clean_value($val, $sdv, $si);
    my($alpha, $beta, $gamma)    = $me->_alpha_beta_gamma($val, $isdev, $dvdir);

    my($atp, $btp) = $me->_get_ab();
    my($ctp, $dtp) = $me->_get_cd($si);

    # missing data - something stopped during boot phase, patch hole
    unless( defined $ctp ){
        my $max = $me->{buckets};
        my $pi = ($si - 1 + $max) % $max;
        my($cx, $dx) = $me->_get_cd($pi);
        $cx  = $val unless defined $cx;
        $ctp = $dtp = $BOOTK * $val + (1 - $BOOTK) * $cx;
    }

    my $yt = $atp + $btp + $ctp;

    my $at = $alpha * ($val - $ctp)    +  (1 - $alpha) * ($atp + $btp);
    my $bt = $beta  * ($at - $atp)     +  (1 - $beta)  * $btp;
    my $ct = $gamma * ($val - $at)     +  (1 - $gamma) * $ctp;
    my $dt = $gamma * (abs($val - $yt) + $sdv) +  (1 - $gamma) * $dtp;

    my $nsi = ($si + 1) % $buckets;
    my($ctn, undef) = $me->_get_cd($nsi);
    my $ytn = $at + $bt + $ctn;

    $me->debug("hw a $at, b $bt, c $ct, d $dt => $ytn");

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


sub add {
    my $me  = shift;
    my $val = shift;

    my $now = $^T;

    $me->debug("add $val");
    $me->{current}{count}  ++;
    $me->{current}{total}  += $val;
    $me->{current}{total2} += $val * $val;

    my $ave = $me->{current}{total} / $me->{current}{count};
    my $sdv = sqrt($me->{current}{total2} / $me->{current}{count} - $ave * $ave);

    while( $me->{current}{start} + $me->{twin} <= $now ){
        $me->_hw($ave, $sdv, $now);

        $me->{current}{count} = $me->{current}{total} = $me->{current}{total2} = 0;
        $me->{current}{start} += $me->{twin};
        $me->_put('cstart', $me->{current}{start});
        $me->_touch();
    }

}

# lessen the impact of outliers - bound value
sub _clean_value {
    my $me  = shift;
    my $val = shift;
    my $sdv = shift;
    my $si  = shift;

    return ($val, $sdv) unless $me->{current};
    return ($val, $sdv) unless $me->{expect};
    return ($val, $sdv) unless $me->{expect}{d};

    # looks ok
    return ($val, $sdv) if $val < $me->{expect}{y} + $KDEVIANT * $me->{expect}{d}
      && $val > $me->{expect}{y} - $KDEVIANT * $me->{expect}{d};

    # would it be ok one slot over?
    my $bkt = $me->{buckets};

    my ($ctp, $dtp) = $me->_get_cd( ($si - 1 + $bkt) % $bkt );
    my ($ctn, $dtn) = $me->_get_cd( ($si + 1) % $bkt );
    my($at, $bt)    = $me->_get_ab();

    my $yp = $at + 0 * $bt + $ctp;			# prev y
    my $yn = $at + 2 * $bt + $ctn;			# next y

    # if ok in adjacent slot, return direction
    # ok in previous slot
    return ($val, $sdv, 0, -1) if $val < $yp + $KDEVIANT * $dtp
      && $val > $yp - $KDEVIANT * $dtp;

    # ok in next slot
    return ($val, $sdv, 0,  1) if $val < $yn + $KDEVIANT * $dtn
      && $val > $yn - $KDEVIANT * $dtn;


    # not ok

    if( $val > $me->{expect}{y} ){
        return ( $me->{expect}{y} + $KDEVIANT * $me->{expect}{d}, $sdv, 1 );
    }else{
        return ( $me->{expect}{y} - $KDEVIANT * $me->{expect}{d}, $sdv, 1 );
    }
}

# lessen the impact of deviants - reduce alpha/beta
sub _alpha_beta_gamma {
    my $me  = shift;
    my $val = shift;
    my $isd = shift;	# deviant?
    my $dir = shift;

    if( $isd ){
        return ($me->{alpha} * $me->{zeta},
                $me->{beta}  * $me->{zeta},
                $me->{gamma});
    }

    return ($me->{alpha}, $me->{beta}, $me->{gamma});
}

# how aberant are we?
sub deviation {
    my $me  = shift;
    my $val = shift;

    # too soon to tell?
    return unless $me->{current};
    return unless $me->{expect};
    return unless $me->{expect}{d};
    my $elapsed = $me->{current}{start} - $me->{created};
    return unless $elapsed > $me->{period_boot};

    my $d = abs($me->{expect}{y} - $val);
    my $a = $d / $me->{expect}{d};

    return $a;
}

sub age {
    my $me = shift;

    return $^T - $me->{created};
}


1;
