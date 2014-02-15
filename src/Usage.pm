# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Nov-06 18:03 (EST)
# Function: monitor my own resource usage - for testing
#
# $Id: Usage.pm,v 1.16 2007/01/08 05:30:05 jaw Exp $

# deprecated - see Self.pm

package Usage;
use Argus::Encode;

$PATH_PS = "/bin/ps";

@ISA = qw(Service);
$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [qw(Service MonEl BaseIO)],
    methods => {},
    versn  => '3.2',
    fields => {
      usage::param => {
	  attrs => ['config'],
      },
    },
};

sub probe {
    my $name = shift;

    return ( $name =~ /^Usage/ ) ? [ 4, \&config ] : undef;
}

sub config {
    my $me = shift;
    my $cf = shift;
    
    bless $me;
    $me->init_from_config( $cf, $doc, 'usage' );
    
    if( $me->{name} =~ /Usage\/(.*)/ ){
	$me->{usage}{param} ||= $1;
    }
    
    $me->{label_right_maybe} ||= $me->{usage}{param};
    $me->{uname} = "Usage_$me->{usage}{param}";
}

sub start {
    my $me = shift;
    my( $p, $i, $ru, @r );

    $me->Service::start();
    $p = $me->{usage}{param};
    
    if( $p eq 'load' ){
	$ru = `uptime`;
	$ru =~ s/.*:\s*([\d\.]+).*\n?/$1/;
    }elsif( $p eq 'Objects' ){
	$ru = @MonEl::all;
    }elsif( $p eq 'Notifs' ){
	$ru = Notify::number_of_notifies();
    }elsif( $p eq 'Sched' ){
	$ru = @BaseIO::bytime;
    }elsif( $p eq 'idle' ){
	$ru = $::idletime;
    }elsif( $p eq 'idlepct' ){
	$ru = 100 * $::idletime / ($^T - $::starttime);
    }elsif( $p eq 'tested' ){
	$ru = $Service::n_tested;
	
    }elsif( $p !~ /\d/ ){
	$ru = `$PATH_PS -p $$ -o $p | tail -1`;
    }else{

	$ru = 0;
    }
    $me->generic_test($ru, 'USAGE');
}

sub about_more {
    my $me = shift;
    my $ctl = shift;
    my( $k, $v );

    $me->Service::about_more($ctl);
    $me->more_about_whom($ctl, 'usage');
}

    
################################################################
# global config
################################################################
Doc::register( $doc );
push @Service::probes, \&probe;

1;
