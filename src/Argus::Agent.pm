# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Nov-06 18:03 (EST)
# Function: monitor various system values via a remote agent
#
# $Id: Argus::Agent.pm,v 1.18 2010/09/01 20:17:21 jaw Exp $

package Argus::Agent;
use Argus::Encode;

# and trust no agent
#   -- Shakespeare

@ISA = qw(TCP);
$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [qw(TCP Service MonEl BaseIO)],
    methods => {},
    versn   => '3.2',
    html    => 'agent',
    fields => {
      agent::param => {
	  descr => 'the parameter to fetch (uptime, load, ...)',
	  attrs => ['config'],
      },
      agent::arg => {
	  descr => 'optional argument',
	  attrs => ['config'],
      },
      agent::agent_port => {
	  descr => 'TCP port for argus remote agent',
	  attrs => ['config', 'inherit'],
	  default => 164,
	  versn => '3.4',
      },
    },
};


sub probe {
    my $name = shift;

    return ( $name =~ /^(SYS|Agent)/ )   ? [ 3, \&config ] : undef;
}

sub config {
    my $me = shift;
    my $cf = shift;
    my( $l );

    bless $me;
    $me->init_from_config( $cf, $doc, 'agent' );

    if( $me->{name} =~ /(SYS|Agent)\/(.*)/ ){
	$me->{agent}{param} ||= $2;
    }

    return $cf->error("no agent param specified")
	unless $me->{agent}{param};

    $me->{tcp}{send} = $me->{agent}{param};
    $me->{tcp}{send} .= " " . $me->{agent}{arg} if defined $me->{agent}{arg};
    $me->{tcp}{send} .= "\n";
    $me->{tcp}{port} = $me->{agent}{agent_port};
    $me->{tcp}{readhow} = 'toeof';

    $l = $me->{tcp}{send};
    chop( $l );
    $l =~ s/\s+/_/g;
    $me->{label_right_maybe} = $l;
    #...
    $me->SUPER::config($cf);
    $me->{uname} = "SYS_$me->{ip}{hostname}_$l";
    $me->{friendlyname} = "$l on $me->{ip}{hostname}";

}

sub about_more {
    my $me = shift;
    my $ctl = shift;
    my( $k, $v );

    $me->SUPER::about_more($ctl);
    $me->more_about_whom($ctl, 'agent');
}


################################################################
# global config
################################################################
Doc::register( $doc );
push @Service::probes, \&probe;

1;
