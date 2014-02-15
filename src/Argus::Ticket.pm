# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Oct-09 10:11 (EDT)
# Function: Ticket system interface
#
# $Id: Argus::Ticket.pm,v 1.2 2011/10/31 04:16:58 jaw Exp $

package MonEl;
use strict;

# does:
#  when creating an override, will be able to specify a ticket number
#  a link to the ticket will be displayed with the override
#  if ticket is closed, override will automatically be removed.


# how do we link to a ticket
sub tkt_watch_web {
    my $me = shift;
    my $v  = shift;

    my $url = ::topconf('tkt_view_url');
    $url =~ s/TICKET/$v/g;

    qq{<A HREF="$url">[TT \#$v]</A>};
}

sub tkt_watch_add {
    my $me = shift;
    my $noise = shift;

    my $watch = Service->new;
    my $t = $me->{override}{ticket};

    my $url = ::topconf('tkt_check_url');
    my $expect = ::topconf('tkt_check_expect');
    return unless $url && $expect;
    $url =~ s/TICKET/$t/g;

    $me->loggit( msg => "ticket $t",
		 tag => 'OVERRIDE',
		 slp => 1 ) if $noise && !$me->{override}{quiet};

    # how do we check if a ticket is still active
    # this is a standard argus service monitor
    #   use a TCP/URL test:
    $watch->{name} = 'TCP/URL';

    #   the monitor config:
    $watch->{config} = {
	uname       => "WATCH $t",
	label       => 'watch',
	url         => $url,
	expect      => $expect,
	browser     => 'Argus Ticket Watcher',
	passive     => 'yes',     # passive - sets nostatus=yes, siren=no, sendnotify=no
	nostats     => 'yes',     # nostats - do not save statistics
	overridable => 'no',      # because that would be silly
	frequency   => 60,
	timeout     => 30,
	retries     => 3,
	retrydelay  => 60,
    };

    $watch->{parents}   = [ $me ];
    $watch->{transient} = 1;       # don't save any state
    $watch->{status}    = $watch->{ovstatus} = 'up';

    $watch->{watch}{reason}   = "ticket $t no longer active";
    $watch->{watch}{watching} = $me;
    $watch->{watch}{callback} = \&tkt_watch_down;
    $me   ->{watch}{watched}  = $watch;

    $watch->config();
    $watch;
}

sub tkt_watch_down {
    my $me = shift;
    my $obj = $me->{watch}{watching};

    $obj->override_remove( 'system', $me->{watch}{reason} );
}

sub tkt_watch_del {
    my $me = shift;
    my $w;

    $w = $me->{watch}{watched};
    delete $me->{watch};
    $w->recycle();
}

sub use_tkt {

    my $url    = ::topconf('tkt_check_url');
    my $expect = ::topconf('tkt_check_expect');

    return ($url && $expect);
}

# checked by cgi
sub cmd_usetkt {
    my $ctl = shift;

    if( use_tkt() ){
        $ctl->ok_n();
    }else{
        $ctl->bummer(404, 'Not Enabled');
    }
}

################################################################
Control::command_install( 'use_tkt',  \&cmd_usetkt, 'is this module installed');


1;
