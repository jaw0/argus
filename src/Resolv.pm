# -*- perl -*-

# Copyright (c) 2003 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2003-May-22 21:46 (EDT)
# Function: caching async resolver + re-resolver
#
# $Id: Resolv.pm,v 1.32 2012/09/16 05:18:11 jaw Exp $

# Wise to resolve, and patient to perform.
#   -- Homer, Odyssey

# runs as a standard argus Service, can have several instances


package Resolv;
@ISA = qw(Service);

use Socket;
BEGIN{ eval{ require Socket6; import Socket6; $HAVE_S6 = 1; }}

use strict qw(refs vars);
use vars qw(@ISA $doc $HAVE_S6 $enable_p);

$enable_p = 0;
my $TOOLONG   = 300;
my $MAXFREQ   = 60;
my $OLD_AGE   = 60;
my $PROTO_UDP = getprotobyname('udp');
my $DNS_PORT  = 53;

my $n_resolv  = 0;
my %cache     = ();		# cache{hostname} = { addr, expire, }
my @todo      = ();		# hostnames to be looked up
my %todo      = ();             # ditto
my %pending   = ();		# pending queries
my @qidmap    = (0 .. 65535);	# randomize qid


$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [qw(Service MonEl BaseIO)],
    methods => {},
    versn => '3.4',
    html  => 'advanced',
    fields => {
	resolv::conf => {
	    descr => 'location of resolv.conf',
	    attrs => ['config', 'inherit'],
	    default => '/etc/resolv.conf',
	},
	resolv::ttl_min => {
	    descr => 'minimum ttl',
	    attrs => ['config', 'inherit', 'timespec'],
	    default => '5min',
	},
	resolv::ttl_max => {
	    descr => 'maximum ttl',
	    attrs => ['config', 'inherit', 'timespec'],
	    default => '2weeks',
	},
	resolv::ttl_nxdomain => {
	    descr => 'nxdomain caching ttl',
	    attrs => ['config', 'inherit', 'timespec'],
	    default => '10min',
	},
	resolv::ttl_error => {
	    descr => 'error caching ttl',
	    attrs => ['config', 'inherit', 'timespec'],
	    default => '1min',
	},
	resolv::max_queries => {
	    descr => 'maximum number of queries per session',
	    attrs => ['config', 'inherit'],
	    default => 10000,
	},
	resolv::max_inflight => {
	    # otherwise packets get dropped
	    descr => 'maximum number of queries pending in flight',
	    attrs => ['config', 'inherit'],
	    versn => '3.5',
	    default => 32,
	},
	resolv::nameservers => {
	    descr => 'list of nameservers to use in addition to those from resolv.conf',
	    attrs => ['config', 'inherit'],
	    exmpl => '192.168.7.11',
	},
	resolv::search => {
	    descr => 'domains to use for non-fully-qualified hostnames, overrides resolv.conf',
	    attrs => ['config', 'inherit'],
	    exmpl => 'example.com',
	},
	resolv::duplicates => {
	    descr => 'create a number of additional identical resolvers',
	    attrs => ['config', 'inherit'],
	    versn => '3.5',
	},

	resolv::qidn	    => { descr => 'queue id number' },
	resolv::inflight    => { descr => 'queries underway' },
	resolv::domlist     => { descr => 'list of search domains' },
	resolv::ns_all      => { descr => 'list of nameservers' },	# for debugging
	resolv::nslist      => { descr => 'list of nameservers' },
	resolv::nameserver  => { descr => 'current nameserver' },
	resolv::ns_i        => { descr => 'index of current nameserver' },
	resolv::pending     => { descr => 'queries currently pending' },
	resolv::n_queries   => { descr => 'number of outstanding queries' },
	resolv::n_responses => { descr => 'number of responses in this session' },
    },
};


################################################################
# these 2 funcs provide the public interface
#
# both will return either an addr or undef
################################################################
sub resolv_defer {
    my $host = shift;
    my( $ip );

    $host = normalize( $host );

    # check for dotted quad
    if( $host =~ /^\d+\.\d+\.\d+\.\d+$/ ){
	$ip = inet_aton( $host );
    }
    # check for cologned octopus
    elsif( $host =~ /^[a-f\d:]+$/i && $HAVE_S6 ){
	$ip = inet_pton(AF_INET6, $host);
    }

    if( $ip ){
	$cache{$host} = {
	    addr   => $ip,
	    expire => 0,
	};

	return $ip;
    }

    if( $cache{$host} && $cache{$host}{addr} ){
	return $cache{$host}{addr};
    }

    return undef if $pending{$host};

    print STDERR "resolv defer $host\n" if $::opt_d;

    add_todo( $host );
    return undef;
}

sub resolv_check {
    my $host = shift;
    $host = normalize( $host );

    print STDERR "resolv check $host\n" if $::opt_d;

    if( $cache{$host} ){
	# expire = 0 => never expires
	if( $cache{$host}{expire} && $cache{$host}{expire} < $^T  && !$pending{$host} ){
	    add_todo( $host );
	}

	return $cache{$host}{addr};
    }

    add_todo( $host );
    undef;
}

sub normalize {
    my $host = shift;

    $host = lc($host);
    # ...
    $host;
}

sub add_todo {
    my $h = shift;

    return if $todo{$h};
    $todo{$h} = 1;
    push @todo, $h;
}

sub remove_todo {
    my $h = shift;

    delete $todo{$h};
    @todo = grep {$_ ne $h} @todo;
}

sub too_long {

    ::topconf('resolv_timeout') || $TOOLONG;
}

################################################################

sub probe {
    my $name = shift;

    return [6, \&config] if $name =~ /^Resolv/i;
}

# a name not under Top:
sub unique {
    my $me = shift;

    $me->{uname};
}

sub config {
    my $me = shift;
    my $cf = shift;

    bless $me;
    $me->init_from_config( $cf, $doc, 'resolv' );

    if( $me->{name} =~ m%/(\d+)$% ){
	$me->{resolv}{duplicates} ||= $1 - 1;
    }

    $me->{web}{hidden}  = 1;
    $me->{passive}      = 1;
    $me->{nostats}      = 1;
    $me->{transient}    = 1;
    $me->{udp}{port}    = $DNS_PORT;

    $me->{uname} = "Resolv_$n_resolv";
    $n_resolv++;

    # don't want to overflow a 16bit
    $me->{resolv}{max_queries} = 60000 if $me->{resolv}{max_queries} > 60000;
    $me->{resolv}{ns_all}  = $me->{resolv}{nameservers};
    $me->{resolv}{ns_all} .= ' ' if $me->{resolv}{ns_all};
    my @ns = (split /\s+/, $me->{resolv}{ns_all});

    my @dom;

    # open resolv.conf
    my $f = $me->{resolv}{conf};
    if( $f ){
	open(R, $f) || return $cf->error("Cannot open '$f': $!");
	while(<R>){
	    my $ns;
	    chop;
	    if( /^domain/i | /^search/i ){
		my @d;
		(undef, @d) = split /\s+/;
		push @dom, @d;
		next;
	    }
	    next unless /^nameserver/i;
	    (undef, $ns) = split /\s+/;
	    push @ns, $ns;
	    $me->{resolv}{ns_all} .= $ns . " ";
	}
	close R;
    }

    # resolv nameservers
    @ns = map {
	if( /^\d+\.\d+\.\d+\.\d+$/ ){
	    inet_aton( $_ );
	}
	elsif( /^[a-f\d:]+$/i && $HAVE_S6 ){
	    inet_pton(AF_INET6, $_);
	}
	else{
	    $cf->nonfatal("Invalid nameserver: $_");
	    ();
	}
    } @ns;

    unless( @ns ){
	# because resolv.conf(5) says so
	push @ns, inet_aton('127.0.0.1');
	$me->{resolv}{ns_all} .= '127.0.0.1';
    }


    $me->{resolv}{nslist}     = [ @ns ];
    $me->{resolv}{ns_i}       = 0;
    $me->{resolv}{nameserver} = $me->{resolv}{nslist}[ 0 ];
    $me->{resolv}{qidn}       = int(rand(0xffff));
    $me->{resolv}{inflight}   = 0;
    $me->{ip}{addr}           = $me->{resolv}{nameserver};

    if( @dom ){
	$me->{resolv}{search} .= ' ' . join(' ', @dom);
    }
    $me->{resolv}{domlist} = [ '', (split/\s+/, $me->{resolv}{search}) ];

    unless( $::opt_t ){
	::loggit( "Asynchronous Resolver enabled" ) unless $enable_p;
	$enable_p = 1;
    }

    if( $me->{resolv}{duplicates} > 0 ){
	$me->clone_me( $cf, $me->{resolv}{duplicates} );
    }

    qidshuffle();
    $me;
}

sub clone_me {
    my $me   = shift;
    my $cf   = shift;
    my $dups = shift;

    my %cf;
    %cf = %{$me->{config}};
    delete $cf{duplicates};

    for (1 .. $dups){
	my $resolv = Service->new;
	$resolv->{name}   = 'Resolv';
	$resolv->{config} = { %cf };
	$resolv->{parents}[0] = $me->{parents}[0];
	$resolv->config($cf);
    }
}

sub mkphi {
    my $n = shift;

    return (1/2, 0) if $n == 1;
    my @p = mkphi( $n - 1 );

    my $d = 1/(1<<$n);
    my @n = map { $_ + $d } @p;
    (@p, @n);
}

my @PHI = mkphi(4);

sub configured {
    my $me = shift;

    my($n) = $me->{uname} =~ /_(\d+)/;
    if( $me->{srvc}{frequency} > $MAXFREQ ){
	$me->{srvc}{frequency} = $MAXFREQ;
    }

    $me->{srvc}{phi} = int($PHI[$n % 8] * $me->{srvc}{frequency});

    $me->SUPER::configured();
}

sub next_ns {
    my $me = shift;

    $me->debug('RESOLV - switching nameserver');
    $me->{resolv}{ns_i} ++;
    $me->{resolv}{ns_i} %= @{ $me->{resolv}{nslist} };

    $me->{resolv}{nameserver} = $me->{resolv}{nslist}[ $me->{resolv}{ns_i} ];
    $me->{ip}{addr} = $me->{resolv}{nameserver};
    qidshuffle();

}

sub start {
    my $me = shift;
    my( $fh, $ip, $i );

    $me->Service::start();
    $me->debug("RESOLV start");

    unless(@todo){
	$me->debug('RESOLV - queue empty');
	return $me->done();
    }

    # open socket to ns
    $me->{fd} = $fh = BaseIO::anon_fh();
    $ip = $me->{resolv}{nameserver};

    if( length($ip) == 4 ){
	$i = socket($fh, PF_INET,  SOCK_DGRAM, $PROTO_UDP);
    }else{
	$i = socket($fh, PF_INET6, SOCK_DGRAM, $PROTO_UDP);
    }

    unless($i){
	my $m = "socket failed: $!";
	::sysproblem( "RESOLV $m" );
	$me->debug( $m );
	return $me->done();
    }

    $me->baseio_init();

    # randomize port
    my $portr = int(rand(0xffff)) ^ $^T;
    for my $portn (0..65535){
	my $port = ($portr ^ $portn) & 0xffff;
	next if $port <= 1024;
	my $v;
	if( length($ip) == 4 ){
	    $i = bind($fh, sockaddr_in($port, INADDR_ANY) );
	    $v = 4;
	}else{
	    $i = bind($fh, pack_sockaddr_in6($port, in6addr_any) );
	    $v = 6;
	}

	if($i){
	    $me->debug("binding to port udp$v/$port");
	    last;
	}
    }

    unless($i){
	my $m = "bind failed: $!";
	::sysproblem( "RESOLV $m" );
	$me->debug( $m );
	return $me->done();
    }

    if( length($ip) == 4 ){
	$i = connect( $fh, sockaddr_in($DNS_PORT, $ip) );
    }else{
	$i = connect( $fh, pack_sockaddr_in6($DNS_PORT, $ip) );
    }

    unless($i){
	my $m = "connect failed: $!";
	::sysproblem( "RESOLV $m" );
	$me->debug( $m );
	$me->next_ns();
	return $me->done();
    }

    $me->wantread(1);
    $me->wantwrit(1);
    $me->settimeout( $me->{srvc}{timeout} );
    $me->{srvc}{state} = 'waiting';
    $me->{resolv}{n_queries}   = 0;
    $me->{resolv}{n_responses} = 0;
    $me->{resolv}{inflight}    = 0;
}

sub maybe_wantwrit {
    my $me = shift;
    my $rs = $me->{resolv};

    if( $rs->{n_queries} >= $rs->{max_queries} ){
	# session limit reached
	$me->wantwrit(0);
	return;
    }

    if( $rs->{inflight} >= $rs->{max_inflight} ){
	# too many outstanding - throttle
	$me->wantwrit(0);
	return;
    }
    $me->wantwrit(1);
}

sub readable {
    my $me = shift;
    my( $fh, $i, $l );

    $fh = $me->{fd};
    $i = recv($fh, $l, 8192, 0);
    unless( defined $i ){
	my $m = "recv failed: $!";
	::sysproblem( "RESOLV $m" );
	$me->debug( $m );
	return $me->done();
    }

    return if UDP::check_response($me, $i);

    $me->debug( 'RESOLV recv data' );
    $me->settimeout( $me->{srvc}{timeout} );

    # pull out qid, rcode
    my $id = unpack( 'n', $l );
    my $ec = unpack( 'x3 C', $l) & 0xF;

    # find matching query
    my $d = $me->{resolv}{pending}{$id};
    my $h = $d->{host};
    my $z = $d->{zone};
    delete  $me->{resolv}{pending}{$id};

    $me->debug( "RESOLV recv qid=$id, rcode=$ec" );

    unless( $h ){
	# un-expected response?
	$me->debug( "RESOLV recv unexpected response id=$id" );
	return;
    }

    # decode pkt
    my $r;
    unless( $ec ){
	eval{ $r = DNS::decode( $me, $l ); };
        $me->debug("error: $@") if $@;
    }

    delete $pending{$h};
    $me->{resolv}{n_responses} ++;
    $me->{resolv}{inflight} -- if $me->{resolv}{inflight};
    $me->maybe_wantwrit(); # or maybe throttle back

    # what to do if we get an error (or non-answer)?
    if( $ec || !$r || !$r->{na} ){

	my $et = ($ec == 3) ? $me->{resolv}{ttl_nxdomain} : $me->{resolv}{ttl_error};

	my $na = $r ? $r->{na} : 0;
	$me->debug( "RESOLV recv ERROR($ec) NA($na) for $z" );

	if( $cache{$h}{addr} ){
	    # if we have an addr, keep it
	    # if expired, update expire time

	    if( $cache{$h}{expire} < $^T ){
		$cache{$h}{expire} = $^T + $et;
	    }
	    $me->debug( "RESOLV keeping value for $h" );
	}

	else{
	    # error => cache failure
	    $cache{$h}{addr}   = undef;
	    $cache{$h}{expire} = $^T + $et;
	    $cache{$h}{rcode}  = $ec;

	    if( $ec == 3 && $me->{resolv}{domlist} && ($h !~ /\.$/) ){
		# nxdomain: try search domains
		$cache{$h}{srch} ||= $me->{resolv}{domlist};
		$cache{$h}{srch_i} = 1 unless defined $cache{$h}{srch_i};

		# go through the entire list, then delay ttl_nxdomain

		if( $cache{$h}{srch_i} % @{$cache{$h}{srch}} ){
		    $cache{$h}{expire} = $^T;
		    add_todo( $h );
		    $me->debug("RESOLV recv nxdomain $h - retry now");
		}
	    }
	}

	return;
    }

    # decode packet, find correct answer, there may be several...
    my @allow = "$z.";

    foreach my $a ( @{ $r->{answers} } ){
	$me->debug( "RESOLV recv $a->{name} $a->{ttl} $a->{class} $a->{type} $a->{answer}" );

	next unless grep {$_ eq $a->{name}} @allow;
	push @allow, $a->{answer} if $a->{type} eq 'CNAME';

	next unless $a->{type} eq 'A' || $a->{type} eq 'AAAA';


	# if we have an answer, it always updates cache
	$me->debug( "RESOLV - caching $h = $a->{answer}" );

	my $t = $a->{xttl};
	$t = $me->{resolv}{ttl_min} if $t < $me->{resolv}{ttl_min};
	$t = $me->{resolv}{ttl_max} if $t > $me->{resolv}{ttl_max};

	$cache{$h} = {
	    fqdn   => $z,	# record fqdn
	    addr   => $a->{rdata},
	    expire => $^T + $t,
	};
    }
}

sub writable {
    my $me = shift;

    my( $host, $qhost, $opt );
    while( @todo && ! $host ){
	$host = shift @todo;
	delete $todo{$host};
	$host = undef if $pending{$host};
    }
    unless( $host ){
	$me->debug( 'RESOLV - writable but queue empty' );

	if( $me->{resolv}{n_queries} ){
	    # pending queries to wait for
	    $me->wantwrit(0);
	}else{
	    $me->done();
	}
	return;
    }

    $qhost = $host;
    $qhost =~ s/\.$//;
    # undocumented feature: 'www.example.com._ipv4', 'www.example.com._ipv6'
    # QQQ or _ipv4.www.example.com

    if( $host =~ /^(\S+)\._ipv(.)/ ){
        $opt   = $2;
        $qhost = $1;
    }
    $opt ||= '46';

    my $fh = $me->{fd};

    my @zone;
    if( $cache{$host} ){
	if( $cache{$host}{fqdn} ){
	    # use known correct fqdn
	    push @zone, $cache{$host}{fqdn};
	}elsif( $cache{$host}{srch} ){
	    # try next search domain
	    my $i = $cache{$host}{srch_i} ++;
	    $i %= @{ $cache{$host}{srch} };
	    my $srch = $cache{$host}{srch}[$i];

	    push @zone, ( $srch ? "$qhost.$srch" : $qhost );
	}else{
	    push @zone, $qhost;
	}
    }else{
	push @zone, $qhost;
	# ...
    }

    foreach my $zone (@zone) {
	# send Q - A and AAAA
	for my $qt ( 'A', ($::HAVE_S6 ? 'AAAA' : ()) ){

	    next if ($qt eq 'A')    && ($opt !~ /4/);
	    next if ($qt eq 'AAAA') && ($opt !~ /6/);

	    my $qidn = $me->{resolv}{qidn};
	    my $qid  = $qidmap[$qidn];
	    my $q = DNS::build_packet( undef, undef, {
		query   => $qt,
		class   => 'IN',
		qid     => $qid,
		recurse => 1,
		zone    => $zone,
	    } );

	    $me->debug( "RESOLV - sending query $qid $qt($zone)" );

	    my $i = send( $fh, $q, 0 );
	    unless($i){
		my $m = "send failed: $!";
		::sysproblem( "RESOLV $m" );
		$me->debug( $m );
		$me->next_ns();
		add_todo( $host );
		return $me->done();
	    }

	    $me->{resolv}{inflight} ++;
	    $me->{resolv}{n_queries} ++;
	    $me->{resolv}{pending}{$qid} = { host => $host, zone => $zone };
	    $pending{$host} = $^T;
	    $qidn ++;
	    $qidn &= 0xFFFF;
	    $me->{resolv}{qidn} = $qidn;
	}
    }

    $me->maybe_wantwrit();
    $me->wantread(1);
    $me->{srvc}{state} = 'resolving';
}

sub timeout {
    my $me = shift;

    $me->debug( 'RESOLV - TO' );

    # pick new ns
    $me->next_ns() unless $me->{resolv}{n_responses};
    $me->done();
}

sub done {
    my $me = shift;

    $me->debug( 'RESOLV - done' );

    # dump pending back to todo list
    my $lost = 0;
    foreach my $q ( sort keys %{ $me->{resolv}{pending} } ){
	my $h = $me->{resolv}{pending}{$q}{host};
	delete $pending{$h};
	$lost ++;
	$me->debug( "RESOLV - response never rcvd: $q - $h" );

	# don't care about lost responses if we got an answer already
	# eg. got an A response, lost the AAAA response
	next if $cache{$h} && $cache{$h}{addr} && $cache{$h}{expire} > $^T;

	# no address yet, at least one pkt was dropped. -- force fast retry.
	add_todo( $h );
    }
    delete $me->{resolv}{pending};

    $me->Service::done();

    $me->debug("RESOLV lost $lost (nq=$me->{resolv}{n_queries}, nr=$me->{resolv}{n_responses})")
	if $lost;
}

sub qidshuffle {

    my $i = @qidmap;
    while (--$i) {
	my $j = int rand ($i+1);
	@qidmap[$i,$j] = @qidmap[$j,$i];
    }
}

################################################################

sub janitor {

    # in case there is a bug and someone gets trapped in the queue...
    # or a packet gets dropped
    foreach my $h ( keys %pending ){
	delete $pending{$h} if $pending{$h} + $OLD_AGE < $^T;
    }
}

sub about_more {
    my $me = shift;
    my $ctl = shift;
    my( $k, $v );

    $me->SUPER::about_more($ctl);
    $me->more_about_whom($ctl, 'resolv');
}

sub gen_conf_decl { 'Resolv' }

sub gen_confs {
    my $conf;

    foreach my $n (0 .. $n_resolv - 1 ){
	my $r = $MonEl::byname{"Resolv_$n"};
	$conf .= $r->gen_conf();
    }
    $conf = "\n$conf" if $conf;
    $conf;
}

################################################################

sub cmd_todo {
    my $ctl = shift;

    $ctl->ok();
    foreach my $h (@todo){
	$ctl->write("$h: 1\n");
    }
    $ctl->final();
}

sub cmd_pending {
    my $ctl = shift;

    $ctl->ok();
    foreach my $h (sort keys %pending){
	$ctl->write("$h: $pending{$h}\n");
    }
    $ctl->final();
}

sub cmd_cache {
    my $ctl = shift;

    $ctl->ok();
    foreach my $h (sort keys %cache){
	$ctl->write("$h addr: ". ::inet_ntoa($cache{$h}{addr}) . "\n")
	    if $cache{$h}{addr};
	foreach my $k (qw(expire rcode fqdn srch_i)){
	    $ctl->write("$h $k: $cache{$h}{$k}\n") if $cache{$h}{$k};
	}
	$ctl->write("$h srch: @{$cache{$h}{srch}}\n") if $cache{$h}{srch};

    }
    $ctl->final();
}

################################################################
Doc::register( $doc );
push @Service::probes, \&probe;

Control::command_install('resolv_todo',    \&cmd_todo);
Control::command_install('resolv_pending', \&cmd_pending);
Control::command_install('resolv_cache',   \&cmd_cache);


Cron->new( freq => 3600,
	   text => 'Resolv cleanup',
	   func => \&janitor,
	   );

1;
