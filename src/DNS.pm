# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Nov-13 10:53 (EST)
# Function: a swiss-army DNS tester
#
# $Id: DNS.pm,v 1.29 2012/10/12 02:17:31 jaw Exp $

# it seems that there is no end to the DNS server mis-configurations
# and failure modes that are available. this is an attempt to stay one step ahead.

# common configs
#   backwards compat with 3.1
#     Service UDP/DNS
#     Service UDP/DNSQ
#     Service UDP/Domain/zone
#   in general
#     Service UDP/DNS/TEST/zone
#     Service UDP/DNS {
#	query: query_type
#	test:  test_type
#	zone:  zone
#	...
#     }

package DNS;

use strict qw(refs vars);
use vars qw($doc @ISA);

my %qtypes =
(
 # RFC 1035 - 3.2.2
 A => 1, NS => 2, CNAME => 5, SOA => 6, WKS => 11,
 PTR => 12, HINFO => 13, MX => 15, TXT => 16, ANY => 255,
 AFS  => 18,	# RFC 1183 - 1
 AAAA => 28,	# RFC 1886 - 2.1
 LOC  => 29,	# RFC 1876 - 1
 SRV  => 33,	# RFC 2782
 AXFR => 252,   # only for use with TCP
 );
my %qtypes_rev = reverse %qtypes;

my %qclass =
(
 # RFC 1035 - 3.2.4
 IN => 1, CS => 2, CH => 3, HS => 4, ANY => 255,
 );
my %qclass_rev = reverse %qclass;

my %rcode =
    # RFC 1035 - 4.1.1
( 0 => 'none', 1 => 'Format Error', 2 => 'Server Failure',
  3 => 'Name Error', 4 => 'Not Impl', 5 => 'Refused',
  );

$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [qw(UDP Service MonEl BaseIO)],
    methods => {},
    versn => '3.2',
    html  => 'dns',
    fields => {

      dns::zone => {
	  descr => 'DNS zone to test',
	  attrs => ['config'],
	  exmpl => 'example.com',
      },
      dns::query => {
	  descr => 'query type',
	  attrs => ['config'],
	  vals  => ['STAT', sort keys %qtypes],
	  # NB: queries that argus does not know about can be specified numerically
      },
      dns::class => {
	  descr => 'query class',
	  attrs => ['config'],
	  vals  => [ sort keys %qclass ],
	  # NB: classes that argus does not know about can be specified numerically
      },
      dns::test  => {
	  descr => 'how to test the result',
	  attrs => ['config'],
	  vals  => [qw(none noerror authok serial answer nanswers authority nauthority additional nadditional aaa)],
	  # none       = up if we get a response
	  # noerror    = response contains no errors
	  # authok     = response is authoratative
	  # serial     = test( serial )
	  # nanswers   = test( # of answers )
	  # answer     = test( answers )
          # authority  = test( authority )
          # additional = test( additional )
          # aaa        = answer + authority + additional
      },
      dns::recurse => {
	  descr => 'recursion desired?',
	  attrs => ['config', 'bool'],
      },
      dns::name => {},
    },
};

my %conf =
(
 Domain => { query => 'SOA',	test => 'authok', 	recurse => 0, },
 DNS	=> { query => 'STAT',	test => 'none',		recurse => 0, },
 DNSQ	=> { query => 'NS',	test => 'noerror',	recurse => 1,	  zone => '.', },
 Serial	=> { query => 'SOA',	test => 'serial',	recurse => 1, },
 BIND   => { query => 'TXT',   class => 'CH',		test => 'answer', zone => 'version.bind', },
 );

my $qid = $$;


sub config {
    my $me = shift;
    my $cf = shift;
    my( $name, $t, $n, $z );

    $name = $me->{name};
    # undocumented feature: 'UDP/' is optional
    # [UDP/](DNS|Domain)[/QUERY][/zone]
    $name =~ s/^UDP\///;
    $name =~ s/^TCP\///;
    ($n, $t, $z) = split /\//, $name, 3;
    $me->{dns}{name} = $name;
    if( !$conf{$t} && !$z ){
	# no QUERY specified: DNS/zone
	$z = $t;
	$t = undef;
    }
    if( !$t ){
	$t = $n;
    }

    if( $conf{$t} ){
	# set defaults from conf table
	foreach my $k ( %{$conf{$t}} ){
	    $me->{dns}{$k} = $conf{$t}{$k};
	}
    }elsif( $t ){
	# if specified as DNS/QUERY[/zone] set defaults as:
	$me->{dns}{query}   = $t;
	$me->{dns}{test}    = 'answer';
	$me->{dns}{recurse} = 1;
    }
    # else { query/recurse/test need to be specified explicitly }

    $me->{dns}{zone} = $z if $z;

    $me->init_from_config( $cf, $doc, 'dns' );

    # auto-in-addr.arpa-ize
    if( $me->{dns}{zone} =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/ ){
	$me->{dns}{zone} = "$4.$3.$2.$1.in-addr.arpa";
    }

    $cf->warning("unknown DNS test method '$me->{dns}{test}")
	unless grep {$_ eq $me->{dns}{test}} qw(none noerror authok serial answer nanswers authority nauthority additional nadditional aaa);

    $me->{friendlyname} = "DNS for $me->{dns}{zone} on $me->{ip}{hostname}";

    $me;
}

# He knew Himself to sing, and build the lofty rhyme.
#   -- John Milton, Lycidas
sub build_packet {
    my $me  = shift;
    my $cf  = shift;
    my $dns = shift; # {class, query, recurse, zone}
    my( $qt, $qc, $q, @q );

    if( $dns->{query} eq 'STAT' ){
	# op=status, not supported by all DNS servers
	return pack("n CC nnnn", ($dns->{qid} || $qid++), 0x10,0, 0,0,0,0);
    }
    $qt = $qtypes{$dns->{query}} || $dns->{query};
    $qc = $qclass{$dns->{class}} || $dns->{class};
    $qc = 1 unless $qc + 0;
    if( $qt + 0 ){
	# RFC 1035 - 4.1.1
	$q = pack( "n CC nnnn", ($dns->{qid} || $qid++),
		   ($dns->{recurse} ? 1 : 0),
		   0, 1,0,0,0);  # op=query, 1 question

	# RFC 1035 - 4.1.2
	@q = split /\./, $dns->{zone};
	foreach my $l (@q){
	    $q .= chr(length($l)) . $l;
	}
	$q .= "\0";		    # terminate QNAME
	$q .= pack("nn", $qt, $qc); # QTYPE, QCLASS
	return $q;
    }else{
	return $cf->error( "unknown DNS query, care to show me how?" ) if $cf;
    }
}

sub testable {
    my $me = shift;
    my $l  = shift;
    my( $tt, $aa, $ec, $ans );

    # get error code, and auth flag
    $aa = unpack('x2 C', $l) & 0x4;
    $ec = unpack('x3 C', $l) & 0xF;

    $tt = $me->{dns}{test};

    if( !$tt || $tt eq 'none' ){
	# recvd response => up
	return $me->isup();
    }
    # everything else checks error field
    if( $ec ){
	my $em = $rcode{$ec} || '';
	$em = " - $em" if $em;
	return $me->isdown( "DNS Error$em (RCODE=$ec)", 'error' );
    }
    if( $tt eq 'noerror' ){
	# no error => up
	return $me->isup();
    }
    if( $tt eq 'authok' ){
	# He looked at the Gryphon as if he thought it had some kind of authority over Alice.
	#   -- Alice in Wonderland
	if( $aa ){
	    return $me->isup();
	}else{
	    return $me->isdown( "DNS Error - Non-Authoratative Response", 'error' );
	}
    }

    if( $tt eq 'nanswers' ){
	# number of answers returned
	my $r = unpack( "x6n", $l );
	return $me->generic_test( $r, 'DNS' );
    }
    if( $tt eq 'nauthority' ){
	# number of ns records returned
	my $r = unpack( "x8n", $l );
	return $me->generic_test( $r, 'DNS' );
    }
    if( $tt eq 'nadditional' ){
	# number of additional records returned
	my $r = unpack( "x10n", $l );
	return $me->generic_test( $r, 'DNS' );
    }

    # fetch answers
    my $dns;
    eval {
	$dns = $me->decode( $l );
    };
    if( $@ ){
	# any error decoding answer => down
	return $me->isdown( $@->[0], 'error' );
    }

    if( $tt eq 'serial' ){
	return $me->isdown( "DNS Error - Did not find SOA serial", 'error' )
	    unless defined($dns->{serial});
	return $me->generic_test( $dns->{serial}, 'DNS' );
    }

    # anything else: test the answers
    # we may have multiple answers, concatenate them with \n

    my @res;
    push @res, @{$dns->{answers}}    if $tt eq 'answer'     || $tt eq 'aaa';
    push @res, @{$dns->{authority}}  if $tt eq 'authority'  || $tt eq 'aaa';
    push @res, @{$dns->{additional}} if $tt eq 'additional' || $tt eq 'aaa';

    my $answer = join "\n", map {
	"$_->{name}\t$_->{ttl}\t$_->{class}\t$_->{type}\t$_->{answer}"
    } @res;

    return $me->generic_test( $answer, 'DNS' );
}

sub skip_name {
    my $pkt = shift;
    my $off = shift;
    my( $pktlen, $skip );

    $pktlen = length($pkt);
    $skip   = 0;
    # RFC 1035 - 3.1, 3.3
    while( 1 ){
	my $p = $off + $skip;
	my $len = unpack("x$p C", $pkt);
	if( $len >= 0xC0 ){
	    # compressed
	    $skip +=2;
	    last;
	}
	if( $len + $off + $skip > $pktlen ){
	    die ["DNS Error - Corrupt NAME"];
	}
	$skip += $len + 1; 	# 1 byte len + len bytes data
	last unless $len;	# null terminator?
    }
    $skip;
}

sub decode_name {
    my $pkt = shift;
    my $off = shift;
    my( $pktlen, $name, $jumps );

    $pktlen = length($pkt);
    while( 1 ){
	my $len = unpack("x$off C", $pkt);
	if( $len >= 0xC0 ){
	    # compressed - jump inside packet
	    # RFC 1035 - 4.1.4
	    $off = unpack("x$off n", $pkt);
	    $off &= 0x3FFF;
	    if( $off > $pktlen ){
		die ["DNS Error - Corrupt NAME (cannot decode)"];
	    }
	    if( ++$jumps > 15 ){
		die ["DNS Error - Corrupt NAME (loop detected)"];
	    }
	    next;
	}
	if( $len + $off > $pktlen ){
	    die ["DNS Error - Corrupt NAME (cannot decode)"];
	}
	if( $len ){
	    my $lb = unpack( "x$off xA$len", $pkt );
	    $name .= '.' if $name;
	    $name .= $lb;
	}
	$off += $len + 1; 	# 1 byte len + len bytes data
	last unless $len;	# null terminator?
    }
    $name .= '.';
    $name;
}

# You are full of pretty answers.
#   -- Shakespeare, As You Like It
sub ttlpretty {
    my $t = shift;

    my @t = map {
	my $a = $t % $_;  $t = int($t/$_); $a;
    } (60, 60, 24, 7, 52);
    push @t, $t;

    my $r = join('', map {
	my $a = pop @t; $a ? sprintf "%d%s", $a, $_ : '';
    } (qw(y w d h m s)));

    $r || '0';
}

sub decode {
    my $me  = shift;
    my $pkt = shift;

    my $r = {};
    my $pktlen = length($pkt);
    $r->{id} = unpack( 'n', $pkt );	# id

    # number of questions, answers, auth, and additional
    ($r->{nq}, $r->{na}, $r->{nauth}, $r->{nmore})
      = unpack("x4nnnn", $pkt);

    my $off = 12;			# start of question section
    my( $i );

    $me->debug( "DNS decoding: $r->{nq} questions => $r->{na} answers + $r->{nauth} auth + $r->{nmore} addtnl" );
    # skip over questions
    # Aeolus entertained me for a whole month asking me questions all the
    # time about Troy, the Argive fleet, and the return of the Achaeans
    #   -- Homer, Odyssey
    for( $i=0; $i<$r->{nq}; $i++){
	$off += skip_name( $pkt, $off );
	$off += 4;   # QTYPE, QCLASS
    }

    # parse out answers
    # RFC 1035 - 4.1.3
    # And all that heard him were astonished at his understanding and answers
    #   -- Luke 2:47

    my(@ans, @auth, @more);
    ($off, @ans)  = parse_section($me, $pkt, $r, $r->{na},    $off, 'answer');
    ($off, @auth) = parse_section($me, $pkt, $r, $r->{nauth}, $off, 'authty');
    ($off, @more) = parse_section($me, $pkt, $r, $r->{nmore}, $off, 'addtnl');

    $r->{answers}    = \@ans;
    $r->{authority}  = \@auth;
    $r->{additional} = \@more;

    $r;
}

sub parse_section {
    my $me  = shift;
    my $pkt = shift;
    my $hdr = shift;
    my $nrr = shift;
    my $off = shift;
    my $tag = shift;

    my @res;
    my $pktlen = length($pkt);
    for( my $i=0; $i<$nrr; $i++ ){
	my $start = $off;
	# get NAME
	my $what = decode_name( $pkt, $off );
	$off += skip_name( $pkt, $off );

	my( $type, $class, $ttl, $rdlen ) = unpack( "x$off nnNn", $pkt );
	$type  = $qtypes_rev{$type} || $type;
	$class = $qclass_rev{$class}|| $class;
	$off += 10;	# 10 = sizeof(nnNn)
	if( $off + $rdlen > $pktlen ){
	    die ["DNS Error - Corrupt Response (RDATA)"];
	}
	my $rdata = unpack( "x$off a$rdlen", $pkt );
	my $res = {
	    name  => $what,
	    start => $start,	# offset of start of answer
	    rdoff => $off,	# offset of RDATA
	    type  => $type,
	    class => $class,
	    xttl  => $ttl,
	    ttl   => ttlpretty($ttl),
	    rdlen => $rdlen,
	    rdata => $rdata,
	};
        push @res, $res;
	$off += $rdlen;

        decode_rdata($res, $pkt, $hdr);
	$me->debug( "DNS $tag: $res->{name} $res->{ttl} $res->{class} $res->{type} '$res->{answer}'" );
    }

    return ($off, @res);
}

sub decode_rdata {
    my $rr  = shift;
    my $pkt = shift;
    my $hdr = shift;

    my $type = $rr->{type};

    if( $type eq 'A' ){
        $rr->{answer} = join('.', unpack('C*', $rr->{rdata}) );
    }

    elsif( $type eq 'AAAA' ){
        # RFC 1886 - 2.2
        $rr->{answer} = join(':', map {sprintf "%x", $_ } unpack('n*', $rr->{rdata}) );
    }

    elsif( $type eq 'TXT' ){
        $rr->{answer} = unpack( "xA*", $rr->{rdata} );
    }

    elsif( $type eq 'HINFO' ){
        my($cpu, $os, $l);
        $l   = unpack("C", $rr->{rdata} );
        $cpu = unpack( "xA$l", $rr->{rdata} );
        $os  = unpack( "x x$l x A*", $rr->{rdata} );
        $rr->{answer} = "$cpu $os";
    }

    elsif( $type eq 'CNAME' || $type eq 'PTR' || $type eq 'NS' ){
        $rr->{answer} = decode_name( $pkt, $rr->{rdoff} );
    }

    elsif( $type eq 'MX' || $type eq 'AFS' ){
        my( $pref, $name );
        $pref = unpack( "n", $rr->{rdata} );
        $name = decode_name( $pkt, $rr->{rdoff} + 2 );
        $rr->{answer} = "$pref $name";
    }

    elsif( $type eq 'SOA' ){
        my( $mname, $rname, );
        my $off = $rr->{rdoff};
        $mname = decode_name( $pkt, $off );
        $off += skip_name( $pkt, $off );
        $rname = decode_name( $pkt, $off );
        $off += skip_name( $pkt, $off );
        my( $serial, $refresh, $retry, $expire, $min
           ) = unpack( "x$off NNNNN", $pkt );
        $hdr->{serial} = $serial;	# for easy access
        $rr->{answer} = "$mname $rname $serial " .
          ttlpretty($refresh) . " " . ttlpretty($retry) . " " .
            ttlpretty($expire)  . " " . ttlpretty($min);
    }

    elsif( $type eq 'LOC' ){
        # you know, like in case someone wants argus to notify them
        # if someone physically relocates a server....
        my($N, $E) = ('N', 'E');
        my($ver, $size, $hp, $vp,
           $lat, $long, $alt) = unpack( 'CCCC NNN', $rr->{rdata} );

        $size = (($size>>4) * 10 ** ($size & 0xF)) / 100;
        $hp   = (($hp>>4)   * 10 ** ($hp & 0xF))   / 100;
        $vp   = (($vp>>4)   * 10 ** ($vp & 0xF))   / 100;
        $alt  = ($alt/100) - 100000;
        $long = ($long - (1<<31)) / 1000;
        $lat  = ($lat  - (1<<31)) / 1000;
        if( $lat  < 0 ){ $lat  = - $lat,  $N = 'S' }
        if( $long < 0 ){ $long = - $long, $E = 'W' }
        $long = sprintf( "%d %d %.3f $N", $long/3600, ($long%3600)/60, ($long%60));
        $lat  = sprintf( "%d %d %.3f $E", $lat/3600,  ($lat%3600)/60,  ($lat%60));

        $rr->{answer} = "$lat $long ${alt}m ${size}m ${hp}m ${vp}m";
    }
    # elsif( $type eq 'SRV' ){
    # I don't see anything on how the packet is encoded in 2782
    # I could make a reasonable guess,...

    else{
        # QQQ - what should we do with unknown dns data type
        $rr->{answer} = $rr->{rdata};
    }
}

################################################################
Doc::register( $doc );

1;

