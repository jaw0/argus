# -*- perl -*-

# Copyright (c) 2007 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2007-Jun-24 17:04 (EDT)
# Function: look up interface names, to permit easier config
#
# $Id: Argus::SNMP::Helper.pm,v 1.18 2012/10/06 21:01:19 jaw Exp $

# let the config file say:
#   oid: ifOperStatus[Serial1/0]

package Argus::SNMP::Helper;
@ISA = qw(Argus::SNMP);

use strict qw(refs vars);
use vars qw(@ISA $doc);

my $MULTI_MAX = 32;
my $FREQUENCY = 30;
my $TIMEOUT   = 15;

my $OID_UPTIME   = '1.3.6.1.2.1.1.3.0';
my $OID_IFNUMBER = '1.3.6.1.2.1.2.1.0';
my $OID_IFDESCR  = '1.3.6.1.2.1.2.2.1.2';
my $OID_IFNAME   = '1.3.6.1.2.1.31.1.1.1.1';
my $OID_IFALIAS  = '1.3.6.1.2.1.31.1.1.1.18';
my $OID_DSKPATH  = '1.3.6.1.4.1.2021.9.1.2';	# by path
my $OID_DSKDEVS  = '1.3.6.1.4.1.2021.9.1.3';	# by device

# keep track of where helpers are enabled
my %host; # {host port src}{ service, hostname, idxsrc, descr, nservices }


my %SRC =
(
 # RFC 1213 required contiguous ifIndexes
 # RFC 1573 removed the requirement.
 # under 1213, we can get the table via snmpv1 multi-oid-get [1 - ifNumber]
 # under 1573, we need to either use snmp2c's bulk-get, or snmpv1's get-next-1-at-a-time
 # most v1 devices support 2c's get-bulk - try that first
 # if it fails, it is probably old and 1213 compliant, so fall back to that.
 if_v1	=> { start => \&multi_start, oid => [$OID_IFDESCR, $OID_IFNAME], ver => 1, number => $OID_IFNUMBER },
 if	=> { start => \&bulk_start,  oid => [$OID_IFDESCR, $OID_IFNAME], ver => '2c', fallback => 'if_v1' },
 ucddsk => { start => \&bulk_start,  oid => [$OID_DSKPATH, $OID_DSKDEVS], ver => '2c' },
);

$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [qw(Argus::SNMP)],
    methods => {},
    html   => 'services',
    fields => {

      snmph::phase      => {},	# 0|1
      snmph::idxsrc     => {},  # if|ucddsk
      snmph::idxfetch   => {},  # number fecthed so far
      snmph::idxnumber  => {},  # number of entries
      snmph::descr      => {},  # descr table data
      snmph::rdescr     => {},  # ditto. reversed
      snmph::lastuptime => {},  # most recent uptime

    },
};

sub addidx {
    my $name = shift;
    my $oids = shift;
    my $watch = shift;

    $SRC{$name} = { start => \&bulk_start, oid => $oids, ver => '2c', number => $watch };
}


sub probe {
    my $name = shift;

    return ( $name =~ /^_SNMP_HELPER/ ) ? [ 12, \&config ] : undef;
}

sub config {
    my $me = shift;
    my $cf = shift;

    $me->SUPER::config($cf);

    bless $me;
}

sub start {
    my $me = shift;

    my $hst = $me->{ip}{hostname};
    my $src = $me->{snmph}{idxsrc};

    $me->{snmph}{phase} ||= 0;
    $me->debug("snmp helper start: phase $me->{snmph}{phase}");

    if( $me->{snmph}{phase} == 0 ){
	# check uptime
	if( $SRC{$src}{number} ){
	    $me->build_req( 'multi', $OID_UPTIME, $SRC{$src}{number} );
	}else{
	    $me->build_req( 'multi', $OID_UPTIME );
	}
    }else{
	$SRC{$src}->{start}->( $me );
    }

    $me->{udp}{rbuffer} = undef;
    $me->UDP::start();
}

sub multi_start {
    my $me = shift;

    # get chunk of ifdescr table
    # RSN - avoid looping if error + idxfetch unchanged
    my @oid;
    my $src  = $me->{snmph}{idxsrc};
    my $base = $SRC{$src}{oid}[0];

    $me->debug("snmp helper multi start: from oid: $base." . ($me->{snmph}{idxfetch}+1));
    for my $i (1 .. $MULTI_MAX){
	my $ii = $me->{snmph}{idxfetch} + $i;
	last if $ii > $me->{snmph}{idxnumber};
	push @oid, "$base.$ii";
    }

    $me->build_req( 'multi', @oid );
}

sub bulk_start {
    my $me = shift;

    my $src = $me->{snmph}{idxsrc};
    my $oid = $SRC{$src}{oid}[ $me->{snmph}{phase} - 1 ];

    if( $me->{snmph}{idxfetch} ){
	$oid .= '.' . $me->{snmph}{idxfetch};
    }

    $me->debug("snmp helper bulk start: from oid: $oid");

    my $pdu = { type  => 'get_bulk_request',
		value => [ { type => 'integer', value => 1234 },
		          0, $MULTI_MAX,
		          [ [ { type => 'oid', value => $oid }, undef ] ] ] };

    $me->build_req('pdu', $pdu);
}


sub reschedule {
    my $me = shift;

    # cause table chunks to be fetched rapidly
    if( $me->{snmph}{phase} ){
	$me->{srvc}{tries} = 1;
	$me->{srvc}{retrydelay} = 1;
    }else{
	$me->{srvc}{retrydelay} = 15; # XXX config?
    }

    $me->SUPER::reschedule();
}

# error? retry or back to square one
sub isdown {
    my $me = shift;

    # if we got a response, but in error, and we have a fallback, fall back
    # to work around rfc-1573 discontiguous ifindex issue
    # XXX - should only fallback if error is due to 2c not supported
    if( $me->{udp}{rbuffer} ){
	my $src = $me->{snmph}{idxsrc};
	$src = $SRC{$src}{fallback};
	if( $src ){
	    $me->debug("fetch of table failed, retrying using $src");
	    $me->{snmph}{idxsrc}     = $src;
	    $me->{snmp}{snmpversion} = $SRC{$src}{ver} || 1;
	}
    }

    if( $me->{srvc}{tries} > $me->{srvc}{retries} ){
	# start over
	if( $me->{snmph}{phase} ){
	    $me->{snmph}{phase} = 0;
	    $me->next_phase();
	}
    }

    $me->SUPER::isdown(@_);
}

sub next_phase {
    my $me = shift;

    my $src = $me->{snmph}{idxsrc};

    unless( $me->{snmph}{phase} ){
	delete $me->{snmph}{descr};
	delete $me->{snmph}{rdescr};
    }

    delete $me->{snmph}{idxfetch};
    $me->{snmph}{phase} ++;

    if( $me->{snmph}{phase} - 1 >= @{$SRC{$src}{oid}} ){
	$me->{snmph}{phase} = 0;
    }

    $me->debug("next phase: $me->{snmph}{phase}");
}

sub process_results {
    my $me = shift;
    my $results = shift;
    my $gotend;
    my $gotupt;
    my $gotextra;

    my $src   = $me->{snmph}{idxsrc};
    my $ctabl = $me->{snmph}{phase} ? $SRC{$src}{oid}[ $me->{snmph}{phase} - 1 ] : undef;
    my $ngot;

    $me->debug("snmp helper process results, ph $me->{snmph}{phase}, ctabl '$ctabl'");
    foreach my $r (@{$results->{res}}){
	my $oid = $r->{oid};
	my $val = $r->{val};
	$oid =~ s/^\.//;
	my( $table, $idx ) = $oid =~ /(.*)\.(\d+)$/;

	if($val =~ /\#</ ){
	    # an error value. we are done.
	    $gotend = "value=$val";
	    next;
	}

        $me->debug("hpr got $oid $val");
	if( $oid eq $OID_UPTIME ){
            $me->debug("hpr got uptime last=$me->{snmph}{lastuptime}");

	    # initial query
	    if( ! $me->{snmph}{lastuptime} ){
		$me->next_phase();
		$me->debug("system startup detected. fetching table");
	    }

	    # device rebooted?
	    elsif( $me->{snmph}{lastuptime} > $val ){
		$me->next_phase();
		$me->debug("system reset detected. refetching table");
	    }

	    $me->{snmph}{lastuptime} = $val;
	    $gotupt = 1;
	}

	elsif( $SRC{$src} && ($oid eq $SRC{$src}{number}) ){

	    if( $me->{snmph}{idxnumber} ne $val && !$me->{snmph}{phase} ){
		$me->next_phase();
		$me->debug("system reconfig detected. refetching table");
	    }

	    $me->{snmph}{idxnumber} = $val;
	}

	elsif( $table eq $ctabl ){
	    $ngot ++;
	    $me->{snmph}{descr}[$idx]  = $val;
	    $me->{snmph}{rdescr}{$val} = $idx;
	    $me->debug("got $val => $idx");
	    $me->{snmph}{idxfetch} = $idx if $idx > $me->{snmph}{idxfetch};
	}

	else{
	    $me->debug("got extra $oid => $val");
	    $gotextra = 1;
	    $gotend ||= "past the end";
	}
    }

    if( $gotend || $me->{snmph}{idxnumber} && ($me->{snmph}{idxfetch} >= $me->{snmph}{idxnumber}) ){
	# got entire table
	$gotend ||= "idxfetch >= idxnumber ($me->{snmph}{idxnumber})";

	$me->next_phase();

	if( ! $me->{snmph}{phase} ){
	    # finished.
            my $key = _hostkey($me);
            $host{$key}{descr} = $me->{snmph}{rdescr};
	    $me->debug("all results fetched. finished ($gotend)");
	}
    }

    return $me->isup() if $ngot || $gotupt;

    if( $gotend && !$me->{snmph}{idxfetch} ){
	return $me->isdown("unexpected responses");
    }

    $me->isup();
}


################################################################

sub _hostkey {
    my $me = shift;

    my $src = $me->{snmph} ? $me->{snmph}{idxsrc} : $me->{snmp}{idxsrc};
    return "$me->{ip}{hostname} $me->{udp}{port} $src";
}

sub helper_init {
    my $me = shift;
    my $cf = shift;

    # mark it
    $me->{snmp}{helping} = 1;

    # record details + create helper
    my $host = $me->{ip}{hostname};
    my $port = $me->{udp}{port};
    my $src  = $me->{snmp}{idxsrc};
    my $comm = $me->{snmp}{community};

    return $cf->error("do not know how to convert $src [$me->{snmp}{idxname}] for table $me->{snmp}{tabloid}")
	unless $SRC{$src};

    # is a helper already enabled for this?
    my $key = _hostkey($me);

    if( $host{$key} ){
	$host{$key}{service}{debug} = 1 if $me->{config}{debug};
	$host{$key}{nservices} ++;
	return;
    }

    # RSN - is $me monitored on this server?

    my $ver = $me->{snmp}{snmpversion};
    if( $SRC{$src}{ver} && $ver < $SRC{$src}{ver} ){
	$cf->warning("snmp ver $ver does not support bulk get of $src table. trying to use $SRC{$src}{ver} instead")
	    unless $SRC{$src}{fallback};
	$ver = $SRC{$src}{ver};
    }

    my $help = Service->new(
        type	=> 'Service',
	name	=> '_SNMP_HELPER',
	parents	=> [ $me ],			# so we can inherit snmp params
	transient  => 1,
	status	=> 'up',
	ovstatus=> 'up',
	unique  => "SNMP_HELPER:${host}/${port}/${src}",
	notypos => 1,
	snmph   => {
	    idxsrc => $src,
	},
	config	=> {
	    uname	=> "SNMP_HELPER:${host}/${port}/${src}",
	    label	=> $host,
	    hostname	=> $host,
            port	=> $port,
	    oid		=> 'sysUptime',		# placeholder to prevent config error
            community   => $comm,

	    severity	=> 'critical',
	    passive     => 'yes',     		# passive - sets nostatus=yes, siren=no, sendnotify=no
	    nostats     => 'yes',     		# nostats - do not save statistics
	    overridable => 'no',      		# because that would be silly
	    graph	=> 'no',

	    frequency   => (::topconf('snmp_helper_frequency') || $FREQUENCY),
	    timeout     => (::topconf('snmp_helper_timeout')   || $TIMEOUT),
	    retries 	=> 3,
	    retrydelay  => 1,	      		# chunk delay

	    snmpversion => $ver,
	},
    );

    $help->{config}{debug} = 1 if $me->{config}{debug};

    $help->config($cf);
    $help->{parents} = []; # orphan
    delete $help->{snmp}{bulkoid};

    $host{$key} = {
	service		=> $help,
	hostname	=> $host,
	idxsrc		=> $src,
	nservices       => 1,
    };

    ::loggit( "SNMP Helper enabled for host $host/$src");


    # ...

}

sub helper_not_needed {
    my $me = shift;

    my $key  = _hostkey($me);

    # helper is refcounted. delete if no longer needed.

    if( -- $host{$key}{nservices} <= 0 ){

	my $s = $host{$key}{service};
	$s->recycle() if $s;
	delete $host{$key};
    }
}

sub helper_check_oid {
    my $me = shift;

    my $idx  = $me->{snmp}{idxname};
    my $key  = _hostkey($me);
    my $h    = $host{$key};

    if( $h->{descr} && $h->{descr}{$idx} ){
	# found
	my $oid = $me->{snmp}{tabloid} . '.' . $h->{descr}{$idx};
	if( $oid ne $me->{snmp}{getoid} ){
	    $me->debug("discovered OID $idx => $oid");
	    $me->{snmp}{getoid} = $oid;
	    $me->snmp_oid_bulk_init($oid);
	}
	return $oid;
    }

    if( $h->{descr} ){
	# queried router. interface not found.
	die "index for '$idx' not found. check spelling?\n";
    }

    my $hs = $h->{service};

    if( $me->{ip}{addr}->is_timed_out() ){
	# cannot resolve host
        die "cannot resolve host '$me->{ip}{hostname}'\n";
    }

    if( $hs->{status} eq 'down' ){
	die "cannot fetch name-to-index table: $hs->{srvc}{reason}\n";
    }

    # else test still underway
    return ;
}

################################################################

sub import {
    my $pkg = shift;
    my $caller = caller;

    for my $f (qw(helper_init helper_check_oid helper_not_needed)){
	no strict;
	*{$caller . '::' . $f} = $pkg->can($f);
    }
}

################################################################
Doc::register( $doc );
push @Service::probes, \&probe;

1;
