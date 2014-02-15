# -*- perl -*-

# Copyright (c) 2003 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2003-May-22 21:46 (EDT)
# Function: caching async resolver + re-resolver
#
# $Id: Argus::Resolv.pm,v 1.6 2012/12/29 21:47:13 jaw Exp $

# Wise to resolve, and patient to perform.
#   -- Homer, Odyssey

# runs as a standard argus Service, can have several instances


package Argus::Resolv;
@ISA = qw(Service);
use Argus::Resolv::IP;
use Socket;
BEGIN{ eval{ require Socket6; import Socket6; $HAVE_S6 = 1; }}

use strict qw(refs vars);
use vars qw(@ISA $doc $HAVE_S6 $enable_p $total_queries);

$enable_p = 0;
my $MAXFREQ   = 20;
my $OLD_AGE   = 60;
my $SOON      = 15;
my $KEEP_OLD  = 600;
my $PROTO_UDP = 17;
my $DNS_PORT  = 53;
my $MAXCNAME  = 10;		# don't follow cnames more than so far
my $DEFEXPIRE = 3600;		# expire time for things that don't expire
my $ABITEARLY = 15;
my $AUTOEACH  = 100;
my $AUTOMAX   = 20;

my $n_resolv  = 0;
my %fqdn      = ();
my %srch      = ();
my %cache     = ();		# cache{fqdn} = { res{addr} => {type, addr, when, expire}, prev, error }
my @todo      = ();		# hostnames to be looked up
my %todo      = ();             # ditto
my %pending   = ();		# pending queries
my @qidmap    = (0 .. 65535);	# randomize qid
my $resolver;			# idle resolver
$total_queries = 0;

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
	    default => '1min',
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
# these funcs provide the public interface
#
# both will return either an addr or undef
################################################################

sub resolv_add {
    my $cf   = shift;
    my $host = shift;
    my( $ip, $type );

    # check for dotted quad
    if( $host =~ /^\d+\.\d+\.\d+\.\d+$/ ){
	$ip = inet_aton( $host );
        _add_cache($host, 'A', $ip, 0, 0);
        return;
    }
    # check for cologned octopus
    elsif( $host =~ /^[a-f\d:]+$/i && $HAVE_S6 ){
	$ip = inet_pton(AF_INET6, $host);
        _add_cache($host, 'AAAA', $ip, 0, 0);
        return;
    }

    add_todo( $host );

    # add more?
    if( ($n_resolv * $AUTOEACH < @todo) && $n_resolv < $AUTOMAX ){
        $resolver->clone_me( $cf, 1 ) if $cf && $resolver && $resolver->{autoconf};
    }

    return;
}

sub resolv_results {
    my $host = shift;
    my $opts = shift;

    _resolv_results($host, $opts, $MAXCNAME);
}

sub resolve_next_needed {
    my $host = shift;
    my $time = shift;

    $host = $fqdn{$host} if $fqdn{$host};
    my $cake = $cache{$host};

    unless( $cake ){
        # 1st query still pending
        my $t = $time - $ABITEARLY;
        if( $t > $^T ){
            _debug("schedule update $host when needed $t");
            Cron->new( time => $t, func => \&_refresh, args => [$host, $time, 0], text => "resolve $host" );
        }
        return;
    }

    my($exp, $ttl) = _time_window($cake);

    # recurse cnames
    _resolve_next_needed_cnames($cake, $time);

    return unless $exp;		# no results, or none that expire

    _debug("needed $host @ $time, $exp/$ttl");

    return if $time < $exp;	# data will still be good

    if( $time < $exp + $ttl ){
        # refresh at expire, and we'll be good

        delete $cake->{atexpire} if $cake->{atexpire} <= $^T;

        # already something scheduled? is it good?
        return if $cake->{atexpire} < $time && $cake->{atexpire} + $ttl > $time;

        unless( $cake->{atexpire} ){
            # schedule it
            _debug("schedule update $host at expire $exp");
            if( $exp <= $^T ){
                _refresh([ $host, $time, $ttl ]);
            }else{
                Cron->new( time => $exp, func => \&_refresh, args => [$host, $time, $ttl], text => "resolve $host" );
                $cake->{atexpire} = $exp;
            }
            return;
        }
    }

    my $t = $time - $ABITEARLY;
    _debug("schedule update $host when needed $t");
    if( $t <= $^T ){
        _refresh([ $host, $time, $ttl ]);
    }else{
        Cron->new( time => $time - $ABITEARLY, func => \&_refresh, args => [$host, $time, $ttl], text => "resolve $host" );
    }
}

################################################################

sub _refresh {
    my $args = shift;
    my($host, $time, $ttl) = @$args;

    $host = $fqdn{$host} if $fqdn{$host};
    my $cake = $cache{$host};
    return unless $cake;

    delete $cake->{atexpire} if $cake->{atexpire} <= $^T;

    _debug("refreshing $host");
    # has it been updated?
    my($exp, undef) = _time_window($cake);
    return if $exp > $time;

    add_todo( $host );
    $resolver->check_now();
}

################################################################

sub _cname_results {
    my $host = shift;
    my $opts = shift;
    my $loop = shift;

    if( $loop ){
        #_debug("following cname $host");
        my $cres = _resolv_results($host, $opts, $loop - 1);
        if( $cres ){
            # _debug("$host => " . join(' ', map{ ::xxx_inet_ntoa($_)} @{$cres->{addr}} ));
        }
        return $cres;
    }else{
        # too many cnames
        _debug("too many cnames");
        return;
    }
}

sub _clean_cache {
    my $host = shift;

    my $cake = $cache{$host};

    return if $cake->{cleaned} >= $^T;
    $cake->{cleaned} = $^T;

    for my $v (values %{$cake->{res}}){
        _clean_cake($cake, $v) if $v->{expire} && $v->{expire} <= $^T;
    }
}

sub _clean_cake {
    my $cake = shift;
    my $data = shift;

    my $a    = $data->{addr};
    my $e    = $data->{expire};

    # move expired records to prev, then delete after a time
    delete $cake->{res}{$a};
    if( $e + $KEEP_OLD > $^T ){
        $cake->{prev}{$a} = $data;
    }else{
        delete $cake->{prev}{$a};
    }
}

sub _resolv_results {
    my $host = shift;
    my $opts = shift;
    my $loop = shift;

    $host = $fqdn{$host} if $fqdn{$host};

    my $cake = $cache{$host};

    if( $cake ){
        my @a;
        my $minexp;
        my $expired;
        my $res = ($cake->{res} && keys %{$cake->{res}}) ? $cake->{res} : $cake->{prev};

        _debug("looking up $host");

        for my $a (sort keys %$res){
            my $c = $res->{$a};

            if( $c->{type} eq 'CNAME' ){
                # look up cnames
                my $cres = _cname_results($c->{addr}, $opts, $loop);
                if( $cres ){
                    push @a, @{$cres->{addr}};
                    $minexp = $cres->{expire} if $cres->{expire} && (!$minexp || ($cres->{expire} < $minexp));
                }
            }else{
                # filter by desired type
                push @a, $a if !$opts || $c->{type} eq $opts;
            }

            my $e = $c->{expire};
            if( $e ){
                $minexp  = $e if !$minexp || ($e < $minexp);
                if( $e < $^T ){
                    $expired = 1;
                    _clean_cake( $cake, $c );
                    _debug("*** expired $host => " . ($e-$^T) . " " . ::xxx_inet_ntoa($a));
                }
            }
        }

        if( !@a && $cake->{error} ){
            $minexp = $cake->{error}{expire};
        }

        if( $expired || !@a ){
            if( !$cake->{error} || ($cake->{error}{expire} < $^T) ){
                add_todo( $host );
                _debug("*** expired $host ***");
                # _dumpcake( $host );
            }
        }

        my $x = $minexp - $^T;

        _debug("addrs $host => " . join(' ', map{ ::xxx_inet_ntoa($_)} @a));

        return unless @a;

        return {
            fqdn	=> $host,
            expire	=> ($minexp || $DEFEXPIRE + $^T),
            addr	=> \@a,
        };

    }

    _debug("resolv add $host");
    resolv_add( undef, $host );

    undef;
}


################################################################
sub _resolve_next_needed_cnames {
    my $cake = shift;
    my $time = shift;

    for my $v (values %{$cake->{res}}){
        next unless $v->{type} eq 'CNAME';
        resolve_next_needed( $v->{addr}, $time );
    }
}

sub _time_window {
    my $cake = shift;

    my($min, $ttl);

    for my $v (values %{$cake->{res}}){
        my $e = $v->{expire};
        my $t = $v->{ttl};
        next unless $e;

        ($min,$ttl) = ($e,$t) if !$min || $e < $min;
    }

    if( $cake->{error} && !$min ){
        $min = $cake->{error}{expire};
        $ttl = $cake->{error}{ttl};
    }

    return ($min, $ttl);
}

sub _dumpcake {
    my $host = shift;

    my $cake = $cache{$host};
    my $cr = ($cake->{res} && keys %{$cake->{res}}) ? $cake->{res} : $cake->{prev};

    _debug( "====");
    for my $v (values %$cr){
        my $t = $v->{expire} - $^T;
        if( $v->{type} eq 'CNAME' ){
            _debug( "$host\t$t\t$v->{type}\t$v->{addr}");
            _dumpcake( $v->{addr} );
        }else{
            _debug( "$host\t$t\t$v->{type}\t" . ::xxx_inet_ntoa($v->{addr}));
        }
    }
}

sub _debug {
    my $msg = shift;

    return unless $resolver;
    $resolver->debug($msg);
}

sub _add_cache {
    my $name = shift;
    my $type = shift;
    my $addr = shift;
    my $exp  = shift;	# 0 => never expires
    my $ttl  = shift;

    my $r = {
        type	=> $type,
        addr	=> $addr,
        expire  => $exp,
        ttl     => $ttl,
        when	=> $^T,
    };

    _debug("add cache $name");
    delete $cache{$name}{res} if $type eq 'CNAME'; # there can be only one

    $cache{$name}{updated}    = $^T;
    $cache{$name}{res}{$addr} = $r;

    delete $cache{$name}{error};
    delete $cache{$name}{prev}{$addr};
    _clean_cache($name);
}

sub add_todo {
    my $h = shift;

    return if $todo{$h};
    return if $pending{$h};
    $todo{$h} = 1;
    push @todo, $h;
}

sub remove_todo {
    my $h = shift;

    delete $todo{$h};
    @todo = grep {$_ ne $h} @todo;
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

    if( $me->{resolv}{search} ){
        $me->{resolv}{domlist} = [ '', split /\s+/, $me->{resolv}{search} ];
    }else{
	$me->{resolv}{search}  = ' ' . join(' ', @dom);
        $me->{resolv}{domlist} = [ '', @dom ];
    }

    unless( $::opt_t ){
	::loggit( "Asynchronous Resolver enabled" ) unless $enable_p;
	$enable_p = 1;
    }

    if( $me->{resolv}{duplicates} > 0 ){
	$me->clone_me( $cf, $me->{resolv}{duplicates} );
    }

    qidshuffle();

    $resolver = $me;
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
    $resolver = $me;

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
    $ip = $me->{udp}{addr} = $me->{resolv}{nameserver};

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
    my $zdot = "$z.";
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

	if( $fqdn{$h} ){
	    # if we have an addr, keep it
	    $me->debug( "RESOLV keeping value for $h" );

            $cache{$fqdn{$h}}{error} = {
                expire => $^T + $et,
                ttl    => $et,
                rcode  => $ec,
            };
	}
	else{
            $cache{$h}{error} = {
                expire => $^T + $et,
                ttl    => $et,
                rcode  => $ec,
            };

	    if( $ec == 3 && $me->{resolv}{domlist} && ($h !~ /\.$/) ){
		# nxdomain: try search domains
		$srch{$h}{srch} ||= $me->{resolv}{domlist};
		$srch{$h}{srch_i} = 1 unless defined $srch{$h}{srch_i};

		# go through the entire list, then delay ttl_nxdomain

		if( $srch{$h}{srch_i} % @{$srch{$h}{srch}} ){
		    $srch{$h}{error}{expire} = $^T;
		    add_todo( $h );
		    $me->debug("RESOLV recv nxdomain $h - retry now");
		}
	    }
	}

	return;
    }

    # decode packet, find correct answer, there may be several...

    foreach my $a ( @{ $r->{answers} } ){
	$me->debug( "RESOLV recv $a->{name} $a->{ttl} $a->{class} $a->{type} $a->{answer}" );

	next unless $a->{type} eq 'A' || $a->{type} eq 'AAAA' || $a->{type} eq 'CNAME';

        # got a response for this fqdn. save it.
        if( $zdot eq $a->{name} && $h !~ /\.$/ ){
            $me->debug( "RESOLV - saving fqdn $h => $zdot") unless $fqdn{$h};
            $fqdn{$h} = $zdot;
            delete $cache{$h};
            delete $cache{$z};
        }

	my $t = $a->{xttl};
	$t = $me->{resolv}{ttl_min} if $t < $me->{resolv}{ttl_min};
	$t = $me->{resolv}{ttl_max} if $t > $me->{resolv}{ttl_max};

	# if we have an answer, it always updates cache
        $me->debug("RESOLV - caching $a->{name} => $a->{answer} for $t");

        my $val = ($a->{type} eq 'CNAME') ? $a->{answer} : $a->{rdata};
        _add_cache($a->{name}, $a->{type}, $val, $^T + $t, $t);
    }

}

sub writable {
    my $me = shift;

    my( $host, $qhost );
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

    my $fh = $me->{fd};

    my @zone;
    if( $fqdn{$host} ){
        # use known correct fqdn
        ($qhost = $fqdn{$host}) =~ s/\.$//;
        push @zone, $qhost;
    }elsif( $srch{$host} ){
        # try next search domain
        my $i = $srch{$host}{srch_i} ++;
        $i %= @{ $srch{$host}{srch} };
        my $srch = $srch{$host}{srch}[$i];

        push @zone, ( $srch ? "$qhost.$srch" : $qhost );
    }else{
        push @zone, $qhost;
    }


    foreach my $zone (@zone) {
	# send Q - A and AAAA
	for my $qt ( 'A', ($::HAVE_S6 ? 'AAAA' : ()) ){

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

            $total_queries ++;
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
	next if $cache{$h} && $cache{$h}{res};

	# no address yet, at least one pkt was dropped. -- force fast retry.
	add_todo( $h );
    }
    delete $me->{resolv}{pending};

    $me->Service::done();

    $me->debug("RESOLV lost $lost (nq=$me->{resolv}{n_queries}, nr=$me->{resolv}{n_responses})")
	if $lost;

    $resolver = $me;
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
        my $cake = $cache{$h};

        if( $cake->{res} && keys %{$cake->{res}} ){
            for my $r (values %{$cake->{res}}){
                next unless $r->{expire};
                my $t = $r->{expire} - $^T;
                my $v = ($r->{type} eq 'CNAME') ? $r->{addr} : ::xxx_inet_ntoa($r->{addr});
                $ctl->write("$h\t$t\t$r->{type}\t$v\n");
            }
        }elsif( $cake->{error} ){
            $ctl->write("$h\terror\n");
        }else{
            $ctl->write("$h\tempty\n");
        }
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
