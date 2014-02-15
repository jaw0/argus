# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Oct-31 13:37 (EST)
# Function: client side of graph data collector
#
# $Id: Graph.pm,v 1.16 2012/10/27 03:12:18 jaw Exp $

# send data samples to a graphing daemon

package Graph;
use Argus::Archivist;
@ISA = qw(Argus::Archivist);

use Socket;
use POSIX ('_exit');
use strict qw(refs vars);
use vars qw($doc @ISA);

my $graph;
my $send_to_master;
my %buffer;

my $BUF_LOWAT = 8;
my $BUF_HIWAT = 128;


sub new {

    my $prog = ::topconf('graphd_prog') || "$::libdir/graphd";
    $graph = __PACKAGE__->SUPER::new( prog => $prog );
}

sub write {
    my $msg = shift;

    if( $send_to_master ){
        darp_write( $msg );
        return ;
    }

    unless( $graph ){
	new() || return;
    }

    $graph->SUPER::write("sample $msg\n" );
}


# Done to death by slanderous tongues
#   -- Shakespeare, Much Ado about Nothing
sub done {
    my $me = shift;

    $me->SUPER::done();
    $graph = undef if $graph == $me;
}

sub darp_write {
    my $msg = shift;

    foreach my $m ( @{ $DARP::info->{masters}} ){
        my $mn = $m->{name};

        push @{$buffer{$mn}}, $msg;

        if( @{$buffer{$mn}} > $BUF_HIWAT ){
            # trim buffer down
            splice @{$buffer{$mn}}, 0, -$BUF_HIWAT;
        }
        if( @{$buffer{$mn}} >= $BUF_LOWAT ){
            send_to_master( $m );
        }
    }
}

sub send_to_master {
    my $m = shift;

    return unless $m->{darps}{state} eq 'up';
    my $mn = $m->{name};
    my $n  = 1;

    $m->send_command( 'darp_graphd',
                      lines => scalar(@{$buffer{$mn}}),
                      map { ("line" . $n++ => $_) } @{$buffer{$mn}},
                      );

    delete $buffer{$mn};

}

################################################################

sub Service::graph_add_sample {
    my $me  = shift;
    my $val = shift;
    my $st  = shift;

    return if $^T - $me->{graphd}{samples_last_time} < $me->{graphd}{samples_min_time};
    $me->{graphd}{samples_last_time} = $^T;

    $val = $me->{srvc}{elapsed}
    	if $me->{image}{gr_what} eq 'elapsed';
    $val = $st eq 'up' ? 1 : 0
	if $me->{image}{gr_what} eq 'status';

    $val = 0 unless defined $val;

    # make numeric
    if( $val + 0 ){
	$val += 0;
    }else{
	$val =~ s/^.*(-?\d+\.?\d*).*/$1/s;
	$val += 0 ;
    }

    # darp tag if enabled
    my $tag;
    $tag = $me->graph_tag() if $me->can('graph_tag');
    $tag ||= '-';

    my( $expect, $delta ) = (0,0);
    if( $me->{hwab} && $me->{hwab}{expect} ){
        $expect = $me->{hwab}{expect}{y};
        $delta  = $me->{hwab}{expect}{d};
    }

    # sizes?
    my $ss = $me->{graphd}{gr_nmax_samples} || 0;
    my $hs = $me->{graphd}{gr_nmax_hours}   || 0;
    my $ds = $me->{graphd}{gr_nmax_days}    || 0;

    my $file;

    # where does data get stored?
    if( $DARP::mode eq 'slave' && ::topconf('darp_graph_location') eq 'master' ){
        $send_to_master = 1;
    }else{
        $send_to_master = 0;
    }

    if( $send_to_master ){
        $file = $me->pathname("$tag:");
    }else{
        $file = $me->pathname();
    }

    Graph::write( "$^T $file $st $val $ss $hs $ds $expect $delta $tag" );
}

################################################################

# recv data from slave
sub cmd_darp_graphd {
    my $ctl = shift;
    my $param = shift;

    $ctl->ok_n();

    for my $n (1 .. $param->{lines}){
        my $l = $param->{"line$n"};
        Graph::write( $l );
    }
}


################################################################

Control::command_install( 'darp_graphd',     \&cmd_darp_graphd,     "darp remote graph data collection" );

1;

