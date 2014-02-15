# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Apr-02 11:06 (EST)
# Function: misc code
#
# $Id: misc.pl,v 1.23 2012/10/06 19:51:07 jaw Exp $

use Socket;
BEGIN{ eval{ require Socket6; import Socket6; $HAVE_S6 = 1; }}
use Fcntl qw(:flock);

# My lord the emperor, resolve me this:
#  -- Shakespeare, Titus Andronicus
# memoized gethostbyname
my %resolve = ();
sub resolve {
    my $a = shift;
    my( $opt, $ip, @o );

    # skip DNS lookups if only checking the config file (-t)
    # but do the lookup under more checking (-T)
    return "addr" if $::opt_t && !$::opt_T;
    $a =~ s/\s+/ /g;

    # since we often monitor several things per host, we tend to lookup
    # each host many times, we use a cache to speed things up
    return $resolve{$a} if( $resolve{$a} );

    # undocumented feature: '-4 www.example.com', '-6 www.example.com'
    # www.example._ipv4, www.example.com._ipv6

    if( $a =~ /^-(\S+)\s(.*)/ ){
	$opt = $1;
	$a   = $2;
    }
    elsif( $a =~ /(\S+)\._ipv(\d)/ ){
        $opt = $2;
        $a   = $1;
    }

    $opt ||= '46';

    if( $a =~ /^\d+\.\d+\.\d+\.\d+$/ ){
	$ip = inet_aton( $a );
    }elsif( $a =~ /^[a-f\d:]+$/i && $HAVE_S6 ){
	$ip = inet_pton(AF_INET6, $a);
    }elsif( $HAVE_S6 ){
	for (0 .. 1){
	    # 1st look for a v6 addr, then v4
	    $ip   = gethostbyname2($a, AF_INET6) if $opt =~ /6/;
	    $ip ||= gethostbyname2($a, AF_INET)  if $opt =~ /4/;
	    last if length($ip);
	    sleep 1;
	}
    }else{
	for (0 .. 1){
	    $ip = gethostbyname($a);
	    last if length($ip);
	    # if the lookup fails, we briefly pause and try again
	    # this takes care of slow DNS servers or transient errors
            sleep 1;
        }
    }

    $resolve{$a} = $ip;
    $ip;
}

sub xxx_inet_ntoa {
    my $n = shift;

    return inet_ntoa($n) if length($n) == 4;
    return undef unless $HAVE_S6;
    return inet_ntop(AF_INET6, $n) if length($n) == 16;

    "X.X.X.X";
}

sub ckbool {
    my $v = shift;

    ($v =~ /yes|true|on|1/i) ? 1 : 0;
}

sub topconf {
    my $p = shift;

    return unless $::Top;
    return $::Top->{$p} if defined $::Top->{$p};
    return $::Top->{config}{$p};
}

# And these does she apply for warnings, and portents,
# And evils imminent; and on her knee
#  -- Shakespeare, Julius Ceasar
sub warning {
    my $msg = shift;

    loggit( $msg, 1 );
}

sub try_openlog {

    return if $opt_t;

    if( my $sysl = topconf('syslog') ){

	$ENV{ARGUS_SYSLOG} = $sysl;
	# ver 3 (5.8.0) will iterate @connectmethods
	if( $Sys::Syslog::VERSION < 0.03 ){
	    eval {
		setlogsock( 'unix' );
	    };
	}
	eval {
	    # this is broken in 5.6.0, at least on Linux
	    openlog( $NAME, 'pid ndelay', $sysl );
	    loggit( "syslog configured: $sysl" );
	};
	if( $@ ){
	    if( $] == 5.006 ){
		loggit( "syslog open failed - due to bug in perl 5.6.0", 1 );
	    }else{
		loggit( "syslog open failed - $@", 1 );
	    }
	}
    }
}

# And there was found at Achmetha, in the palace that is in the province
# of the Medes, a roll, and therein was a record thus written:
#   -- ezra 6:2
sub loggit {
    my $msg = shift;
    my $lfp = shift;	# also put in datadir/log

    # When they had thrown down their great logs of wood over the whole ground
    #   -- Homer, Iliad

    $::TIME ||= $^T;
    my $t = int $::TIME;
    my $f = sprintf '%.4f', $::TIME - $t;
    $f =~ s/^0\.//;
    my @d = localtime($t);
    my $date = sprintf "%d/%02d/%02d %d:%0.2d:%0.2d.%s",
        $d[5]+1900, $d[4]+1, $d[3], $d[2], $d[1], $d[0], $f;

    eval {
	syslog( 'info', $msg )  if topconf('syslog') && !$::opt_t;
    };
    print STDERR "[$date] $msg\n" if $opt_f;

    Control::console( $msg );
    if( $lfp && $datadir && !topconf('_test_mode') && !$::opt_t ){
	if( open  LOG, ">> $datadir/log" ){
	    print LOG "[$date] [$$] $msg\n";
	    close LOG;
	}else{
	    loggit( "open log '$datadir/log' failed: $!", 0 );
	}
    }

    undef;
}

# It is a good shrubbery.  I like the laurels particularly.
# But there is one small problem--
#   -- Monty Python, Holy Grail
sub sysproblem {
    my $msg = shift;

    warning( $msg );
}

# The greatest efforts of the race have always been traceable to the love
# of praise, as its greatest catastrophes to the love of pleasure.
#   -- John Ruskin, Sesame and Lilies
sub trace {

    for my $i (0..8){
	print STDERR "trace: ", join(", ", caller($i)), "\n" if caller($i);
    }
    print STDERR "----\n";
}

# Once upon a weekend weary, while I pondered, beat and bleary,
# Over many a faintly printed hexadecimal dump of core --
# While I nodded, nearly napping, suddenly there came a tapping,
# As of some Source user chatting, chatting of some Mavenlore.
# "Just a power glitch," I muttered, "printing out an underscore --
# 		  Just a glitch and nothing more."
#   -- the Dragon, The Maven
sub hexdump {
    my $b = shift;
    my $tag = shift;
    my( $l, $t );

    print STDERR "$tag:\n" if $tag;
    while( $b ){
	$t = $l = substr($b, 0, 16);
	substr($b, 0, 16) = '';
	$l =~ s/(.)/sprintf('%0.2X ',ord($1))/ges;
	$t =~ s/\W/./gs;
	print STDERR "    $l\n";
    }
}

sub hexstr {
    my $b = shift;

    $b =~ s/(.)/sprintf('%0.2X ',ord($1))/ges;
    $b;
}

# expand conditional
#  %(test_text=pattern?then_text:else_text)
#  = may be: = != ~ !~
#  =pattern is optional
#  else is optional.
sub expand_conditionals {
    my $txt = shift;

    # print STDERR "expand: <$txt>\n";
    while( $txt =~ /%\(([^\)]*)\)/s ){
	my $pat = $1;
	# do not split on \? and \:
	my($cond, $repl) = split /(?<!\\)\?/, $pat, 2;
	my($then, $else) = split /(?<!\\):/, $repl, 2;

	foreach my $x ($cond, $then, $else){
	    $x =~ s/\\\?/\?/sg;
	    $x =~ s/\\\:/\:/sg;
	}

	# print STDERR "  => pat<$pat>, cond<$cond>, repl<$repl>, then<$then>, else<$else>\n";

	# Now go and see what their condition is.
	#   -- Dante, Divine Comedy
	if( $cond =~ /(.*)!=(.*)/ ){
	    $repl = $1 eq $2 ? $else : $then;

	}elsif( $cond =~ /(.*)=(.*)/ ){
	    $repl = $1 eq $2 ? $then : $else;

	}elsif( $cond =~ /(.*)!~(.*)/ ){
	    $repl = $1 =~ /$2/ ? $else : $then;

	}elsif( $cond =~ /(.*)~(.*)/ ){
	    $repl = $1 =~ /$2/ ? $then : $else;

	}else{
	    $repl = $cond ? $then : $else;
	}

	$txt =~ s/%\([^\)]*\)/$repl/s;
	# print STDERR "  => txt<$txt>\n";
    }

    # print STDERR "  => final: $txt\n";
    return $txt;
}

# convert friendly time specifiers to seconds
my %convfactor = (
		  s => 1,
		  m => 60,
		  h => 3600,
		  d => 24 * 3600,
		  w => 7 * 24 * 3600,
		  M => 30 * 24 * 3600,
		  y => 365 * 24 * 3600,
		  );
sub timespec {
    my $spec = shift;
    my $dfls = shift; # default units in seconds

    my $sec = 0;

    # add spaces between parts: 12y3w2d -> 12y 3w 2d
    $spec =~ s/(\D)(\d)/$1 $2/g;
    # convert punctuation to spaces: 12y-14d-6h -> 12y 14d 6h
    $spec =~ s/[-.,\/_+:]/ /g;

    for my $s (split /\s+/, $spec){
	my($n,$c) = $s =~ /(\d+)(\D)?/; # look at 1st letter only
	my $f = $convfactor{$c};
	die "invalid timespec\n" if $c && !$f;
	$f ||= ($dfls || 1);
	$sec += $f * $n;
    }

    return $sec;
}


# Eager already to search in and round
# The heavenly forest, dense and living-green,
#   -- Dante, Divine Comedy
sub binary_search {
    my $a = shift;
    my $k = shift;
    my $t = shift;

    my $lo = 0;
    my $hi = @$a - 1;

    while($lo <= $hi){
	my $mi = ($lo + $hi) >> 1;
	my $mt = $a->[$mi]{$k};

	if( $mt < $t ){
	    $lo = $mi + 1;	# gaze right
	}elsif( $mt > $t ){
	    $hi = $mi - 1;	# gaze left
	}else{
	    return $mi;		# exact match found
	}
    }

    # They were very angry at
    # my having escaped and went searching about for me, till at last they
    # thought it was no further use and went back to their ship
    #   -- Homer, Odyssey

    return $lo;		# not found - return item to the right
}

1;

