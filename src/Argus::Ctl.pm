# -*- perl -*-

# Copyright (c) 2003 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2003-Jan-27 15:16 (EST)
# Function: talk to argus
#
# $Id: Argus::Ctl.pm,v 1.16 2012/09/29 21:23:01 jaw Exp $

# that would be *other programs* talking to argus
# not some sort of schizo-argus talking to itself

package Argus::Ctl;
use Socket;
use Fcntl;
use Argus::Encode;
use strict;

my $PROTO_TCP = getprotobyname('tcp');

sub new {
    my $class = shift;
    my $where = shift;
    my @param = @_;
    my $me;

    $me = {
	where => $where,
	@param,
    };
    bless $me, $class;

    $me->connect();
    $me;
}

sub connect {
    my $me = shift;
    my( $fd, $i, $st );

    $fd = do{local *ARGUSCTL};

    local $SIG{ALRM} = sub {};
    # handle local and inet connections
    if( $me->{where} =~ /:\d+$/ ){
	$st = 'tcp';
	my( $host, $port ) = split /:/, $me->{where};
	my $ip = inet_aton($host);
	socket($fd, PF_INET, SOCK_STREAM, $PROTO_TCP);
	alarm( $me->{timeout} || 10 );
	$i = connect( $fd, sockaddr_in($port, $ip) );
	alarm(0);
    }else{
	$st = 'unix';
	socket($fd, PF_UNIX, SOCK_STREAM, 0);
	alarm( $me->{timeout} || 10 );
	$i = connect($fd, sockaddr_un( $me->{where} ));
	alarm(0);
    }
    unless( $i ){
	return $me->{onerror}->( "connect failed: $!" )
	    if $me->{onerror};
	print STDERR "ERROR: could not connect to argusd on $st socket '$me->{where}': $!\n";
	return;
    }
    my $old = select $fd; $| = 1; select $old;
    $me->{fd} = $fd;

    $me;
}

sub connectedp {
    my $me = shift;

    $me->{fd} ? 1 : 0;
}

sub disconnect {
    my $me = shift;

    close $me->{fd} if $me->{fd};
    delete $me->{fd};
}

sub reconnect {
    my $me = shift;

    $me->disconnect();
    $me->connect();
}

sub try_command {
    my $me = shift;
    my %param = @_;
    my( $fd, $r );

    $fd = $me->{fd};
    local $SIG{ALRM} = sub{};
    alarm( $me->{timeout} || 10 );
    # send req
    $r = print $fd "GET / ARGUS/2.0\n";

    foreach my $k (keys %param){
	my $v = $param{$k};
	next unless defined $v;
	$v = encode($v) if $me->{encode};
	$r = print $fd "$k: $v\n";
    }
    print $fd "$me->{who}: 1\n" if $me->{who};
    print $fd "\n";
    chop( $r = <$fd> );
    alarm(0);
    $r;
}

sub sendbuf {
    my $me  = shift;
    my $buf = shift;

    my $fd = $me->{fd};
    local $SIG{ALRM} = sub{};
    alarm( $me->{timeout} || 10 );
    print $fd $buf;
    alarm(0);

    1;
}


sub command_raw {
    my $me = shift;
    my( $fd );

    $me->connect() unless $me->{fd};
    return undef unless $me->{fd};

    $fd = $me->{fd};
    my $r = $me->try_command(@_);
    if( !$r && $me->{retry} ){
	$me->reconnect();
	$r = $me->try_command(@_) if $me->{fd};
    }

    $r;
}

sub nextline {
    my $me = shift;
    my $fd = $me->{fd};

    <$fd>;
}

sub command {

    my($rh, $ra) = command_a(@_);
    $rh;
}

sub command_a {
    my $me = shift;
    my %param = @_;
    my( $fd, $k, $v, $l, @r, %r );

    $l = $me->command_raw( %param );
    return undef unless $l;

    # get result
    (undef, $k, $v) = split /\s+/, $l, 3;
    $r{resultcode} = $k;
    $r{resultmsg}  = $v;

    $fd = $me->{fd};
    while( <$fd> ){
	chop;
	last if /^$/;
	($k, $v) = split /:\s+/, $_, 2;
	$v = decode($v) if $me->{decode};
	$r{$k} = $v;
	push @r, [$k, $v];

    }

    (\%r, \@r);
}


1;
