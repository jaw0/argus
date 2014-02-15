# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Apr-03 18:59 (EST)
# Function: testing of SNMP things - support for both v1, v2c and v3
#
# $Id: Argus::SNMP.pm,v 1.19 2012/12/02 22:21:40 jaw Exp $

# SNMP v1 => RFC 1157
# SNMP v2 => RFC 1905
# SNMP v3 => RFC 3414

package Argus::SNMP;
@ISA = qw(UDP);

use Encoding::BER::SNMP;
use Argus::Encode;
use Argus::SNMP::Helper;
use Argus::SNMP::Conf;
my( $HAVE_MD5, $HAVE_SHA1, $HAVE_HMAC, $HAVE_DES, $HAVE_3DES, $HAVE_AES);

BEGIN {
    # these are used for SNMPv3 auth + priv
    eval{ require Digest::MD5;     $HAVE_MD5  = 1; };
    eval{ require Digest::SHA1;    $HAVE_SHA1 = 1; };
    eval{ require Digest::HMAC;    $HAVE_HMAC = 1; };
    eval{ require Crypt::DES;      $HAVE_DES  = 1; };
#    eval{ require Crypt::3DES;     $HAVE_3DES = 1; };	# RSN - write Crypt::3DES
#    eval{ require Crypt::Rijndael; $HAVE_AES  = 1; };

    $HAVE_MD5 = $HAVE_SHA1 = undef unless $HAVE_HMAC;
}

use strict qw(refs vars);
use vars qw(@ISA $doc);

my $snmpid = rand( 1000000 );
my $SNMP3_TIME_WINDOW = 150;		# rfc 3414 2.2.3
my $BER_DEBUG = 0;
my $MULTI_MAX = 20;

# let user specify some common OIDs by name
my %OIDS =
(
 sysUptime     => { oid => '.1.3.6.1.2.1.1.3',      idx => 0 },
 ifNumber      => { oid => '.1.3.6.1.2.1.2.1',      idx => 0 },
 ifDescr       => { oid => '.1.3.6.1.2.1.2.2.1.2',  idx => 'if' },
 ifAdminStatus => { oid => '.1.3.6.1.2.1.2.2.1.7',  idx => 'if', up => 1 },
 ifOperStatus  => { oid => '.1.3.6.1.2.1.2.2.1.8',  idx => 'if', up => 1 },
 ifInErrors    => { oid => '.1.3.6.1.2.1.2.2.1.14', idx => 'if'	},
 ifOutErrors   => { oid => '.1.3.6.1.2.1.2.2.1.20', idx => 'if'	},
 ifInOctets    => { oid => '.1.3.6.1.2.1.2.2.1.10', idx => 'if', calc => 'ave-rate-bits' },
 ifOutOctets   => { oid => '.1.3.6.1.2.1.2.2.1.16', idx => 'if', calc => 'ave-rate-bits' },
 BGPPeerState  => { oid => '.1.3.6.1.2.1.15.3.1.2', idx => 'peerIP', up => 6 },

 # status of isdn d-channel
 isdnLapdOperStatus                => { oid => '.1.3.6.1.2.1.10.20.1.3.4.1.2', idx => 'if', up => 3 },

 # yeah, it is much shorter to type 'ciscoEnvMonTemperatureStatusValue' ...
 ciscoEnvMonTemperatureStatusValue => { oid => '.1.3.6.1.4.1.9.9.13.1.3.1.3' },

 dskPercent    => { oid => '.1.3.6.1.4.1.2021.9.1.9', idx => 'ucddsk' },

 # additional entries added at runtime via 'mibfile' or 'snmpoid' parameter

 );

# user-friendly names for some common errors
my %errstat =
(
 1 => 'too big',
 2 => 'invalid OID',
 3 => 'bad value',
 4 => 'read only',
 5 => 'general error',
 6 => 'access denied',

 13 => 'resource unavailable',
 16 => 'authorization error',

 );

# convert common v3 errors to user-friendly messages
my %v3errs =
(
 '1.3.6.1.6.3.15.1.1.1.0'  => 'unsupported security level',
 '1.3.6.1.6.3.15.1.1.2.0'  => 'time window expired',
 '1.3.6.1.6.3.15.1.1.3.0'  => 'wrong username?',
 '1.3.6.1.6.3.15.1.1.4.0'  => 'wrong engine-id?',
 '1.3.6.1.6.3.15.1.1.5.0'  => 'wrong password?',
 '1.3.6.1.6.3.15.1.1.6.0'  => 'wrong privacy password?',
 );

my %CRYPTO = (
    DES		=> { encrypt => \&des_encrypt,  decrypt => \&des_decrypt  },
    '3DES'	=> { encrypt => \&tdes_encrypt, decrypt => \&tdes_decrypt },
    AES		=> { encrypt => \&aes_encrypt,  decrypt => \&aes_decrypt  },
    AES128	=> { encrypt => \&aes_encrypt,  decrypt => \&aes_decrypt  },
    AES192	=> { encrypt => \&aes_encrypt,  decrypt => \&aes_decrypt  },
    AES256	=> { encrypt => \&aes_encrypt,  decrypt => \&aes_decrypt  },
   );

$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [qw(UDP Service MonEl BaseIO)],
    methods => {},
    html   => 'services',
    fields => {
      snmp::community => {
	  descr => 'SNMP (v1, v2c) community',
	  attrs => ['config', 'inherit'],
	  versn => '3.5',
      },
      snmp::oid => {
	  descr => 'SNMP OID to query',
	  attrs => ['config'],
      },

      # v3 params
      snmp::snmpversion => {
	  # normally this should be specified as Service UDP/SNMPv3
	  descr => 'snmp version, 1, 2c, or 3',
	  attrs => ['config', 'inherit'],
	  versn => '3.5',
      },
      snmp::snmpuser => {
	  descr => 'SNMPv3 username',
	  attrs => ['config', 'inherit'],
	  versn => '3.3',
      },
      snmp::snmppass => {
	  descr => 'SNMPv3 authentication password',
	  attrs => ['config', 'inherit'],
	  versn => '3.3',
      },
      snmp::snmpauth => {
	  descr => 'SNMPv3 authentication protocol',
	  attrs => ['config', 'inherit'],
	  vals  => ['MD5', 'SHA1', 'none'],
	  versn => '3.3',
      },
      snmp::snmppriv => {
	  descr => 'SNMPv3 privacy (aka encryption) protocol',
	  attrs => ['config', 'inherit'],
	  vals  => ['DES', '3DES', 'AES', 'AES128', 'AES192', 'AES256', 'none'],
	  versn => '3.3',
      },
      snmp::snmpprivpass => {
	  descr => 'SNMPv3 privacy password',
	  attrs => ['config', 'inherit'],
	  versn => '3.3',
      },
      snmp::contextname => {
	  descr => 'SNMPv3 context name',
	  attrs => ['config', 'inherit'],
	  versn => '3.3',
      },
      snmp::contextengine => {
	  descr => 'SNMPv3 context engine id',
	  attrs => ['config', 'inherit'],
	  versn => '3.3',
      },
      snmp::authengine => {
	  descr => 'SNMPv3 authentication engine id',
	  attrs => ['config', 'inherit'],
	  versn => '3.3',
      },

      snmp::engineboot => {
	  # RFC 3414  2.2.2
	  descr => 'SNMPv3 remote system snmpEngineBoots value',
      },
      snmp::enginetime => {
	  # RFC 3414  2.2.2
	  descr => 'SNMPv3 remote system snmpEngineTime value',
      },
      snmp::authkey => {
	  # RFC 3414 2.6, etal.
	  descr => 'SNMPv3 localized authentication key',
      },
      snmp::privkey => {
	  # RFC 3414 2.6, etal.
	  descr => 'SNMPv3 localized privacy key',
      },
      snmp::builttime => {
	  # we intentionally abuse the RFC 3414 2.2.3 Time Window
	  # by replaying messages during the allowed window
	  descr => 'time snmp request packet was built',
      },
      snmp::discovered => {
	  # if we auto-discovered engine-id, we permit re-discovery
	  # if engine-id is user-specified, we do not
	  descr => 'engine-id was auto-discovered',
      },

      snmp::bulk => {
	  descr => 'list of other objects associated with bulk request',
      },
      snmp::getoid  => {
	  descr => 'full numeric oid for get requests',
      },
      snmp::bulkoid => {
	  descr => 'full numeric oid for get-bulk-requests',
      },

      # for helper
      snmp::tabloid  => {},  # base oid '1.3.6.1.2.3'
      snmp::tablidx  => {},  # name of index
      snmp::idxsrc   => {},  # table for idx => name lookup
      snmp::helping  => {},  # being helped

    },
};

sub probe {
    my $name = shift;

    return ( $name =~ /^UDP\/SNMP/ ) ? [ 8, \&config ] : undef;
}

sub config {
    my $me = shift;
    my $cf = shift;

    bless $me;
    $me->init_from_config( $cf, $doc, 'snmp' );

    if( $me->{name} =~ /SNMP\w*\/(.*)/i ){
	$me->{snmp}{oid} ||= $1;
    }

    if( $me->{name} =~ /SNMPv?3/ ){
	$me->{snmp}{snmpversion} = 3;
    }
    if( $me->{name} =~ /SNMPv?2c/ ){
	$me->{snmp}{snmpversion} = '2c';
    }

    $me->{snmp}{snmpversion} ||= 1;

    if( $me->{snmp}{snmpversion} == 3 ){
	$me->{snmp}{snmpauth} ||= $me->{snmp}{snmppass}     ? 'MD5' : 'none';
	$me->{snmp}{snmppriv} ||= $me->{snmp}{snmpprivpass} ? 'DES' : 'none';
	$me->{snmp}{snmppriv} = 'none' if $me->{snmp}{snmpauth} eq 'none';

	if( $me->{snmp}{snmpauth} !~ /^(MD5|SHA1|none)$/ ){
	    $cf->warning("SNMPv3 unknown authentication protocol");
	    $me->{snmp}{snmpauth} = 'none';
	}

	if( $me->{snmp}{snmpauth} eq 'SHA1' && ! $HAVE_SHA1 ){
	    $me->{snmp}{snmpauth} = $HAVE_MD5 ? 'MD5' : 'none';
	    $cf->warning( "SNMPv3 SHA1 not available" );
	}

	if( $me->{snmp}{snmpauth} eq 'MD5' && ! $HAVE_MD5 ){
	    $cf->warning( "SNMPv3 MD5 not available" );
	    $me->{snmp}{snmpauth} = 'none';
	}

	if( $me->{snmp}{snmppriv} !~ /^(DES|3DES|AES(128|192|256)?|none)$/ ){
	    $cf->warning( "SNMPv3 unknown privacy protocol" );
	    $me->{snmp}{snmppriv} = 'none';
	}

	if( $me->{snmp}{snmppriv} eq 'DES' && ! $HAVE_DES ){
	    $cf->warning( "SNMPv3 DES not available" );
	    $me->{snmp}{snmppriv} = 'none';
	}
	if( $me->{snmp}{snmppriv} eq '3DES' && ! $HAVE_3DES ){
	    $cf->warning( "SNMPv3 3DES not available" );
	    $me->{snmp}{snmppriv} = 'none';
	}

	if( $me->{snmp}{snmppriv} =~ /^AES/ && ! $HAVE_AES ){
	    $cf->warning( "SNMPv3 AES not available" );
	    $me->{snmp}{snmppriv} = 'none';
	}

	if( $me->{snmp}{contextengine} =~ /^(0x)?[0-9a-f]+$/i ){
	    $me->{snmp}{contextengine} =~ s/^0x//i;
	    $me->{snmp}{contextengine} =~ s/(..)/chr(hex($1))/ge;
	}
	if( $me->{snmp}{authengine} =~ /^(0x)?[0-9a-f]+$/i ){
	    $me->{snmp}{authengine} =~ s/^0x//i;
	    $me->{snmp}{authengine} =~ s/(..)/chr(hex($1))/ge;
	}
    }


    # configure some defaults from OIDS->up, ...
    my($table) = $me->{snmp}{oid} =~ /^([^\d\.\[]+)/;
    if( my $o = $OIDS{$table} ){
	if( defined $o->{up} ){
	    $me->{test}{eqvalue} = $o->{up};
	}

	if( defined $o->{calc} ){
	    $me->{test}{calc} = $o->{calc};
	}
    }

    $me->{label_right_maybe} ||= $me->{snmp}{oid};
    $me->{udp}{port} ||= 161;
    $me->SUPER::config($cf);
    $me->{friendlyname} = "$me->{snmp}{oid} on $me->{ip}{hostname}";
    $me->snmp_oid_init($cf);

    $me;
}

sub snmp_oid_init {
    my $me = shift;
    my $cf = shift;
    my( $req, $oid );

    $oid = $me->{snmp}{oid};

    return $cf->error( "invalid OID ($oid)" )
	unless $oid;

    my($otable) = $oid =~ /^([^\d\.\[]+)/;
    $oid =~ s/^([^\d\.\[]+)/$OIDS{$1}{oid}||'UNKNOWN'/e;

    if( $oid =~ /^[\d\.]+$/ ){
	$me->{snmp}{getoid} = $oid;
	$me->snmp_oid_bulk_init($oid);
	# for compat, use numeric oid
	$me->{uname} = "SNMP_$me->{snmp}{getoid}_$me->{ip}{hostname}";
    }
    elsif( $oid =~ /^([\d\.]+)\[(.*)\]/ ){
	# 1.3.6.1.2[Serial1/0]
	my($table, $idx) = ($1, $2);
	$idx =~ s/^\s*//;
	$idx =~ s/\s*$//;

	my $idxsrc = $OIDS{$otable}{idx};
	$idxsrc = 'if' unless defined $idxsrc;

	$me->{snmp}{tabloid} = $table;
	$me->{snmp}{idxname} = $idx;
	$me->{snmp}{idxsrc}  = $idxsrc;
	$me->{uname} = "SNMP_$table\_$idx\_$me->{ip}{hostname}";

	$me->helper_init($cf);
    }else{
	return $cf->error( "invalid OID ($me->{snmp}{oid})" );
    }

    $me;
}

sub snmp_oid_bulk_init {
    my $me  = shift;
    my $oid = shift;

    # bulk get returns value of oid after the one specified
    my @o = split /\./, $oid;
    if( $o[-1] == 0 ){
	pop @o;
    }else{
	$o[-1]--;
    }
    $me->{snmp}{bulkoid} = join('.', @o);

    $me;
}

sub DESTROY {
    my $me = shift;

    $me->helper_not_needed() if $me->{snmp}{helping};
}

sub start {
    my $me = shift;
    my @more;

    $me->Service::start();

    $me->{ip}{addr}->refresh($me);

    if( $me->{ip}{addr}->is_timed_out() ){
        return $me->isdown( "cannot resolve hostname" );
    }

    unless( $me->{ip}{addr}->is_valid() ){
        $me->debug( 'Test skipped - resolv still pending' );
        # prevent retrydelay from kicking in
        $me->{srvc}{tries} = 0;
        return $me->done();
    }

    if( $me->{snmp}{bulk} ){
	::sysproblem( 'BUG ALERT - SNMP bulk fetch did not finish processing' );
    }

    if( $me->{snmp}{helping} ){
	# continue, skip test, or down (host|oid) not found
	my $oid = eval {
	    $me->helper_check_oid();
	};
	if(my $e = $@){
	    $me->isdown( $e, 'not found' );
	    return;
	}
	unless( $oid ){
	    # still pending. skip check.
	    $me->debug('oid discovery still pending. skipping check.');
	    return $me->done();
	}
    }

    $me->{snmp}{running} = 1;

    # search for others that we can get at the same time
    my $n = 1;
    if( $me->{snmp}{snmpversion} != 1 && $me->{snmp}{bulkoid} ){
	foreach my $t (@BaseIO::bytime){
	    last if $t->{time} > $^T + $me->{srvc}{frequency};
	    last if $n >= $MULTI_MAX;
	    foreach my $x ( @{$t->{elem}} ){
		last if $n >= $MULTI_MAX;
		next unless $x;
		my $o = $x->{obj};
		next unless defined $o->{snmp};
                my $os = $o->{snmp};
		next if $o->{srvc}{disabled};
		next unless $os->{getoid};
		next unless $os->{bulkoid};
                next if $os->{running};	# XXX - how?
		next if $o->{srvc}{nexttesttime} - $o->{srvc}{frequency} / 4 > $^T;
                next unless $o->monitored_here();
                next unless $o->monitored_now();
                my $opa = $o->{ip}{addr};
                $opa->refresh($o);
                next unless $opa->is_valid();
		next unless $me->merge_compat($o);

		if( $o->{snmp}{helping} ){
		    # NB: if we got this far, we already know the oid.
		    # we want to make sure it gets updated on change
		    eval { $o->helper_check_oid() };
		    next if $@; # no longer a valid interface
		}

		$x = undef;
		$o->{srvc}{delaynext} = 1; # it ran early, do not run again at normal time.
                $os->{running} = 1;
		push @more, $o;
		$n ++;
	    }
	}
    }

    if( $me->{snmp}{snmpversion} == 3 &&
	# RFC 3414 2.2.3
	($me->{snmp}{snmpauth} ne 'none') &&
	($^T - $me->{snmp}{builttime}) >= $SNMP3_TIME_WINDOW - 10){

	$me->{snmp}{enginetime} += $^T - $me->{snmp}{builttime};
	$me->build_req();
    }

    if(@more){
	$me->debug( 'SNMP taking others on a multi-get-request' );
	$me->{snmp}{bulk} = \@more;

	# get uniqed list of oids
	my %oid = map {($_->{snmp}{getoid} => 1)} ($me, @more);
	my @oid = keys %oid;

	$me->build_req( 'multi', @oid );
	foreach my $o (@more){
	    $o->debug( 'SNMP joining in with multi-get-request' );
	    $o->Service::start();
	}
    }

    $me->build_req() unless $me->{udp}{send};

    $me->open_socket();
    $me->connect_and_send();
}

# can we merge these 2 into a bulk get?
sub merge_compat {
    my $me = shift;
    my $he = shift;

    foreach my $k (qw(community snmpversion snmpuser snmppass snmpauth snmppriv)){
	return unless $me->{snmp}{$k} eq $he->{snmp}{$k};
    }

    return unless $me->{ip}{addr}->is_same( $he->{ip}{addr} );
    return unless $me->{udp}{port} == $he->{udp}{port};

    1;
}

sub build_req {
    my $me   = shift;
    my $type = shift;
    my @more = @_;
    my( $req );

    $me->debug('snmp build req');
    $me->{snmp}{builttime} = $^T;
    my $snmppdu;
    my $ber = Encoding::BER::SNMP->new(debug => $BER_DEBUG);

    if( $type eq 'pdu' ){
	# use supplied pdu
	$snmppdu = $more[0];

    }elsif( $type eq 'bulk' ){
	# use a get-bulk request
	my @oid = map { [ { type => 'oid', value => $_ }, undef ] } @more;
	$snmppdu = { type  => 'get_bulk_request',
		     value => [ { type => 'integer', value => $snmpid++ },
				{ type => 'integer', value => scalar(@oid) },
				0,
				[ @oid ] ] };

    }elsif( $type eq 'multi' ){
	# use get-request with multiple oids
	my @oid = map { [ { type => 'oid', value => $_ }, undef ] } @more;
	$snmppdu = { type  => 'get_request',
		     value => [ { type => 'integer', value => $snmpid++ },
				0,
				0,
				[ @oid ] ] };
    }else{
	$snmppdu = { type  => 'get_request',
		     value => [ { type => 'integer', value => $snmpid++ },
				0,
				0,
				[ [ { type => 'oid', value => $me->{snmp}{getoid} }, undef ] ] ] };
    }

    if( $me->{snmp}{snmpversion} == 1 ){
	# Why lifts she up her arms in sequence thus?
	#   -- Shakespeare, Titus Andronicus
	# SNMP v1 packet
	$req = $ber->encode( [ 0, # 0 = snmpv1
			       { type => 'string', value => $me->{snmp}{community} },
			       $snmppdu ]);

    }elsif( $me->{snmp}{snmpversion} eq '2c' ){
	# only the version number is different
	$req = $ber->encode( [ 1, # 1 = snmpv2c
			       { type => 'string', value => $me->{snmp}{community} },
			       $snmppdu ]);

    }else{
	# SNMP v3 packet - has a "slightly" different format from v1
	my( $flags, $secparams, $auth, $priv, $scopedpdu );

	$scopedpdu = { type  => 'sequence',
		       value => [ { type => 'string', value => $me->{snmp}{contextengine} },
				  { type => 'string', value => $me->{snmp}{contextname}   },
				  $snmppdu ] };

	if( $me->{snmp}{snmpauth} eq 'none' || !$me->{snmp}{authengine} ){
	    $flags = "\4";     # noAuth, noPriv, Report
	    $auth = $priv = '';
	}else{
	    $auth = "\0" x 12;
	    if( $me->{snmp}{snmppriv} eq 'none' ){
		$flags = "\5"; # Auth, noPriv, Report
		$priv = '';
	    }else{
		$flags = "\7"; # Auth, Priv, Report
		$priv = pack('C*', map{ rand(0xFF) } (1..8) );
	    }
	}

	$secparams = [ { type => 'string', value => $me->{snmp}{authengine} },
		       { type => 'int',    value => ($me->{snmp}{engineboot} || 0) },
		       { type => 'int',    value => ($me->{snmp}{enginetime} || 0) },
		       { type => 'string', value => $me->{snmp}{snmpuser} },
		       { type => 'string', value => $auth },
		       { type => 'string', value => $priv } ];

	if( $priv ){
	    # priv => encrypt scoped pdu
	    unless( $me->{snmp}{privkey} ){
		$me->{snmp}{privkey} = $me->localized_key( $me->{snmp}{snmpprivpass} );
	    }
	    my $encpdu = $me->encrypt( $priv, $ber->encode($scopedpdu) );
	    $scopedpdu = { type => 'string', value => $encpdu };
	}

	my $reqd = [ 3, # 3 = snmpv3
		     [ # msg global header
		       { type => 'int',    value => $snmpid++ },
		       { type => 'int',    value => 1234 },       # PTOOMA
		       { type => 'string', value => $flags },
		       3 ], # 3 = USM
		     { type => 'string', value => $ber->encode($secparams) },
		     $scopedpdu  ];

	$req = $ber->encode($reqd);

	if( $auth ){
	    # calculate auth, and insert it back in
	    $auth = $me->calc_auth( $req );

	    my $offset = length($req)
		- $scopedpdu->{tlen}
	        - $secparams->[5]{tlen}
	        - $secparams->[4]{dlen};

	    $me->debug("snmpv3 auth offset: $offset");

	    substr( $req, $offset, length($auth) ) = $auth;
	}

    }

    $me->{udp}{send} = $req;
    $me;
}

# RFC 3414 A.2
# the RFC poorly specifies the algorithm; actually it doesn't specify the algorithm,
# it only provides a snippet of sample code
sub localized_key {
    my $me = shift;
    my $pass = shift;

    my $mac;
    if( $me->{snmp}{snmpauth} eq 'MD5' ){
	$mac = Digest::MD5->new;
    }elsif( $me->{snmp}{snmpauth} eq 'SHA1' ){
	$mac = Digest::SHA1->new();
    }else{
	return;
    }

    my( $pp, $i, $m, $d );
    $m = length($pass);
    $pp = $pass x (2 + 1024/$m);

    for( $i=0; $i<1024*1024; $i+=1024 ){
	$mac->add( substr($pp, $i % $m, 1024) );
    }

    $d = $mac->digest();

    $mac->add($d . $me->{snmp}{authengine} . $d)->digest();
}

sub calc_auth {
    my $me  = shift;
    my $req = shift;
    my( $hmac, $auth );

    unless( $me->{snmp}{authkey} ){
	$me->{snmp}{authkey} = $me->localized_key( $me->{snmp}{snmppass} );
    }

    if( $me->{snmp}{snmpauth} eq 'MD5' ){
	$hmac = Digest::HMAC->new($me->{snmp}{authkey}, 'Digest::MD5');
    }
    if( $me->{snmp}{snmpauth} eq 'SHA1' ){
        $hmac = Digest::HMAC->new($me->{snmp}{authkey}, 'Digest::SHA1');
    }

    $hmac->add($req);
    $auth = substr($hmac->digest(), 0, 12);
    $auth;
}

################################################################

sub encrypt {
    my $me   = shift;
    my $salt = shift;
    my $pdu  = shift;

    return $CRYPTO{ $me->{snmp}{snmppriv} }{encrypt}->( $me, $me->{snmp}{snmppriv}, $salt, $pdu );
}

sub decrypt {
    my $me   = shift;
    my $salt = shift;
    my $pdu  = shift;

    return $CRYPTO{ $me->{snmp}{snmppriv} }{decrypt}->( $me, $me->{snmp}{snmppriv}, $salt, $pdu );
}

# RSN - AES - RFC 3826

sub des_encrypt {
    my $me   = shift;
    my $algo = shift;
    my $salt = shift;
    my $pdu  = shift;

    # RFC 3414 8.1.1.2
    my $pk  = $me->{snmp}{privkey};
    my $piv = substr( $pk, 8, 8 );
    my $iv  = $piv ^ $salt;

    my $pad = 8 - length($pdu) % 8;
    $pdu .= chr($pad) x $pad;

    my $c = Crypt::DES->new( substr($pk,0,8) );

    # cbc
    my $d;
    while( $pdu ){
	my $x =  substr($pdu, 0, 8, '');
	$iv = $c->encrypt( $x ^ $iv );
	$d .= $iv;
    }

    $d;
}

sub des_decrypt {
    my $me   = shift;
    my $algo = shift;
    my $salt = shift;
    my $pdu  = shift;

    my $pk  = $me->{snmp}{privkey};
    my $piv = substr( $pk, 8, 8 );
    my $iv  = $piv ^ $salt;

    my $c = Crypt::DES->new( substr($pk,0,8) );

    # cbc
    my $d;
    while( $pdu ){
	my $x =  substr($pdu, 0, 8, '');
	$d .= $c->decrypt( $x ) ^ $iv;
	$iv = $x;
    }

    $d;
}

################################################################

sub decode_results {
    my $me  = shift;
    my $pdu = shift;

    $pdu->destruct_bind(my $resm = {},
		    [ 'reqid', 'errorstat', 'erroridx', 'varbind' ]);

    my $ress = $resm->{varbind};
    unless($ress){
	$me->debug("no varbindlist found");
	return;
    }

    my @r;
    foreach my $r ( @$ress ){
	next unless ref $r->{value};

	my $oid = $r->{value}[0]{value};
	my $val = $r->{value}[1];

	# RFC 1905
	if( $val->{identval} == 0x80 ){
	    $val = '#<noSuchObject>';
	}elsif( $val->{identval} == 0x81 ){
	    $val = '#<noSuchInstance>';
	}elsif( $val->{identval} == 0x82 ){
	    $val = '#<endOfMibView>';
	}else{
	    $val = $val->{value};
	}

	$me->debug("SNMP result found: $oid => $val");
	push @r, { oid => $oid, val => $val };
    }

    { errst => $resm->{errorstat},
      res   => \@r,
  };
}

sub readable {
    my $me = shift;
    my( $fh, $i, $l, $results );

    $fh = $me->{fd};
    $i = recv($fh, $l, 8192, 0);
    return $me->m_isdown( "SNMP recv failed: $!", 'recv failed' )
	unless defined($i);

    return if $me->check_response($i);

    $me->debug( "SNMP recv data" );
    $me->{udp}{rbuffer} = $l;		# for debugging
    delete $me->{udp}{send} if $me->{snmp}{bulk};

    my $ber = Encoding::BER::SNMP->new( debug => $BER_DEBUG,
					error => sub { die "$_[0]\n" },
					decoded_callback => sub { bless $_[1], 'Argus::BER::Result' },
					);
    my $dat;
    eval {
	$dat = $ber->decode( $l );
    };
    return $me->m_isdown( "SNMP decode failed: $@", 'recv failed' ) if $@;

    if( $me->{snmp}{snmpversion} == 1 || $me->{snmp}{snmpversion} eq '2c' ){
	$dat->destruct_bind(my $resm = {}, [ 'version', 'community', \ 'snmppdu' ]);
	$results = $me->decode_results( $resm->{snmppdu} );

    }else{
	# v3
	my $discov;

	my @more = $me;
	push @more, @{$me->{snmp}{bulk}} if $me->{snmp}{bulk};

	# disassemble
	my $snmp = ['version', [ 'msgid', 'maxsize', 'flags', 'secmodel'], 'secparams', \ 'scopedpdu' ];
	my $resv = {};
	$dat->destruct_bind($resv, $snmp);

	my $secparam = $resv->{secparams};
	return $me->m_isdown("SNMP response corrupt.", 'BER error') unless $secparam;

	# sec params is BER embedded in a string...
	$secparam = $ber->decode($secparam);
	return $me->m_isdown("SNMP response corrupt.", 'BER error') unless $secparam;
	my $usmsec = ['aeng', 'eboot', 'etime', 'name', 'authpm', 'privpm' ];
	$secparam->destruct_bind($resv, $usmsec);

	# auto-discover engine-id
	if( $resv->{aeng} ){
	    foreach my $o (@more){
		next if $o->{snmp}{authengine};
		$o->{snmp}{authengine}    ||= $resv->{aeng};
		$o->{snmp}{contextengine} ||= $resv->{aeng};
		# also try to auto-discover boots+time
		# but not all systems will send these
		# in an invalid-engine-id report
		$o->{snmp}{engineboot} = $resv->{eboot};
		$o->{snmp}{enginetime} = $resv->{etime};
		$o->{snmp}{discovered} = 1;
		delete $o->{udp}{send};
		$discov = 1;
		$o->debug( "SNMPv3 auto-discovered engine-id" );
	    }
	}

	# scopedpdu might be encrypted, decrypt
	my $scopedpdu;
	if( $resv->{privpm} ){
	    my $d = $me->decrypt( $resv->{privpm}, $resv->{scopedpdu}{value} );
	    eval {
		$scopedpdu = $ber->decode($d);
	    };
	    return $me->m_isdown( "SNMPv3 decryption failed: $@", 'decrypt failed' ) if $@;

	}else{
	    $scopedpdu = $resv->{scopedpdu};
	}
	return $me->m_isdown("SNMP response corrupt.", 'BER error') unless $scopedpdu;

	# pull out snmppdu
	my $snmppdu = $scopedpdu->{value}[2];
	my $pdutype = $snmppdu->{identval};

	if( $pdutype == 162 ){
	    # get-response
	    $results = $me->decode_results( $snmppdu );

	}elsif( $pdutype == 168 ){
	    # report
	    # if we auto-discovered engine-ids
	    # start over with new engine id
	    if( $discov ){
                return $me->m_done();
	    }

	    my $report = $me->decode_results( $snmppdu );
	    my %repoid = map { ($_->{oid} => 1) } @{$report->{res}};

	    if( $repoid{'1.3.6.1.6.3.15.1.1.2.0'} ){
		 # need to update boot/time
		 foreach my $o (@more){
		     $o->{snmp}{engineboot} = $resv->{eboot};
		     $o->{snmp}{enginetime} = $resv->{etime};

		     $o->debug( "SNMPv3 updating boots/time" );
		     delete $o->{udp}{send};
		 }
                 return $me->m_done();
	    }

	    if( $repoid{'1.3.6.1.6.3.15.1.1.4.0'} ){
		# if we previously auto-discovered the engine-id,
		# re-auto-discover it.
		# NB: ucd choses a new engine id when it restarts
		foreach my $o (@more){
		    if( $o->{snmp}{discovered} ){
			$o->{snmp}{authengine}    = $resv->{aeng};
			$o->{snmp}{contextengine} = $resv->{aeng};
			$o->{snmp}{engineboot}    = $resv->{eboot};
			$o->{snmp}{enginetime}    = $resv->{etime};
			delete $o->{snmp}{authkey};
			delete $o->{snmp}{privkey};
		    }
		    # make noise
		    $o->loggit( tag => 'SNMPv3',
				msg => "remote system changed engine-id.",
				objlog => 1,
				);
		    delete $o->{udp}{send};
		}
                return $me->m_done();
	    }

	    my $oid1;
	    for my $oid (keys %repoid){
		$oid1 = $oid;
		if( $v3errs{$oid} ){
		    return $me->m_isdown( "SNMPv3 error report. $v3errs{$oid}", 'SNMP error' );
		}
	    }

	    return $me->m_isdown( "SNMPv3 report. possibly misconfigured? ($oid1)", 'SNMP error' );
	}else{
	    return $me->m_isdown( "SNMPv3 unknown reply type ($pdutype)", 'SNMP error' );
	}
    }

    return $me->m_isdown("SNMP response corrupt.", 'BER error') unless $results;

    if( $results->{errst} ){
	# 1 bad oid in a bulk query, not an error
	unless( @{$results->{res}} && $results->{errst} == 2){
	    return $me->m_isdown( "SNMP error - " . $errstat{$results->{errst}} || $results->{errst}, 'SNMP error' );
	}
    }

    $me->process_results( $results );

}

sub process_results {
    my $me = shift;
    my $results = shift;

    if( $me->{snmp}{bulk} ){
	my %val;
	foreach my $r (@{$results->{res}}){
	    my $oid = $r->{oid};
	    $oid =~ s/^\.//;
	    $val{$oid} = $r->{val};
	}

        my @all = ($me, @{$me->{snmp}{bulk}});
	delete $me->{snmp}{bulk};

	foreach my $o (@all){
	    my $oid = $o->{snmp}{getoid};
	    $oid =~ s/^\.//;
	    $o->debug( 'SNMP fetching result from bulk-response' );
	    my $val = $val{$oid};

	    unless( defined $val && $val !~ /\#<.*>/ ){
		$o->debug('SNMP response not found. disabling bulk-get');
		delete $o->{snmp}{bulkoid};
		$o->done();
		next;
	    }
	    $o->check_and_test_result($val);
	}
    }else{
	my $value = $results->{res}[0]{val};
	$me->check_and_test_result($value);
    }
}

sub done {
    my $me = shift;

    $me->m_done(@_);
}

sub m_done {
    my $me = shift;

    if( $me->{snmp}{bulk} ){
	foreach my $o (@{$me->{snmp}{bulk}}){
            delete $o->{snmp}{running};
	    $o->SUPER::done(@_);
	}
    }
    delete $me->{snmp}{running};
    delete $me->{snmp}{bulk};
    $me->SUPER::done(@_);
}

sub isdown {
    my $me = shift;
    $me->m_isdown(@_);
}

sub m_isdown {
    my $me = shift;

    if( $me->{snmp}{bulk} ){
	foreach my $o (@{$me->{snmp}{bulk}}){
	    $o->SUPER::isdown(@_);
	}
    }
    delete $me->{snmp}{bulk};
    $me->SUPER::isdown(@_);
}

sub timeout {
    my $me = shift;

    if( $me->{snmp}{bulk} ){
	foreach my $o (@{$me->{snmp}{bulk}}){
	    $o->SUPER::timeout(@_);
	}
    }
    delete $me->{snmp}{bulk};
    $me->SUPER::timeout(@_);
}

sub check_and_test_result {
    my $me  = shift;
    my $val = shift;

    if( $val =~ /^\#<(.*)>/ ){
	return $me->isdown( "BER error: $1 (no such OID?)", 'OID error' );
    }

    $me->debug( "SNMP recv - raw value $val" );
    $me->generic_test($val, 'SNMP');
}

sub webpage_more {
    my $me = shift;
    my $fh = shift;
    my( $k, $v );

    $me->SUPER::webpage_more($fh);

    foreach $k (qw(oid contextname)){
	$v = $me->{snmp}{$k};
	print $fh "<TR><TD>SNMP $k</TD><TD>$v</TD></TR>\n" if defined($v);
    }
}

sub about_more {
    my $me = shift;
    my $ctl = shift;
    my( $k, $v );

    $me->SUPER::about_more($ctl);
    $me->more_about_whom($ctl, 'snmp');
    $me->more_about_whom($ctl, 'snmph');
}

################################################################
# fetch specified items from decoded BER results
# and put into simple to access hash
sub Argus::BER::Result::destruct_bind {
    my $me  = shift;
    my $res = shift;
    my $tpl = shift;

    unless( ref $tpl ){
	$res->{$tpl} = $me;
	return $res;
    }
    unless( ref $me->{value} ){
	return $res;
    }

    my @v = @{$me->{value}};
    for my $t (@$tpl){
	my $v = shift @v;
	if( ref $t eq 'ARRAY' ){
	    $v->destruct_bind($res, $t);
	}elsif(ref $t){
	    $res->{$$t} = $v;
	}elsif(defined $t){
	    $res->{$t} = $v->{value};
	}else{
	    # skip
	}
    }
    $res;
}

################################################################
# read-config callback
# load MIB2SCHEMA format file of name to oid translations
sub load_mibfile {
    my $file = shift;
    my $cf   = shift;

    for my $f (split /\s+/, $file){
	unless( open(MIB, $f) ){
	    ::warning("cannot open mibfile '$file': $!");
	    next;
	}

	while(<MIB>){
	    chop;
	    s/\"//g;
	    my($name, $oid, $idx) = split /\s+/, $_, 3;
            next unless $name;
            return $cf->error( "invalid OID ($oid)" ) unless $oid =~ /^[0-9\.]+$/;

            add_mib_def( $cf, $name, {
                oid	=> $oid,
                idx	=> $idx,
            });
	}
	close MIB;
    }
}

sub add_mib_def {
    my $cf   = shift;
    my $name = shift;
    my $p    = shift;

    my $d = $OIDS{$name} = { _name => $name, oid => $p->{oid}, _usercf => 1 };
    $d->{up}    = $p->{upvalue} if defined $p->{upvalue};
    $d->{calc}  = $p->{calc}    if defined $p->{calc};

    if( my $w = $p->{watch} ){
        $w = $OIDS{$w}{oid} || $w;
        $w =~ s/^\.//;	# remove leading .
        return $cf->error( "invalid OID ($w)" ) unless $w =~ /^[0-9\.]+$/;
        $d->{watch} = $w;
    }

    # print STDERR "add $name => '$p->{oid}'\n";
    if( $p->{idx} ){
        my @idx = split /\s+/, $p->{idx};

        # translate names => oids
        for my $o (@idx){
            $o = $OIDS{$o}{oid} || $o;
            $o =~ s/^\.//;	# remove leading .
            next if $o =~ /^[0-9\.]+$/;

            return $cf->error( "invalid OID ($o)" );
        }

        # a convenient name
        my $idxname = join('+', sort @idx) . ($d->{watch} ? ";$d->{watch}" : '');
        $idxname = Digest::MD5::md5_hex($idxname) if defined &Digest::MD5::md5_hex;

        Argus::SNMP::Helper::addidx( $idxname, \@idx, $d->{watch} );
        $OIDS{$name}{idx} = $idxname;
        $OIDS{$name}{_idx} = $p->{idx};
    }
}

sub get_user_conf {

    return map{
        $_->{idx} = $_->{_idx} if $_->{_idx};
        $_;
    } grep { $_->{_usercf} } values %OIDS;
}
sub get_oid_conf {
    my $name = shift;

    my $o = $OIDS{$name};
    $o->{idx} = $o->{_idx} if $o->{_idx};

    return $o;
}

################################################################

Doc::register( $doc );
push @Service::probes, \&probe;

1;

# NOTE: ucd replies with error = 'NO ERROR', value = 'NOSUCHINSTANCE' for invalid oid

