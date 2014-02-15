# -*- perl -*-

# Copyright (c) 2011
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2011-Oct-30 12:55 (EDT)
# Function: colors
#
# $Id: Argus::Color.pm,v 1.3 2011/11/03 02:13:40 jaw Exp $

package Argus::Color;
use strict;

# Downward the various goddess took her flight,
# And drew a thousand colors from the light;
#   -- Virgil, Aeneid
sub web_status_color {
    my $status = shift;
    my $sever  = shift() || 'critical';
    my $where  = shift() || 'fore';

    my $c;
    $status = 'up' if $status eq 'down' && $sever eq 'clear';

    if( $status eq 'down' ){
	$c = {
            warning  => { fore => '#0088DD', back => '#88DDFF' }, # blue
            minor    => { fore => '#CCCC00', back => '#FFFF00' }, # yellow
            major    => { fore => '#DD9900', back => '#FFBB44' }, # orange
            critical => { fore => '#CC0000', back => '#FF4444', bulk => '#ff8888' }, # red
        }->{$sever};

        $c ||=          { fore => '#BB44EE', back => '#DD99FF' }; # purple (unknown)
    }else{
        $c = {
            up       => { fore => '#22AA22', back => '#33DD33', bulk => '#88ff88' }, # green
            override => { fore => '#888888', back => '#DDDDDD' }, # gray
            depends  => { fore => '#DD9900', back => '#FFCC44' }, # orange

      }->{$status};
    }

    if( ref $c ){
        $where = 'back' if $where eq 'bulk' && !$c->{$where};
        return $c->{$where};
    }
    return $c;
}

sub web_element_color {
    my $elem = shift;

    my $c = {
        top_normal	=> '#AABAFF',
        top_error	=> '#FF8888',
        log_altrow	=> '#DDE8FF',
        statline_altrow	=> '#DDE8FF',
        side_button	=> '#DDDDDD',
        acked		=> '#88FF88',
        unacked		=> '#FFAAAA',
    }->{$elem};

    return $c;
}

sub import {
    my $pkg = shift;
    my $caller = caller;

    for my $f (qw(web_status_color web_element_color)){
	no strict;
	*{$caller . '::' . $f} = $pkg->can($f);
    }
}


1;
