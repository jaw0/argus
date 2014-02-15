# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Oct-09 10:11 (EDT)
# Function: Ticket system interface
#
# $Id: Tkt.pm,v 1.1 2011/10/29 15:36:13 jaw Exp $

package MonEl;

# edit this file.
# drop it into the argus lib directory.

# does:
#  when creating an override, will be able to specify a ticket number
#  a link to the ticket will be displayed with the override
#  if ticket is closed, override will automatically be removed.


# how do we link to a ticket
sub tkt_watch_web {
    my $me = shift;
    my $v  = shift;

    # CHANGE ME:
    qq{<A HREF="http://www.example.com/cgi-bin/tt?ticket=$v">[TT \#$v]</A>};
}

sub tkt_watch_add {
    my $me = shift;
    my $noise = shift;
    
    my $watch = Service->new;
    my $t = $me->{override}{ticket};

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
	# CHANGE US:
	url         => "http://www.example.com/cgi-bin/tt?ticket=$t",
	expect      => 'status: active',
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


# do not allow long duration overrides without a ticket
sub override_policy {
    my $me = shift;

    # has ticket - allow.
    return 1 if $me->{override}{ticket};
    
    # no expiration - no allow
    return 0 unless $me->{override}{expires};

    # more than 4 hours. don't allow.
    return 0 if ($me->{override}{expires} - $^T) > 4 * 3600;
    
    return 1;
}

# checked by cgi
sub cmd_usetkt {
    my $ctl = shift;
    
    $ctl->ok_n();
}

################################################################
Control::command_install( 'use_tkt',  \&cmd_usetkt, 'is this module installed');


1;
