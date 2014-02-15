# -*- perl -*-

# Copyright (c) 2012
# Author: Jeff Weisberg <jaw @ tcp4me.com>
# Created: 2012-Sep-15 14:51 (EDT)
# Function: 
#
# $Id: Argus::Dashboard::Overview.pm,v 1.1 2012/09/16 05:18:10 jaw Exp $

package Argus::Dashboard::Overview;
@ISA = qw(Argus::Dashboard::Widget);
use vars qw(@ISA);
use strict;


sub cf_widget {
    my $me = shift;
    my $cf = shift;
    my $line = shift;

    # overview down|unacked|override [topN]
    my(undef, $what, $topn) = split /\s+/, $line;

    if( !grep { $what eq $_ } qw(down unacked override) ){
        $cf->nonfatal( "invalid overview widget in config file: '$_' try [down unacked override]" );
        $me->{conferrs} ++;
        return;
    }

    $me->{overview} = $what;
    $me->{topn}     = $topn || 10;

    $me;
}

sub web_make_widget {
    my $me = shift;
    my $fh = shift;

    my $which = $me->{overview};

    if( $which eq 'down' ){
        MonEl::web_overview_down($fh);
    }
    elsif( $which eq 'override' ){
        MonEl::web_overview_override($fh);
    }
    elsif( $which eq 'unacked' ){
        MonEl::web_overview_unacked($fh);
    }

}


1;
