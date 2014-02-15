# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Nov-01 15:57 (EST)
# Function: misc graph data handling
#
# $Id: Argus::Graph::Data.pm,v 1.21 2011/11/03 14:52:03 jaw Exp $

package Argus::Graph::Data;
use strict;

use vars qw($MAGIC $HDR_SIZE $SAMP_SIZE $SAMP_NMAX);
use vars qw($HOURS_SIZE $HOURS_NMAX $DAYS_SIZE $DAYS_NMAX);

$MAGIC = "AGD4";	# Argus Graphing Data
$HDR_SIZE   = 1024;	# total size of header, currently mostly unused

# raw samples
$SAMP_SIZE  = 32;	# bytes per sample
$SAMP_NMAX  = 2048;	# default number of samples

# hourly summary data
$HOURS_SIZE = 48;
$HOURS_NMAX = 1024;

# daily summary data
$DAYS_SIZE  = 48;
$DAYS_NMAX  = 1024;

# Header:
#   magic,   lastT,    sampl_cnt, sampl_indx
#   hrs_cnt, hrs_indx, day_cnt,   day_indx
#
#   hrs_min, hrs_max,  hrs_nsamp, hrs_sigm
#   hrs_sigm2-------,  hrs_flags, unused,
#
#   day_min, day_max,  day_nsamp, day_sigm
#   day_sigm2-------,  day_flags, unused,
#
#   smp_nmax,hrs_nmax, day_nmax,  unused,
#
#   hrs_exp, hrs_delt, day_exp, day_delt,
#
# Data:
#   samples: {time, value, flags, expected, delta, unused...}
#   summary: {time, min, max, ave, stdev, nsamps, flags, expected, delta, unused...}


my $OLD3_MAGIC = 'AGD3';
my $OLD3_SAMP_SIZE  = 16;
my $OLD3_HOURS_SIZE = 32;
my $OLD3_DAYS_SIZE  = 32;


sub new {
    my $c = shift;
    my $name = shift;

    my $file = ($name =~ /^\//) ? $name : "$::datadir/gdata/$name";
    $c->new_file( $name, $file );
}

sub new_file {
    my $c = shift;
    my $name = shift;
    my $file = shift;

    my $me = {
	name => $name,
    };

    bless $me;
    my $fh = anon_fh();
    $me->{fd}= $fh;
    open( $fh, $file )
	|| return ::error( "'$file' is stubborn and refuses to open: $!" );
    binmode $fh;

    # read file header
    my $magic = $me->read_header();

    unless( $magic eq $MAGIC ){
	return ::error( "corrupt data file: $name" );
    }

    $me;
}


# But what Gherardo is it, who, as sample
# Of a lost race, thou sayest has remained
#   -- Dante, Divine Comedy
sub readallsamples {
    my $me = shift;

    my @samp;
    my $fh = $me->{fd};

    my $start = ($me->{sampl_index} - $me->{sampl_count} + $me->{sampl_nmax}) % $me->{sampl_nmax};
    # print STDERR "samples=$me->{sampl_count} index=$me->{sampl_index} start=$start\n";

    for( my $i=0; $i<$me->{sampl_count}; $i++ ){
	my $n = ($i + $start) % $me->{sampl_nmax};
	my $off = $n * $SAMP_SIZE + $me->{sampl_start};
	my $buf;
	seek( $fh, $off, 0 );
	read( $fh, $buf, $SAMP_SIZE );
        # RSN - include hwab delta
	my( $t, $v, $f, $exp, $delt ) = unpack( "NfNff", $buf );
	unless( $t ){
	    warn "corrupt data sample\n";
	    next;
	}
	push @samp, {
	    time   => $t,
	    value  => $v,
	    flag   => $f,
            expect => $exp,
            delta  => $delt,
	    ($f ? (color =>  ($f==2 ? 'gray' : 'red')) : ()),
	};
    }

    $me->{samples} = \@samp;
}

sub readsamples {
    my $me    = shift;
    my $limit = shift;

    $me->readallsamples();
    my $samp = $me->{samples};

    # remove end-errors
    if( @$samp > 1 ){
	shift @$samp
	    if( $samp->[0]{time} > $samp->[1]{time} );
    }

    # temporal limit
    if( @$samp && $limit ){

	while( @$samp && $samp->[0]{time} < $limit ){
	    shift @$samp;
	}
    }
}

# Here's the scroll,
# The continent and summary of my fortune
#   -- Shakespeare, Merchant of Venice
sub readsummary {
    my $me = shift;
    my $wh = shift;
    my $ns = shift;
    my $limit = shift;
    my( $fh, $start, $first, $cnt, $idx, $nmax, $nsmall, @samp );

    $fh = $me->{fd};
    # day+hours data is same, different offset
    if( $wh eq 'hours' ){
	$cnt   = $me->{hours_count};
	$idx   = $me->{hours_index};
	$start = $me->{hours_start};
	$nmax  = $me->{hours_nmax};
    }else{
	$cnt   = $me->{days_count};
	$idx   = $me->{days_index};
	$start = $me->{days_start};
	$nmax  = $me->{days_nmax};
    }

    # limit number of points
    $cnt = $ns if $cnt > $ns && ! $limit;

    $first = ($idx - $cnt + $nmax) % $nmax;

    for( my $i=0; $i<$cnt; $i++ ){
	my $n = ($i + $first) % $nmax;
	my $off = $n * $HOURS_SIZE + $start;
	my $buf;

	seek( $fh, $off, 0 );
	read( $fh, $buf, $HOURS_SIZE );
	my( $t, $min, $max, $ave, $sdv, $ns, $f, $exp, $del
	    ) = unpack( "NffffNNx4ff", $buf );
	unless( $t ){
	    warn "corrupt summary data point\n";
	    next;
	}

	$nsmall ++ unless $ns > 1;	# NB: otherwise the graphs get ugly
	push @samp, {
	    time   => $t,
	    flag   => $f,
	    min    => $min, max  => $max,
	    ave    => $ave, stdv => $sdv,
	    ns     => $ns,
	    value  => $ave,
            expect => $exp,
            delta  => $del,
	    ($f ? (color =>  ($f==2 ? 'gray' : 'red')) : ()),
	};
    }

    if( @samp > 1 ){
	shift @samp
	    if( $samp[0]{time} > $samp[1]{time} );
    }

    if( @samp ){
	# skip small partial edge values
	@samp = grep { $_->{ns} > 1 } @samp if $nsmall < $cnt/2;

	# temporal limit
	my $et = $samp[-1]{time};
	while( @samp && $samp[0]{time} < $limit ){
	    shift @samp;
	}
    }

    $me->{samples} = \@samp;
}

sub read_header {
    my $me = shift;
    my $fh = $me->{fd};

    my $buf;
    sysseek($fh, 0, 0);
    sysread($fh, $buf, $HDR_SIZE);

    ($me->{magic},       $me->{lastt},
     $me->{sampl_count}, $me->{sampl_index},
     $me->{hours_count}, $me->{hours_index},
     $me->{days_count},  $me->{days_index},

     $me->{hours_min},   $me->{hours_max},
     $me->{hours_nsamp}, $me->{hours_sigma},
     $me->{hours_sigm2}, $me->{hours_flags},

     $me->{days_min},   $me->{days_max},
     $me->{days_nsamp}, $me->{days_sigma},
     $me->{days_sigm2}, $me->{days_flags},

     $me->{sampl_nmax}, $me->{hours_nmax}, $me->{days_nmax},

     $me->{hours_expect}, $me->{hours_delta}, $me->{days_expect}, $me->{days_delta},

     ) = unpack( "a4N NN NN NN  ffNfdNx4  ffNfdNx4  NNNx4 ffff", $buf );

    $me->header_init();

    $me->{magic};
}

sub header_init {
    my $me = shift;

    $me->{sampl_nmax} ||= $SAMP_NMAX;
    $me->{hours_nmax} ||= $HOURS_NMAX;
    $me->{days_nmax}  ||= $DAYS_NMAX;

    $me->{sampl_start} = $HDR_SIZE;
    $me->{hours_start} = $me->{sampl_start} + $SAMP_SIZE  * $me->{sampl_nmax};
    $me->{days_start}  = $me->{hours_start} + $HOURS_SIZE * $me->{hours_nmax};

}

sub write_header {
    my $me = shift;
    my $fh = $me->{fd};
    my $hdr;

    $hdr = $MAGIC . pack( "N NN NN NN ffNfdNx4 ffNfdNx4 NNNx4 ffff",
			  $me->{lastt},
			  $me->{sampl_count}, $me->{sampl_index},
			  $me->{hours_count}, $me->{hours_index},
			  $me->{days_count},  $me->{days_index},

			  $me->{hours_min},   $me->{hours_max},
			  $me->{hours_nsamp}, $me->{hours_sigma},
			  $me->{hours_sigm2}, $me->{hours_flags},

			  $me->{days_min},   $me->{days_max},
			  $me->{days_nsamp}, $me->{days_sigma},
			  $me->{days_sigm2}, $me->{days_flags},

			  $me->{sampl_nmax}, $me->{hours_nmax}, $me->{days_nmax},
                          $me->{hours_expect}, $me->{hours_delta}, $me->{days_expect}, $me->{days_delta},

			  );
    sysseek( $fh, 0, 0 );
    syswrite($fh, $hdr );
}

sub upgrade {
    my $me = shift;

    return $me->upgrade_3to4() if $me->{magic} eq $OLD3_MAGIC;

    return ;
}

sub upgrade_3to4 {
    my $me = shift;

    my $fd = $me->{fd};

    my %dat;

    $me->{hours_start} = $me->{sampl_start} + $OLD3_SAMP_SIZE  * $me->{sampl_nmax};
    $me->{days_start}  = $me->{hours_start} + $OLD3_HOURS_SIZE * $me->{hours_nmax};

    my %info = (
	     s => { cnt => $me->{sampl_count}, oz => $OLD3_SAMP_SIZE,
		    str => $me->{sampl_start}, sz => $SAMP_SIZE },

	     h => { cnt => $me->{hours_count}, oz => $OLD3_HOURS_SIZE,
		    str => $me->{hours_start}, sz => $HOURS_SIZE },

	     d => { cnt => $me->{days_count},  oz => $OLD3_DAYS_SIZE,
		    str => $me->{days_start},  sz => $DAYS_SIZE },
            );

    # read all the data
    foreach my $k (qw(s h d)){

        sysseek($fd, $info{$k}{str}, 0);
        for (1 .. $info{$k}{cnt}){
            my $buf;
            sysread($fd, $buf, $info{$k}{oz});
            push @{$dat{$k}}, $buf;
        }
    }

    # write header
    $me->{magic} = $MAGIC;
    $info{h}{str} = $me->{hours_start} = $me->{sampl_start} + $SAMP_SIZE  * $me->{sampl_nmax};
    $info{d}{str} = $me->{days_start}  = $me->{hours_start} + $HOURS_SIZE * $me->{hours_nmax};
    $me->write_header();

    # write extended data
    foreach my $k (qw(s h d)){
        my $ext_l = $info{$k}{sz} - $info{$k}{oz};
        my $ext_b = "\0" x $ext_l;

        sysseek($fd, $info{$k}{str}, 0);
        for my $d (@{$dat{$k}}){
            syswrite($fd, $d, $info{$k}{oz});
            syswrite($fd, $ext_b, $ext_l);
        }
    }

    return $MAGIC;
}



# change the file's section sizes
sub resize {
    my $me = shift;
    my $ss = shift;
    my $hs = shift;
    my $ds = shift;
    my $fh = $me->{fd};

    # default to current size
    $ss ||= $me->{sampl_nmax};
    $hs ||= $me->{hours_nmax};
    $ds ||= $me->{days_nmax};

    my %d = (
	     s => { idx => $me->{sampl_index}, cnt => $me->{sampl_count}, nx => $ss,
		    max => $me->{sampl_nmax},  str => $me->{sampl_start}, sz => $SAMP_SIZE },

	     h => { idx => $me->{hours_index}, cnt => $me->{hours_count}, nx => $hs,
		    max => $me->{hours_nmax},  str => $me->{hours_start}, sz => $HOURS_SIZE },

	     d => { idx => $me->{days_index},  cnt => $me->{days_count},  nx => $ds,
		    max => $me->{days_nmax},   str => $me->{days_start},  sz => $DAYS_SIZE },
	     );

    foreach my $k (qw(s h d)){
	my $x = $d{$k};

	# read entire section
	my $start = ($x->{idx} - $x->{cnt} + $x->{max}) % $x->{max};
	my $len   = $x->{max} - $start;
	$start *= $x->{sz}; $len *= $x->{sz};

	my $buf;
	sysseek($fh, $start + $x->{str}, 0);
	sysread($fh, $buf, $len);

	if( $start ){
	    # read wraparound
	    sysseek($fh, $x->{str}, 0);
	    sysread($fh, $buf, $start, $len);
	}

	# new header values?
	# new count is always either: old count, new nmax
	# new index is always either: 0, old count

	$x->{ncnt} = $x->{cnt} > $x->{nx} ? $x->{nx} : $x->{cnt};

	if( $x->{ncnt} < $x->{cnt} ){
	    # shrink
	    substr($buf, 0, ($x->{cnt} - $x->{ncnt}) * $x->{sz}, ''); 	# remove front
	    $x->{nidx} = 0;
	}else{
	    $x->{nidx} = $x->{cnt} % $x->{nx};
	}

	# adjust buffer size
	if( length($buf) < $x->{nx} * $x->{sz} ){
	    $buf .= "\0" x ($x->{nx} * $x->{sz} - length($buf)); 	# add extra at end
	}else{
	    $buf = substr($buf, 0, $x->{nx} * $x->{sz}); 		# remove extra at end
	}
	$x->{data} = $buf;
    }

    # rejigger header

    $me->{sampl_index} = $d{s}{nidx};
    $me->{hours_index} = $d{h}{nidx};
    $me->{days_index}  = $d{d}{nidx};
    $me->{sampl_count} = $d{s}{ncnt};
    $me->{hours_count} = $d{h}{ncnt};
    $me->{days_count}  = $d{d}{ncnt};
    $me->{sampl_nmax}  = $d{s}{nx};
    $me->{hours_nmax}  = $d{h}{nx};
    $me->{days_nmax}   = $d{d}{nx};


    $me->{sampl_start} = $HDR_SIZE;
    $me->{hours_start} = $me->{sampl_start} + $SAMP_SIZE  * $me->{sampl_nmax};
    $me->{days_start}  = $me->{hours_start} + $HOURS_SIZE * $me->{hours_nmax};

    # write back out
    $me->write_header();
    sysseek($fh, $me->{sampl_start}, 0);
    syswrite($fh, $d{s}{data});

    sysseek($fh, $me->{hours_start}, 0);
    syswrite($fh, $d{h}{data});

    sysseek($fh, $me->{days_start}, 0);
    syswrite($fh, $d{d}{data});
}


sub anon_fh {
    do { local *FILEHANDLE };
}

1;

