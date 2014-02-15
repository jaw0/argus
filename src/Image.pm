# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Nov-01 16:11 (EST)
# Function: image drawing
#
# $Id: Image.pm,v 1.17 2004/04/28 20:04:46 jaw Exp $

package Image;
use GD;
use POSIX;
use Argus::Encode;

sub new {
    my $c = shift;
    my $size = shift;
    my $me = {
	size => $size,
	ngraphs => 0,
	graphno => 0,
	grid    => 0,
	# ...
    };

    if( $size eq 'thumb' ){
	$me->{xdim}  = 160;
	$me->{ydim}  = 64;
	$me->{xmarl} = 8; $me->{xmarr} = 8;
	$me->{ymart} = 8; $me->{ymarb} = 8;
    }else{
	$me->{xdim} = 640;
	$me->{ydim} = 192;
	# ymarb includes space for tic-labels but not xlabel
	# xmarr includes space for logo
	# xmarl + ymart do not include space for ylabel, tic-labels, or title
	# the things not included will be calculated based on string sizes on the fly
	$me->{xmarl} = 2; $me->{xmarr} = 16;
	$me->{ymart} = 8; $me->{ymarb} = 24;
    }
    
    bless $me;
    $me->adjust();
    
    my $im = new GD::Image($me->{xdim}, $me->{ydim});
    $me->{img} = $im;
    $me->{color}{white} = $im->colorAllocate(255,255,255);
    $me->{color}{black} = $im->colorAllocate(0,0,0);
    $me->{color}{blue}  = $im->colorAllocate(0, 0, 255);
    $me->{color}{red}   = $im->colorAllocate(255, 0, 0);
    $me->{color}{grn}   = $im->colorAllocate(0, 255, 0);
    $me->{color}{gray}  = $im->colorAllocate(128, 128, 128);

    # some colors...
    $me->usecolors('00FF00 DD33DD 00FFFF FFAAAA AAFFAA AAAAFF
                    FFCC44 FF44CC 44CC88 88CC44 4488CC 8844CC' );

    $im->setStyle(gdTransparent, $me->{color}{gray}, gdTransparent, gdTransparent);
    $im->interlaced('true');

    $me->logoize() if $me->{ydim} > 128 && $me->{xmarr} > 10;
    $me;
}

# The axis of the earth sticks out visibly through the centre of each and every town or city.
#   -- Oliver Wendell Holmes, The Autocrat of the Breakfast-Table    
sub axii {
    my $me = shift;
    my $im = $me->{img};
    # draw axii

    $im->line( $me->xpt(-1), $me->ypt(-1), $me->xpt(-1), $me->ypt($me->{ymax}), $me->{color}{black});
    $im->line( $me->xpt(-1), $me->ypt(-1), $me->xpt($me->{xmax}), $me->ypt(-1), $me->{color}{black});
    
    # 'Talking of axes,' said the Duchess, 'chop off her head!'
    #   -- Alice in Wonderland
}

sub border {
    my $me = shift;
    $me->{img}->rectangle(0, 0, $me->{xdim}-1, $me->{ydim}-1, $me->{color}{black});
}

sub transparent {
    my $me = shift;
    $me->{img}->transparent($me->{color}{white});
}

sub logscale {
    my $me = shift;
    $me->{logscale} = 1;
}

sub usegrid {
    my $me = shift;
    $me->{grid} = 1;
}

sub usebinary {
    my $me = shift;
    $me->{binary} = 1;
}

# Nor long the sun his daily course withheld, 
# But added colors to the world reveal'd: 
# When early Turnus, wak'ning with the light, 
#   -- Virgil, Aeneid
sub usecolors {
    my $me = shift;
    my $cs = shift;
    my( @c, @r );

    @c = split /\s+/, $cs;
    foreach my $c (@c){
	my($r,$g,$b) = map {hex} unpack('a2 a2 a2', $c);
	my $i = $me->{img}->colorAllocate($r, $g, $b);
	push @r, $i;
    }
    unshift @{$me->{colors}{RGB}}, @c;
    unshift @{$me->{colors}{use}}, @r;
}

sub png {
    my $me = shift;
    $me->{img}->png();
}

# xpt, ypt - convert graph space => image space
sub xpt {
    my $me = shift;
    my $pt = shift;

    $pt + $me->{xmarl};
}

sub ypt {
    my $me = shift;
    my $pt = shift;

    # make 0 bottom
    $me->{ydim} - $pt - $me->{ymarb};
}

# xdatapt, ydatapt - convert data space => image space
sub xdatapt {
    my $me = shift;
    my $pt = shift;

    $me->xpt( ($pt - $me->{xd_min}) * $me->{xd_scale} );
}

sub ydatapt {
    my $me = shift;
    my $pt = shift;

    $pt = $pt < $me->{yd_min} ? $me->{yd_min} : $pt;
    
    $me->ypt( ($pt - $me->{yd_min}) * $me->{yd_scale} );
}

# choose proper color for plot
sub color {
    my $me = shift;
    my $fl = shift;

    # What is your favorite color?
    # Blue.  No yel--  Auuuuuuuugh!
    #   -- Monty Python, Holy Grail
    
    return $me->{color}{gray} if $fl == 2;
    return $me->{color}{red}  if $fl;
    return $me->{color}{grn}  if $me->{ngraphs} == 1;
    return $me->{colors}{use}[$me->{graphno} % @{$me->{colors}{use}}];
}

# I hear beyond the range of sound,
# I see beyond the range of sight,
# New earths and skies and seas around,
# And in my day the sun doth pale his light.
#   -- Thoreau, Inspiration
sub setrange {
    my $me = shift;
    my $r  = shift;
    my( $l, $h, $x ) = split /\s*-\s*/, $r;

    ($l, $h) = (-$h, $x) if $l eq '';
    $h = -$x if $h eq '';

    $me->{yd_min} = $l if defined($l) && $l ne '';
    $me->{yd_max} = $h if defined($h) && $h;
    $me->adjust();
}

sub adjust {
    my $me = shift;
    
    # I have touched the highest point of all my greatness;
    #   -- Shakespeare, King Henry VIII
    $me->{xmax} = $me->{xdim} - $me->{xmarr} - $me->{xmarl};
    $me->{ymax} = $me->{ydim} - $me->{ymarb} - $me->{ymart} ;

    # print STDERR "adj $me->{ymin} > $me->{ymax} ; $me->{yd_min} > $me->{yd_max}\n";
    
    $me->{xd_scale} = ($me->{xd_min} == $me->{xd_max}) ? 1
	: $me->{xmax} / ($me->{xd_max} - $me->{xd_min});

    $me->{yd_scale} = ($me->{yd_min} == $me->{yd_max}) ? 1
	: $me->{ymax} / ($me->{yd_max} - $me->{yd_min});

}

sub analyze_samples {
    my $me = shift;
    my $samp = shift;

    my( $st, $et, $min, $max );
    $st = $samp->[0]{time};
    $et = $samp->[-1]{time};
    
    foreach my $s (@$samp){
	$min = $s->{valu} if !defined($min) || $s->{valu} < $min;
	$max = $s->{valu} if !defined($max) || $s->{valu} > $max;
    }

    $me->{xd_min} = $st  if !defined($me->{xd_min}) || $st  < $me->{xd_min};
    $me->{xd_max} = $et  if !defined($me->{xd_max}) || $et  > $me->{xd_max};
    $me->{yd_min} = $min if !defined($me->{yd_min}) || $min < $me->{yd_min};
    $me->{yd_max} = $max if !defined($me->{yd_max}) || $max > $me->{yd_max};

    $me->adjust();
    $me->{ngraphs} ++;
}

sub analyze_summary {
    my $me = shift;
    my $samp = shift;
    my( $st, $et, $min, $max );

    $st = $samp->[0]{time};
    $et = $samp->[-1]{time};
    foreach my $s (@$samp){
	$min = $s->{min} if !defined($min) || $s->{min} < $min;
	$max = $s->{max} if !defined($max) || $s->{max} > $max;
    }

    $me->{xd_min} = $st  if !defined($me->{xd_min}) || $st  < $me->{xd_min} && $st;
    $me->{xd_max} = $et  if !defined($me->{xd_max}) || $et  > $me->{xd_max};
    $me->{yd_min} = $min if !defined($me->{yd_min}) || $min < $me->{yd_min};
    $me->{yd_max} = $max if !defined($me->{yd_max}) || $max > $me->{yd_max};

    $me->adjust();
    $me->{ngraphs} ++;
}

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
sub logoize {
    my $me = shift;

    foreach my $l (@data){
	foreach my $i ($l->[0] .. $l->[0] + $l->[2]){
	    $me->{img}->setPixel($me->{xdim} - 9 + $i, 2 + $l->[1], $me->{color}{gray});
	}
    }
}

# Titles are marks of honest men, and wise;
# The fool or knave that wears a title lies.
#   -- Edward Young, Love of Fame
sub title {
    my $me = shift;
    my $lb = shift;
    my( $loc );

    return if $me->{size} eq 'thumb';
    $me->{ymart} += 16;
    $me->adjust();
    # center title
    $loc = ($me->{xdim} - length($lb) * 7) / 2;
    $me->{img}->string(gdMediumBoldFont, $loc, 2, $lb, $me->{color}{black});
}

# His heart was as great as the world, but there was
# no room in it to hold the memory of a wrong.
#   -- Emerson, Greatness.
sub makeroom {
    my $me = shift;

    return if $me->{size} eq 'thumb';
    $me->{ymart} += 4 if $me->{ymart} < 12;
    $me->adjust();
    
}

# when I waked, I found This label on my bosom
#   -- Shakespeare, Cymbeline
sub xlabel {
    my $me = shift;
    my $lb = shift;
    my( $loc, $y );

    return if $me->{size} eq 'thumb';
    $me->{ymarb} += 12;
    $me->adjust();
    $loc = ($me->{xdim} - length($lb) * 6) / 2;
    $y = $me->{ydim} - $me->{ymarb} + 20;
    $me->{img}->string(gdSmallFont, $loc, $y, $lb, $me->{color}{black});
}

sub ylabel {
    my $me = shift;
    my $lb = shift;
    my( $loc );

    return if $me->{size} eq 'thumb';
    $me->{xmarl} += 10;
    $me->adjust();
    $loc = ($me->{ydim} + length($lb) * 5) / 2;
    $me->{img}->stringUp(gdTinyFont, 2, $loc, $lb, $me->{color}{black});
}

# It must be a very pretty dance
#   -- Alice in Wonderland
# make tic numbers pretty
sub pretty {
    my $me = shift;
    my $y  = shift;
    my $st = shift;
    my( $ay, $sc, $b, $prec );

    $ay = abs($y);
    if( $ay < 1 ){
	if( $ay < .000_000_001 ){
	    return "0";
	}
	elsif( $ay < .000001 ){
	    $y *= 1_000_000_000; $st *= 1_000_000_000;
	    $sc = 'p';
	}
	elsif( $ay < .001 ){
	    $y *= 1000000; $st *= 1000000;
	    $sc = 'u';
	}
	elsif( $ay < .1 ){
	    $y *= 1000;	$st *= 1000;
	    $sc = 'm';
	}
    }else{
	$b = $me->{binary} ? 1024 : 1000;
	if( $ay >= $b**3 ){
	    $y /= $b**3;  $st /= $b**3;
	    $sc = 'G';
	}
	elsif( $ay >= $b**2 ){
	    $y /= $b**2; $st /= $b**2;
	    $sc = 'M';
	}
	elsif( $ay >= $b ){
	    $y /= $b;   $st /= $b;
	    $sc = 'k';
	}
	$sc .= 'i' if $me->{binary}; # as per IEC 60027-2
    }
    if( $st > 1 ){
	$prec = 0;
    }else{
	$prec = abs(floor(log($st)/log(10)));
    }
    # print STDERR "ay=$ay y=$y, st=$st prec=$prec\n";
    sprintf "%.${prec}f$sc", $y;
}

sub ytics {
    my $me  = shift;
    my( $min, $max, $tp, $st, $is, $low, $maxw, @tics );

    $min = $me->{yd_min};
    $max = $me->{yd_max};
    
    if( $min == $max ){
	my $lb = $me->pretty($min, 1);	# QQQ
	my $w = length($lb) * 5 + 6;
	push @tics, [$me->ydatapt($min), $lb, $w];
	$maxw = $w;
    }else{
	$tp = ($max - $min) / 4;	# approx 4 tics
	if( $me->{binary} ){
	    $is = 2 ** floor( log($tp)/log(2) );
	}else{
	    $is = 10 ** floor( log($tp)/log(10) );
	}
	$st = floor( $tp / $is ) * $is; # -> 4 - 8, ceil -> 2 - 4
	$low = int( $min / $st ) * $st;
	# print STDERR "min=$min max=$max tp=$tp is=$is st=$st low=$low yt=$me->{ymart}\n";
	for my $i ( 0 .. 10 ){
	    my $y = $low + $i * $st;
	    next if $y < $min;
	    last if $y > $max;
	    my $yy = $me->ydatapt($y);
	    my $label = $me->pretty($y, $st);
	    my $w = 5 * length($label) + 6;
	    $maxw = $w if $w > $maxw;
	    #print STDERR "ytic $i: $y -> $yy\n";
	    
	    push @tics, [$yy, $label, $w];
	}
    }
    
    my $dolbs;
    if( $me->{size} ne 'thumb' ){
	$dolbs = 1;
	# move margin
	$me->{xmarl} += $maxw + 4;
	$me->adjust();
    }

    $me->{grid}{y} = [ @tics ];
}

sub drawgrid {
    my $me = shift;
    
    foreach my $tic (@{$me->{grid}{y}}){
	my $yy = $tic->[0];
	$me->{img}->line($me->xpt(-1), $yy, $me->xpt(-4), $yy,
			 $me->{color}{black});
	$me->{img}->line($me->xpt(0), $yy, $me->{xdim} - $me->{xmarr}, $yy,
			 gdStyled) if $me->{grid};
	if( $me->{xmarl} > 16 ){
	    my $label = $tic->[1];
	    my $w = $tic->[2];
	    $me->{img}->string(gdTinyFont, $me->xpt(-$w), $yy-4,
			       $label,
			       $me->{color}{black});
	}
    }

    foreach my $tic (@{$me->{grid}{x}}){
	my( $t, $ll, $label ) = @$tic;

	if( $ll ){
	    # solid line, red label
	    $me->{img}->line($me->xdatapt($t), $me->{ymart},
			     $me->xdatapt($t), $me->ypt(-4),
			     $me->{color}{black} );
	}else{
	    # tic and grid
	    $me->{img}->line($me->xdatapt($t), $me->ypt(-1),
			     $me->xdatapt($t), $me->ypt(-4),
			     $me->{color}{black} );
	    $me->{img}->line($me->xdatapt($t), $me->{ymart},
			     $me->xdatapt($t), $me->ypt(0),
			     gdStyled ) if $me->{grid};
	}
	if( $me->{size} ne 'thumb' ){
	    my $a = length($label) * 6 / 4;	# it looks better not quite centered
	    $me->{img}->string(gdSmallFont, $me->xdatapt($t)-$a, $me->ypt(-6),
			       $label, $ll ? $me->{color}{red} : $me->{color}{black} );
	}
    }
}

# this is much too ickky, please re-write
sub xtics {
    my $me = shift;
    my( $r, $step, $rd, $n2, $n3, $n4, $lt, $low, $t, @tics );

    # this is good for (roughly) 10 mins - 10 yrs
    return if $me->{xd_max} == $me->{xd_min};
    $r = ($me->{xd_max} - $me->{xd_min} ) / 3600;	# => hours
    $rd   = $r / 24;
    $step = 3600;
    $n2   = 24; $n3 = $n4 = 1;
    $low  = int($me->{xd_min} / 3600) * 3600;
    
    if( $r < 2 ){ 		# less than 2 hrs
	$low = int($me->{xd_min} / 600) * 600;
	$n2 = 1;
	$lt = 1;
	$step = 10 * 60;
    }elsif( $r < 48 ){		# less than 2 days
	$n2  = ($r < 13) ? 1 : ($r < 24) ? 2 : 4;
	$lt  = 1;
    }
    elsif( $r < 360 ){		# less than ~ 2 weeks
	$lt  = 2;
    }elsif( $rd < 1500 ){	# less than ~ 4yrs
	$n3  = ($rd < 80)  ? 7 : ($rd < 168) ? 14 : 32;
	$n4  = ($rd < 370) ? 1 : ($rd < 500) ? 2 : 4;
	$lt  = 3;
    }else{
	$n3 = 32; $n4 = 12;
	$lt  = 4;
    }

    # print STDERR "xtics min=$me->{xd_min} max=$me->{xd_max}  r=$r, st=$step, low=$low, $n2/$n3/$n4\n";
    for( $t=$low; $t<$me->{xd_max}; $t+=$step ){
	my $ll;
	next if $t < $me->{xd_min};
	my @lt = localtime $t;
	next if $lt[2] % $n2;
	next if ($lt[3] - 1) % $n3 || (($n3!=1) && $lt[3] > 22 );
	next if $lt[4] % $n4;
	if( $lt == 1 && !$lt[2] && !$lt[1] ||      # midnight
	    $lt == 2 && !$lt[6] ||                 # sunday
	    $lt == 3 && $lt[3] == 1 && $rd < 60 || # 1st of month
	    $lt == 3 && $lt[3] == 1 && $lt[4] == 0 # Jan 1
	    ){
	    $ll = 1;
	}
	
	my $label;
	if( $lt == 1){
	    $label = sprintf "%d:%0.2d", $lt[2], $lt[1];	# time
	}
	if( $lt == 2 ){
	    if( $ll ){
		# NB: strftime obeys LC_TIME for localized day/month names
		# (if locales are supported in the OS and perl)
		$label = strftime("%d/%b", @lt);	# date DD/Mon
	    }else{
		$label = strftime("%a", @lt);		# day of week
	    }
	}
	if( $lt == 3){
	    if( $lt[3] == 1 && $lt[4] == 0 ){
		$label = $lt[5] + 1900;			# year
	    }else{
		$label = strftime("%d/%b", @lt);	# date DD/Mon
	    }
	}
	if( $lt == 4){
	    $label = $lt[5] + 1900; # year
	}
	push @tics, [$t, $ll, $label];
    }
    $me->{grid}{x} = [@tics];
}

# it shall be inventoried, and every particle and utensil
# labelled to my will: as, item, two lips,
# indifferent red; item, two grey eyes, with lids to
# them; item, one neck, one chin, and so forth. Were
# you sent hither to praise me?
#   -- Shakespeare, Twelfth Night
sub clabels {
    my $me = shift;
    my $cl = shift;
    my( $i, $maxw, $r, $tw, @cl, @cx );
    @cl = split /\s+/, $cl;

    return if $me->{size} eq 'thumb';

    # round the neck of the bottle was a paper label, with the
    # words 'DRINK ME' beautifully printed on it in large letters
    #   -- Alice in Wonderland
    foreach my $l (@cl){
	$l = decode($l);
	my $w = length($l) * 5 + 6;
	if( $tw + $w > $me->{xdim} - 32 ){
	    $r ++;
	    $tw = 0;
	}
	push @cx, [$l, $tw, $r];
	$tw += $w;
    }

    $i = 0;
    foreach my $x (@cx){
	my $y = $me->{ydim} - ($r - $x->[2] + 1) * 10 - 2;
	my $c = $me->{colors}{use}[ $i++ % @{$me->{colors}{RGB}} ];
	$me->{img}->string(gdTinyFont, $x->[1] + 16, $y, $x->[0], $c);
    }
    $me->{ymarb} += ($r + 1) * 10;
    $me->adjust();
}

# A flattering painter, who made it his care
# To draw men as they ought to be, not as they are.
#   -- Oliver Goldsmith, Retaliation
sub draw {
    my $me   = shift;
    my $how  = shift;
    my $data = shift;

    return unless @$data;

    if( @$data < 3 ){
        # $me->{img}->string(GD::gdMediumBoldFont, $me->{xmarl} + 4, 24, 'NOT ENOUGH DATA',
	# 	      $me->{color}{red} );
	return;
    }
    
    my $limit = 4 * ($me->{xd_max} - $me->{xd_min}) / @$data;
	
    # 'What did they draw?' said Alice, quite forgetting her promise.
    #   -- Alice in Wonderland
    if( $how eq 'filled' ){
	# 'You can draw water out of a water-well,' said the Hatter
	#   -- Alice in Wonderland
	my($px, $py) = ($data->[0]{time}, $data->[0]{valu} || $data->[0]{ave});
	foreach my $s ( @$data ){
	    my $x = $s->{time};
	    my $y = $s->{valu} || $s->{ave};
	    if( $me->xdatapt($x) - $me->xdatapt($px) > 1 ){
		$px = $x - $limit if $x - $px > $limit;
		
		my $poly = GD::Polygon->new;
		$poly->addPt($me->xdatapt($px), $me->ypt(0));
		$poly->addPt($me->xdatapt($px), $me->ydatapt($py));
		$poly->addPt($me->xdatapt($x),  $me->ydatapt($y));
		$poly->addPt($me->xdatapt($x),  $me->ypt(0));
		$me->{img}->filledPolygon($poly, $me->color($s->{flag}));
	    }else{
		$me->{img}->line( $me->xdatapt($x), $me->ypt(0),
				  $me->xdatapt($x), $me->ydatapt($y),
				  $me->color($s->{flag}) );
	    }
	    $px = $x; $py = $y;
	}
	$me->{graphno} ++;
    }
    
    if( $how eq 'line' ){
	# I should think you could draw treacle out of a treacle-well
	#    -- Alice in Wonderland
	my($px, $py) = ($data->[0]{time}, $data->[0]{valu} || $data->[0]{ave});
	foreach my $s ( @$data ){
	    my $x = $s->{time};
	    my $y = $s->{valu} || $s->{ave};
	    $px = $x - $limit if $x - $px > $limit;
	    
	    $me->{img}->line( $me->xdatapt($px), $me->ydatapt($py),
			      $me->xdatapt($x),  $me->ydatapt($y),
			      $me->color($s->{flag}) );
	    $px = $x; $py = $y;
	}
	$me->{graphno} ++;
    }
    
    if( $how eq 'minmax' || $how eq 'stddev' ){
	# did you ever see such a thing as a drawing of a muchness?
	#    -- Alice in Wonderland
	my($px, $py) = ($data->[0]{time}, $data->[0]{ave});
	my($pn, $pm) = ($py, $py);
	foreach my $s ( @$data ){
	    my $x = $s->{time};
	    my $y = $s->{ave};
	    my($a, $b);
	    if( $how eq 'minmax' ){
		$a = $s->{min}; $b = $s->{max};
	    }else{
		$a = $y - $s->{stdv}; $b = $y + $s->{stdv};
		$a = $me->{yd_min} if $a < $me->{yd_min};
		$b = $me->{yd_max} if $b > $me->{yd_max};
	    }
	    if( $me->xdatapt($x) - $me->xdatapt($px) > 1 ){
		my $poly = GD::Polygon->new;
		$px = $x - $limit if $x - $px > $limit;
		
		$poly->addPt($me->xdatapt($px), $me->ydatapt($pn));
		$poly->addPt($me->xdatapt($px), $me->ydatapt($pm));
		$poly->addPt($me->xdatapt($x),  $me->ydatapt($b));
		$poly->addPt($me->xdatapt($x),  $me->ydatapt($a));
		$me->{img}->filledPolygon($poly, $me->{color}{blue});
	    }else{
		$me->{img}->line( $me->xdatapt($x),  $me->ydatapt($b),
				  $me->xdatapt($x),  $me->ydatapt($a),
				  $me->{color}{blue} );
	    }
	    $px = $x; $py = $y;
	    $pn = $a; $pm = $b;
	}
	if( $me->{xdim} > 256 ){
	    my $y = $me->{ymart} > 12 ? 2 : -2;
	    $me->{img}->string(gdSmallFont, 4, $y, "ave", $me->{color}{grn});
	    $me->{img}->string(gdSmallFont, 24, $y, $how, $me->{color}{blue});
	}
    }
}

sub testme {
    my $dt = shift;
    my $img = new('thumb');
    my( $t, $data );

    for($t=$^T; $t<$^T+$dt; $t+=$dt/1000){
	my $v = 1000 + rand(.05);
	push @$data, {time => $t, valu => $v};
    }
    
    $img->analyze_samples( $data );
    $img->ytics();
    $img->xtics();
    $img->axii();
    $img->drawgrid();    
    $img->draw( 'filled', $data );
    print $img->png();
}

1;
