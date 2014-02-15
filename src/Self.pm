# -*- perl -*-

# Copyright (c) 2003 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2003-Apr-06 13:08 (EST)
# Function: monitor myself - for testing, etc
#
# $Id: Self.pm,v 1.16 2012/10/29 00:50:31 jaw Exp $


package Self;
@ISA = qw(Service);
use Argus::Encode;

# I know myself now
#   -- Shakespeare, King Henry VIII

use strict qw(refs vars);
use vars qw(@ISA $doc);

$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [qw(Service MonEl BaseIO)],
    methods => {},
    versn  => '3.2',
    html   => 'self',
    fields => {
      self::param => {
	  descr => 'which internal value',
	  vals  => ['idle', 'tested', 'files', 'objects', 'notifs', 'sched', 'services',
                    'uptime1', 'uptime2', 'loops', 'dnsqueries' ],
	  attrs => ['config'],
      },
    },
};

sub probe {
    my $name = shift;

    return ( $name =~ /^Self/i ) ? [ 4, \&config ] : undef;
}

sub config {
    my $me = shift;
    my $cf = shift;
    
    bless $me;
    $me->init_from_config( $cf, $doc, 'self' );
    
    if( $me->{name} =~ /Self\/(.*)/i ){
	$me->{self}{param} ||= $1;
    }
    
    $me->{label_right_maybe} ||= $me->{self}{param};
    $me->{uname} = "Self_$me->{self}{param}";
    $me->{friendlyname} = "test of argus internal $me->{self}{param}";
    
}

sub start {
    my $me = shift;
    my( $p, $ru );

    $me->SUPER::start();
    $p = lc($me->{self}{param});
    
    if( $p eq 'objects' ){
	$ru = @MonEl::all;
    }elsif( $p eq 'notifs' || $p eq 'notifies' ){
	$ru = Notify::number_of_notifies();
    }elsif( $p eq 'unacked' ){
        $ru = Notify::num_unacked();
    }elsif( $p eq 'sched' ){
	for my $t ( @BaseIO::bytime ){
	    $ru += ($t && $t->{elem}) ? grep {$_} @{$t->{elem}} : 0;
	}
    }elsif( $p eq 'files' ){
	$ru = BaseIO::nfds();
    }elsif( $p eq 'services' ){
	$ru = $Service::n_services;
    }elsif( $p eq 'idle' ){
	$ru = $::idletime;
    }elsif( $p eq 'tested' ){
	$ru = $Service::n_tested;
    }elsif( $p eq 'loops' ){
	$ru = $::loopcount;
    }elsif( $p eq 'uptime1' ){
	$ru = $^T - $::starttime;
    }elsif( $p eq 'uptime2' ){
	$ru = $^T - $::mainstart;
    }elsif( $p eq 'three' ){
	$ru = 3;
    }elsif( $p eq 'dnsqueries' ){
        $ru = $Argus::Resolv::total_queries;
    }else{
	$ru = 0;
    }
    $me->generic_test($ru, 'SELF');
}

sub about_more {
    my $me = shift;
    my $ctl = shift;
    my( $k, $v );

    $me->SUPER::about_more($ctl);
    $me->more_about_whom($ctl, 'self');
}

    
################################################################
# global config
################################################################
Doc::register( $doc );
push @Service::probes, \&probe;

1;
