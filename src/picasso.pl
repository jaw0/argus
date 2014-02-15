#!__PERL__
# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Nov-01 11:54 (EST)
# Function: lay paint on canvas. make pretty graphs.
#
# $Id: picasso.pl,v 1.29 2012/09/16 18:52:50 jaw Exp $

# Computers are useless. They can only give you answers.
#   -- Picasso

use lib('__LIBDIR__');
require "conf.pl";
use Chart::Strip;
use Argus::Encode;
use Argus::Graph::Data;
use POSIX;
use strict;

BEGIN {
    eval {
	require GD;
	GD->import();
    };
    if($@){
	die "cannot generate graphs. GD not installed.\n";
    }
}

my %opt;

# get args from command line
while( @ARGV ){
    last unless $ARGV[0] =~ /^-/;
    my $k = shift @ARGV;
    my $v = shift @ARGV;
    $k =~ s/^-//;
    $opt{$k} = $v;
}

# get args from stdin
if( $opt{stdin} ){

    alarm(10);	# trap for protocol botch

    # until eof or blank line
    while(<STDIN>){
	chop;
	last unless $_;

	# -param: value
	# objectname
	if( /^-(.*)/ ){
	    my($k, $v) = split /:\s*/, $1, 2;
	    $opt{$k} = $v;
	}else{
	    push @ARGV, $_;
	}
    }
    alarm(0);
}

# make sure we aren't using old argus with new picasso
error('version mismatch') if $opt{s};
# and other errors...
error( $opt{error} )      if $opt{error};

my $which  = $opt{which};
my $size   = $opt{size};
my @labels = map {decode($_)} split /\s+/, $opt{clabels};

binmode STDOUT;
$| = 1;


# What is your favorite color?
# Blue.  No yel--  Auuuuuuuugh!
#   -- Monty Python, Holy Grail
my @colors  = qw(00FF00 DD33DD 00FFFF FFAAAA AAFFAA AAAAFF
		 FFCC44 FF44CC 44CC88 88CC44 4488CC 8844CC);
usecolors(decode($opt{gr_colors}));

# barstyle: '', minmax, stddev
# grstyle:  line, filled

my $grstyle  = 'line';
my $barstyle = $which eq 'samples' ? '' : $opt{barstyle};
$barstyle = '' if $barstyle eq 'none';

if( $size =~ /(\d+)x(\d+)/ ){
    $opt{gr_width}  = $1;
    $opt{gr_height} = $2;
    $size = 'full';
}

my @dataopts;
my @imgopts = (
	       transparent      => $opt{transparent},
	       draw_border      => $opt{drawborder},
	       draw_grid        => $opt{drawgrid},
	       binary           => $opt{gr_binary},
	       logscale         => $opt{logscale},
	       grid_on_top      => $opt{gridontop},
	       data_label_style => $opt{labelstyle},
	       limit_factor     => 4,
	       );

my $width;
if( $size eq 'thumb' ){
    push @imgopts, width => ($width = 200), height => 80;
    push @imgopts, draw_data_labels => 0, draw_tic_labels => 0;

    push @dataopts, smooth   => $opt{gr_smooth};
    push @dataopts, shadow   => {dx => 1, dy => 1, dw => 0} if $opt{gr_drop_shadow};
}else{
    push @imgopts, height    => ($opt{gr_height} || 192);
    push @imgopts, width     => ($width = $opt{gr_width} || 640);
    push @imgopts, margin_right => 16;
    push @imgopts, title     => decode($opt{title});
    push @imgopts, x_label   => decode($opt{xlabel});
    push @imgopts, y_label   => decode($opt{ylabel});

    push @dataopts, thickness => decode($opt{gr_line_thickness});
    push @dataopts, smooth    => $opt{gr_smooth};
    push @dataopts, shadow    => {dx => 2, dy => 2, dw => 3} if $opt{gr_drop_shadow};
}

my $img = Chart::Strip->new( @imgopts );

my $colorn = 0;
my $notenough = 0;
foreach my $n (@ARGV){
    my $m = Argus::Graph::Data->new($n);
    my $color = color($colorn++);
    my $label = shift @labels;

    if( $which eq 'samples' ){
        my $limit = $^T - ($opt{gr_xrange_samples} || 36*3600);
	$m->readsamples( $limit );

	if( @{$m->{samples}} < 2 ){
	    $notenough ++;
	    next;
	}

        subsample( $m, $width );

        my $hwab;
        $hwab = add_hw_prediction($m) if @ARGV==1 && $size ne 'thumb' && $opt{gr_show_hwab};
        push @dataopts, shadow => undef if $hwab;

	$img->add_data( $m->{samples}, {style => $grstyle, color => $color, label => $label,
                                        @dataopts,
                        } );

    }else{
        my $limit = $^T - ($opt{"gr_xrange_$which"} ||($which eq 'hours' ? 180 * 3600 : 90 * 24 * 3600));

	# limit to either 576 points, or specified range
	$m->readsummary( $which, 576, $limit );
	# print STDERR "data: ", scalar(@{$m->{samples}}), "\n";

	if( @{$m->{samples}} < 2 ){
	    $notenough ++;
	    next;
	}

        subsample( $m, $width );

        add_bars($m) if $barstyle && $barstyle ne 'none' && $size ne 'thumb';

        my $hwab;
        $hwab = add_hw_prediction($m) if @ARGV==1 && $size ne 'thumb' && $opt{gr_show_hwab};
        push @dataopts, shadow => undef if $hwab;

	$img->add_data( $m->{samples}, {style => $grstyle, color => $color, label => $label,
                                        @dataopts,
                        } );
    }
}

if( $notenough >= @ARGV ){
    error( 'not enough data yet' );
}

# ICK - reorder data: put range graphs 1st
my @d;
push @d, grep { $_->{opts}{style} eq 'range' } @{$img->{data}};
push @d, grep { $_->{opts}{style} ne 'range' } @{$img->{data}};
$img->{data} = \@d;

setrange( $img, decode($opt{gr_range}) ) if $opt{gr_range};
$img->plot();

if( $size ne 'thumb' ){
    logoize($img);

    if( $barstyle ){
	my $im = $img->gd();
	my $y  = $img->{margin_top} > 12 ? 2 : -2;
	$im->string(gdSmallFont, 4,  $y, "ave",   $img->{color}{green});
	$im->string(gdSmallFont, 24, $y, $barstyle,  $img->{color}{blue});
    }
}


#..., then draw the model;
#   -- Shakespeare, King Henry IV
if( $opt{filetype} eq 'gif' ){
    print $img->gif();
}else{
    print $img->png();
}
exit 0;

################################################################

sub add_bars {
    my $m = shift;

    my @data;

    if( $barstyle eq 'minmax' ){
        @data = map {
            {
                time => $_->{time},
                min  => $_->{min},
                max  => $_->{max},
            }
        } @{$m->{samples}};
    }
    if( $barstyle eq 'stddev' ){
        my $n = $opt{gr_bar_nstddev} || 1;

        @data = map {
            {
                time => $_->{time},
                min  => $_->{ave} - $n * $_->{stdv},
                max  => $_->{ave} + $n * $_->{stdv},
            }
        } @{$m->{samples}};
    }

    $img->add_data( \@data, {style => 'range', color => $opt{gr_bar_color}} );
}


# include holt-winters prediction on graph?
sub add_hw_prediction {
    my $m = shift;

    my $enabled;
    my @data = map {
        $enabled = 1 if $_->{expect};
        {
            time => $_->{time},
            min  => $_->{expect} - $_->{delta},
            max  => $_->{expect} + $_->{delta},
      };
    } @{$m->{samples}};

    return unless $enabled;

    # remove initial 0s (probably wasn't enabled yet)
    my $z;
    @data = grep {
        $z || $_->{max} && ($z=1)
    } @data;

    $img->add_data( \@data, {
        style     => 'range',
        color     => $opt{gr_hwab_color},
        label     => '',
        shadow    => undef,

    } );

    # prevent this data from being considered in determining the graph ranges
    # chart::strip should add a feature
    $img->{xd_max} = $img->{xd_min} = $img->{yd_max} = $img->{yd_min} = undef
      if $opt{gr_hwab_range_ignore};

    1;
}

sub subsample {
    my $m     = shift;
    my $width = shift;

    my $samp = $m->{samples};
    if( @$samp > $width/2 ){
        # more samples than we have room for. subsample
        my $n = ceil( 2 * @$samp / $width );

        my @s;
        for my $i (0 .. $#{$samp}){
            next if $i % $n;

            my $ct = 1;
            my $tt = $samp->[$i]{value};
            for my $j (0 .. $n/2){
                if( $i-$j >= 0 ){ $ct ++; $tt += $samp->[$i-$j]{value}; }
                if( $i+$j <= $#{$samp} ){ $ct ++; $tt += $samp->[$i+$j]{value}; }
            }

            $samp->[$i]{value} = $tt / $ct;
            push @s, $samp->[$i];
        }

        $m->{samples} = \@s;
    }
}

sub error {
    my $msg = shift;
    my $im;

    print STDERR "picasso: ERROR $msg\n";

    $im = new GD::Image(200, 80);
    my $blk = $im->colorAllocate(0,0,0);
    my $red = $im->colorAllocate(0xFF,0x88,0x88);

    $im->filledRectangle(0,0, 199,79, $red);
    $im->rectangle(0,0, 199,79, $blk);
    my $grtitle = $opt{errortitle} || 'PICASSO: GRAPH ERROR';
    $im->string(GD::gdMediumBoldFont, 4, 2, $grtitle, $blk);
    my @a = grep {$_ || ()} split /(.{25})/, $msg;
    my $y = (@a > 1) ? 16 : 40;
    foreach (@a){
	s/^\s+//;
	$im->string(GD::gdSmallFont, 4, $y, $_, $blk);
	$y += 10;
    }

    if( $opt{filetype} eq 'gif' ){
	print $im->gif();
    }else{
	print $im->png();
    }

    exit -1;
}

sub color {
    my $n = shift;

    return 'green' if @ARGV == 1;
    $colors[ $n % @colors ];
}

# Nor long the sun his daily course withheld,
# But added colors to the world reveal'd:
# When early Turnus, wak'ning with the light,
#   -- Virgil, Aeneid
sub usecolors {
    my $cs = shift;
    my @c;

    @c = split /\s+/, $cs;
    unshift @colors, @c;
}

# I hear beyond the range of sound,
# I see beyond the range of sight,
# New earths and skies and seas around,
# And in my day the sun doth pale his light.
#   -- Thoreau, Inspiration
sub setrange {
    my $img = shift;
    my $r   = shift;
    my( $l, $h, $x ) = split /\s*-\s*/, $r;

    ($l, $h) = (-$h, $x) if $l eq '';
    $h = -$x if $h eq '';

    $img->set_y_range($l, $h);
}

sub logoize {
    my $img = shift;
    my $im = $img->gd();

    # Aldeborontiphoscophornio! Where left you Chrononhotonthologos?
    #   -- Henry Carey, Chrononhotonthologos
    my @data = ([1, 80, 2], [4, 79, 0], [2, 78, 1], [4, 77, 0], [1, 76, 3], [2, 74, 1], [4, 73, 0],
    [1, 73, 0], [4, 72, 0], [1, 72, 0], [2, 71, 1], [4, 69, 0], [1, 69, 0], [4, 68, 0], [1, 68, 0],
    [4, 67, 0], [1, 67, 0], [2, 66, 1], [1, 63, 1], [1, 62, 1], [3, 59, 0], [1, 59, 0], [3, 58, 1],
    [1, 58, 0], [4, 57, 0], [1, 57, 1], [2, 56, 1], [1, 55, 2], [4, 54, 0], [2, 53, 1], [4, 52, 0],
    [1, 51, 3], [3, 49, 0], [1, 48, 5], [5, 47, 0], [3, 47, 0], [3, 46, 1], [3, 44, 0], [4, 43, 0],
    [2, 43, 0], [4, 42, 0], [2, 42, 0], [0, 41, 4], [4, 39, 0], [1, 39, 0], [4, 38, 0], [1, 38, 0],
    [4, 37, 0], [1, 37, 0], [2, 36, 1], [2, 34, 0], [4, 33, 0], [1, 33, 0], [2, 32, 4], [4, 31, 0],
    [1, 28, 1], [1, 27, 1], [4, 24, 0], [2, 24, 0], [4, 23, 0], [1, 23, 1], [3, 22, 1], [1, 22, 0],
    [3, 21, 0], [1, 21, 0], [1, 19, 3], [2, 18, 0], [1, 17, 0], [2, 16, 2], [1, 14, 3], [4, 13, 0],
    [2, 13, 0], [0, 13, 0], [4, 12, 0], [2, 12, 0], [0, 12, 0], [3, 11, 0],  [3, 9, 0],  [4, 8, 0],
    [3, 7, 0],   [1, 6, 3],  [1, 4, 3],  [4, 3, 0],  [2, 3, 0],  [4, 2, 0],  [1, 2, 0],  [2, 1, 1] );

    foreach my $l (@data){
	foreach my $i ($l->[0] .. $l->[0] + $l->[2]){
	    $im->setPixel($img->{width} - 9 + $i, 2 + $l->[1], $img->{color}{blue});
	}
    }
}

