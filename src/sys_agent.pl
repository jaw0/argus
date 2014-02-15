#!__PERL__
# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Nov-06 17:57 (EST)
# Function: remote system monitoring agent
#
# $Id: sys_agent.pl,v 1.13 2012/10/12 02:17:32 jaw Exp $

# run from inetd.conf

# if ip addresses are listed on cmdline, restrict access to those specified
# eg:  argus-agent 10.0.0.1  10.0.0.2  fec0:b80:1fcb:1::1

# uptime, disk used %, load ave, etc.
# shouldn't people be running snmpd instead?

# many of these use highly non-portable means for gathering data
# it probably won't work on your system without customization

use Socket;
my $HAVE_S6;
BEGIN{ eval{ require Socket6; import Socket6; $HAVE_S6 = 1; }}
use strict;

$> = $< = -1;	# if we are root, drop privileges

verify_access(@ARGV) if @ARGV;

# read request
chop(my $line = <STDIN>);
$line =~ tr/\r//d;
my ($what, $arg) = split /\s+/, $line, 2;


my %FUNC = (
    load	=> \&get_load,
    uptime	=> \&uptime,
    disk	=> \&disk_usage,
    smart	=> \&disk_smart,
    iostat	=> \&disk_iostat,
    zpool	=> \&zpool_status,
    kstat	=> \&kstat,
    netstat	=> \&netstat,
    filesize	=> \&filesize,
    fileage	=> \&fileage,
    temperature => \&temperature,
    );

my $func = $FUNC{$what};
unless( $func ){
    print "error\n";
    exit -1;
}

$func->( $arg );
exit;

################################################################

sub get_load {
    my $arg = shift;

    if( open(F, "/proc/loadavg") ){
	# linux
	my $l = <F>;
	($l) = split /\s+/, $l;
	print "$l\n";
	close F;
    }elsif( open(F, "/kern/loadavg") ){
	# netbsd
	my $l = <F>;
	my(@a) = split /\s+/, $l;
	$l = $a[0] / $a[3];
	print "$l\n";
	close F;
    }else{
	# other
	my $up = output_of_command( 'uptime' );
	$up =~ s/.*:\s*([\d\.]+).*\n?/$1/;
	print "$up\n";
    }
}

sub uptime {
    my $arg = shift;

    if( open(F, "/proc/uptime") ){
	# linux
	my $l = <F>;
	($l) = split /\s+/, $l;
	print "$l\n";
	close F;
    }elsif( open(F, "/kern/boottime") ){
	# netbsd
	my $l = <F>;
	$l = $^T - $l;
	print "$l\n";
	close F;
    }else{
	# QQQ
	# the format of uptime varies significantly, I am too lazy
	# to write the code at the moment
    }
}

sub disk_usage {
    my $arg = shift;
    my $df;

    if( $^O eq 'solaris' || $^O eq 'netbsd' ){
        $df = output_of_command( 'df', '-k', $arg );
        $df =~ s/.*\s+(\d+)%.*\n?/$1/s;
    }else{
        $df = output_of_command( 'df', $arg );
        $df =~ s/.*\s+(\d+)%.*\n?/$1/s;
    }
    print "$df\n";
}

sub disk_smart {
    my $arg = shift;

    my $st = output_of_command('/usr/local/sbin/smartctl', '-H', $arg);
    $st =~ s/.*Status:\s+//s;
    chomp($st);
    print "$st\n";
}

sub filesize {
    my $arg = shift;
    my $v = -s $arg;
    print "$v\n";
}

sub fileage {
    my $arg = shift;

    # mtime
    my $v = $^T - (stat($arg))[9];
    print "$v\n";
}

sub netstat {
    my $arg = shift;

    # arg: interface [in|out]
    # extremely non-portable
    my( $int, $dir ) = split /\s+/, $arg;
    my $r;

    if( $^O eq 'solaris' ){
	my $st = output_of_command( '/bin/kstat', '-p', '-n',
	        $int, '-s', ($dir eq 'in' ? 'rbytes' : 'obytes'));
	chomp $st;
	$st =~ s/.*\s+//;
	$r = $st;
    }elsif( $^O eq 'linux' ){
	my $col = ($dir eq 'in' ? 0 : 8);
	open(F, "/proc/net/dev");
	while(<F>){
	    chop;
	    next unless /$int/;
	    s/^.*:\s*//;
	    my @st = split;
	    $r = $st[ $col ];
	    last;
	}
    }else{
	my $st = output_of_command( 'netstat', '-b', '-I', $int );
	# 1st matching line
	foreach my $l (split /\n/, $st){
	    next unless $l =~ /^$int/;
	    my @st = split /\s+/, $l;
	    $r = $st[ ($dir eq 'in') ? 4 : 5 ];
	    last;
	}
    }

    print "$r\n";
}

# => iostat c0t0d0s0 busy
sub disk_iostat {
    my $arg = shift;

    my($disk, $stat) = split /\s+/, $arg;

    # NB: this is about as portable as a house
    if( $^O eq 'solaris' ){
        my %STAT = ( read => 3, write => 4, wait => 5, actv => 6, svct => 7, wpct => 8, busy => 9 );
        my $n = $STAT{$stat};

        # translate cNtNdNsN => sdN
        my $dev = readlink("/dev/dsk/$disk");
        $dev =~ s|../../devices||;
        $dev =~ s|:.*||;

        my $name;
        open(P, '/etc/path_to_inst');
        while(<P>){
            chop;
            my($long, $i, $driver) = /"(\S+)"\s+(\d+)\s+"(\S+)"/;
            if( $long eq $dev ){
                $name = $driver . $i;
                last;
            }
        }
        close P;

        unless( $name ){
            print "error\n";
            exit -1;
        }

        my $out = output_of_command( 'iostat', '-x', $name, 5, 2 );
        my @dat = split /\s+/, ((split /\n/, $out)[-1]);

        if( $stat eq 'total' ){
            my $res = $dat[3] + $dat[4];	# read + write
            print "$res\n";
        }else{
            print "$dat[$n]\n";
        }
        exit;
    }

    if( $^O eq 'netbsd' ){
        my %STAT = (read => 4, write => 8);
        my $n = $STAT{$stat};
        my $out = output_of_command( 'iostat', '-Dx', $disk, 5, 2 );
        my @dat = split /\s+/, ((split /\n/, $out)[-1]);
        if( $stat eq 'total' ){
            print ($dat[4] + $dat[8]) * 1000, "\n";
        }else{
            print ($dat[$n] * 1000), "\n";
        }
        exit;
    }
    
    # ...
}

sub zpool_status {
    my $arg = shift;	# pool name

    my $out = output_of_command( 'zpool', 'status', $arg );
    for my $l (split /\n/, $out){
        if( $l =~ /^\s+state:\s+(.*)/ ){
            my $v = $1;
            print "$v\n";
            exit;
        }
    }
    print "UNKNOWN\n";
}

sub kstat {
    my $arg = shift;

    my $out = output_of_command( 'kstat', '-p', $arg );
    chomp($out);
    my($key, $res) = split /\t/, $out, 2;

    print "$res\n";
}

sub temperature {

    my $temp = 'UNKNOWN';

    # solaris
    if( $^O eq 'solaris' ){
        my $out = output_of_command('/usr/sbin/prtpicl', '-v', '-c', 'temperature-sensor');

        for my $l (split /\n/, $out){
            next unless $l =~ /Temperature/;
            ($temp) = $l =~ /(\d+)/;
        }
    }

    # QQQ - pull from smart?


    print "$temp\n";
}

################################################################

sub output_of_command {
    my $cmd = shift;
    my @arg = @_;
    my( $f );

    # we don't just `$cmd $arg` in case we have a naughty $arg...
    open(F, "-|") || exec($cmd, @arg);
    while( <F> ){
	$f .= $_;
    }
    close F;
    $f;
}

sub verify_access {
    my @addr = @_;

    # get address of peer
    my $sk = getpeername(STDIN);
    die "getpeername failed: $!\n" unless $sk;

    my $af = unpack('xC', $sk);
    my( $srcip, $srcport );

    if( $HAVE_S6 && $af == AF_INET6 ){
	($srcport, $srcip) = unpack_sockaddr_in6($sk);
    }else{
	($srcport, $srcip) = sockaddr_in($sk);
    }

    $srcip = xxx_inet_ntoa($srcip);

    # check
    foreach my $a (@addr){
	# canonicalize
	$a = xxx_inet_ntoa( resolve($a) );

	return 1 if $a eq $srcip;
    }

    die "access denied from $srcip\n";

}

sub xxx_inet_ntoa {
    my $n = shift;

    return inet_ntoa($n) if length($n) == 4;
    return undef unless $HAVE_S6;
    return inet_ntop(AF_INET6, $n) if length($n) == 16;

    "X.X.X.X";
}

sub resolve {
    my $a = shift;
    my( $opt, $ip, @o );

    if( $a =~ /^\d+\.\d+\.\d+\.\d+$/ ){
	$ip = inet_aton( $a );
    }elsif( $a =~ /^[a-f\d:]+$/i && $HAVE_S6 ){
	$ip = inet_pton(AF_INET6, $a);
    }elsif( $HAVE_S6 ){
	for (0 .. 1){
	    # 1st look for a v6 addr, then v4
	    $ip   = gethostbyname2($a, AF_INET6);
	    $ip ||= gethostbyname2($a, AF_INET);
	    last if length($ip) != 0;
	    sleep 1;
	}
    }else{
	for (0 .. 1){
	    $ip = gethostbyname($a);
	    last if length($ip) != 0;
            sleep 1;
        }
    }

    $ip;
}
