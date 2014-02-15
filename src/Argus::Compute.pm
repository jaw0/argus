# -*- perl -*-

# Copyright (c) 2007 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2007-Dec-22 12:27 (EST)
# Function: service for math calculations
#
# $Id: Argus::Compute.pm,v 1.9 2012/10/27 03:12:18 jaw Exp $

# But the age of chivalry is gone; that of sophisters, economists,
# and calculators has succeeded.
#   -- Edmund Burke, Reflections on the Revolution in France

package Argus::Compute;
@ISA = qw(Service);
use Argus::Encode;
use Argus::Interpolate;

use strict qw(refs vars);
use vars qw($doc @ISA);


$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [qw(Service MonEl BaseIO)],
    methods => {},
    versn => '3.6',
    html  => 'compute',
    fields => {
      compute::expr => {
	  descr => 'mathmatical expression on other services',
	  exmpl => "( %{Top:Foo} + %{Top:Bar} ) / %{Top:Baz}",
	  attrs => ['config', 'inherit'],
      },
      compute::downtime => {},
      compute::srvcs => {},
    },
};

sub probe {
    my $name = shift;

    return [7, \&config] if $name =~ /^Compute/i;
}

sub config {
    my $me = shift;
    my $cf = shift;

    $me->init_from_config( $cf, $doc, 'compute' );

    my $expr = $me->{compute}{expr};
    $me->{uname} = "COMPUTE_$expr";

    # What mad expressions did my tongue refuse
    #   -- Virgil, Aenid
    return $cf->error( 'expr not specified' )
	unless $expr;

    bless $me if( ref($me) eq 'Service' );
    $me;
}

# NB: if darp'ed, the dependancies may not exist yet

sub resolve_depends {
    my $me = shift;
    my $cf = shift;	# undef if we are reresolving post conf

    my $expr = $me->{compute}{expr};

    # get list of services
    my @srvc = map {
        # remove groupop
        s/.*\s+//;	# 'SUM Top:Foo'	=> Top:Foo
        $_;
    } $expr =~ /%\{([^{}]+)/g;

    delete $me->{compute}{unresolved};

    $cf->error('compute expr must reference results of monitored services') if $cf && ! @srvc;

    for my $s (@srvc){
        my $x = MonEl::find($s);

        unless( $x ){
            $me->warning("Cannot resolve compute dependency: $s");
            $me->{compute}{unresolved} = 1;
            next;
        }

        $me->_add_depends( $x );
    }

    $me->SUPER::resolve_depends($cf) if $cf;
}

sub _add_depends {
    my $me = shift;
    my $x  = shift;

    $x = $x->aliaslookup();

    if( exists $x->{srvc} ){

        unless( grep {$x == $_} @{$me->{compute}{srvcs}} ){
            # She that would alter services with thee
            #   -- Shakespeare, Twelfth Night
            # add self to srvc, + v/v
            push @{$x->{srvc}{alsorun}}, $me;
            push @{$me->{compute}{srvcs}}, $x;

            $me->debug("adding dependency " . $x->unique());
            return;
        }
    }

    for my $c (@{$x->{children}}){
        $me->_add_depends($c);
    }
}


sub start {
    my $me = shift;

    $me->SUPER::start();
    $me->debug( 'start compute' );

    $me->resolve_depends() if $me->{compute}{unresolved};

    # are all srvcs ready?

    for my $s ( @{$me->{compute}{srvcs}} ){
        # QQQ - service is down, and stays down?
        next if $s->{status} ne 'up';
	unless( $s->{srvc}{result_valid} ){
	    $me->debug("service not ready: " . $s->unique() );
	    return $me->done();
	}
    }

    my $expr = interpolate($me, $me->{compute}{expr});
    $expr =~ s/#\[[^][\]]+\]/0/g;	#  "#[error]" => 0

    $me->debug("computing: $expr");
    my $r = eval $expr;

    return $me->isdown("computation failed: $@")  if $@;

    # Is wander'd forth, in care to seek me out
    # By computation and mine host's report.
    #   -- Shakespeare, Comedy of Errors

    $me->generic_test($r, 'COMPUTE');

}

sub isup {
    my $me = shift;

    $me->{compute}{downtime} = undef;
    $me->SUPER::isup(@_);
}

sub isdown {
    my $me = shift;

    # emulate retries in a reasonable way
    if( $me->{srvc}{retries} ){
	$me->{compute}{downtime} ||= $^T;
	my $t = 1 + ($^T - $me->{compute}{downtime}) / $me->{srvc}{frequency};
	$me->{srvc}{tries} = $t;
    }

    $me->SUPER::isdown(@_);
}

sub check_now {
    my $me = shift;

    # check all component srvcs
    for my $s ( @{$me->{compute}{srvcs}} ){
	$s->check_now();
    }
    $me->SUPER::check_now();
}

sub recycle {
    my $me = shift;

    delete $me->{compute}{srvcs};
    $me->SUPER::recycle(@_);
}

sub about_more {
    my $me  = shift;
    my $ctl = shift;
    my( $k, $v );

    $me->SUPER::about_more($ctl);
    $me->more_about_whom($ctl, 'compute');
}


################################################################
Doc::register( $doc );
push @Service::probes, \&probe;

1;

