# -*- perl -*-

# Copyright (c) 2005 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2005-Dec-10 12:46 (EST)
# Function: cgi notify related functions
#
# $Id: web_notify.pl,v 1.8 2011/11/03 02:13:41 jaw Exp $

package Argus::Web;
use Argus::Color;
use strict;
use vars qw($argusd);


sub web_ntfylist {
    my $me = shift;
    $me->notify_list( 'Notifications', 0 );
}

sub web_ntfylsua {
    my $me = shift;
    $me->notify_list( 'Unacked Notifications', 1 );
}

sub notify_list {
    my $me = shift;
    my $title = shift;
    my $ackp  = shift;
    my( $q, $n );

    $q = $me->{q};
    my $fmt = $q->param('fmt');

    return web_notify_json($me) if $fmt eq 'json';
    return web_notify_rss($me)  if $fmt eq 'rss';

    return unless $me->check_acl_func('Top', 'ntfylist', 1);
    # QQQ - check ACL for every object listed???
    my $url = $q->url();

    my $r = $argusd->command( func   => 'logindata',
                              object => encode('Top'),
                             );

    my $res = notify_list_data($me, $ackp);

    return $me->error( "unable to connect to server" ) unless $res;
    return $me->error( "Unable to access <I>notify list</I><BR>$res->{error}" ) if $res->{error};

    $me->startpage( title   => l10n($title),
		    refresh => 60,
		    rss     => "$url?func=rss",
		    bkgimg  => decode($r->{bkgimg}),
		    style   => decode($r->{style_sheet}),
		    icon    => decode($r->{icon}) );
    print decode($r->{header}), "\n";

    $me->top_of_table( title     => $title,
                       mainclass => 'notifiesmain',
                       branding  => decode($r->{branding}) );

    print $q->startform(-method=>'get'), "\n" if $ackp;
    print "<TR><TD colspan=2><TABLE class=notifylist WIDTH=\"100%\" CELLSPACING=0 CELLPADDING=0>\n";

    foreach my $nd (@{$res->{data}}){
	$n++;
	my $dt = strftime "%d/%b %R", localtime($nd->{create});
	$dt =~ s/\s+/&nbsp\;/g;
	my $id = $nd->{id};
	my $obj = decode($nd->{obj});
	my $msg = decode($nd->{msg});
	$msg =~ s/\n/<br>\n/gs;
	my $durl = "<A HREF=\"" . $q->url() . "?func=ntfydetail;idno=$id\">$id</A>";
	my $aurl = "<A HREF=\"" . $q->url() . "?func=ntfyack;idno=$id\" class=ackbutton>Ack</A>";
	my $objl = "<A HREF=\"" . $q->url() . "?object=$obj;func=page\">Object</A>";
	# QQQ - or base color on whether it is acked or not?
        my $clr = web_status_color( $nd->{status}, $nd->{seve}, 'bulk' );

	if( $ackp ){
	    print "<TR BGCOLOR=\"$clr\"><TD>$aurl</TD><TD><INPUT TYPE=checkbox NAME=idno VALUE=$id></TD>",
	    "<TD>$durl</TD><TD>$objl</TD><TD>$dt</TD><TD>$msg</TD></TR>\n";
	}else{
	    print "<TR BGCOLOR=\"$clr\"><TD>$durl</TD><TD>$objl</TD><TD>$dt</TD><TD>$msg</TD></TR>\n";
	}
    }

    print "</TABLE>\n";
    if( $ackp && $n ){
	print "<BR><INPUT TYPE=HIDDEN NAME=func VALUE=ntfyack>\n";
	print $q->submit(l10n("Ack Checked")), "\n";
	print $q->submit(l10n("Ack All")), "\n";
	print $q->endform(), "\n";
    }

    unless( $n ){
	if( $ackp ){
	    print l10n("There are no un-acked notifications"), "\n";
	}else{
	    print l10n("There are no notifications"), "\n";
	}
    }

    print "</TD></TR>\n";
    $me->bot_of_table();
    print decode($r->{footer}), "\n";
    $me->endpage();
}

sub web_ntfyack {
    my $me = shift;
    my( $q, @id, $res );

    $q = $me->{q};

    if( $q->param('Ack All') ){
	@id = ('all');
    }else{
	@id = $q->param('idno');
    }

    foreach my $id (@id){
	return $me->error( 'Invalid Notification ID' ) unless $id =~ /^(\d+|all)$/;

	return unless $me->check_acl_ack($id, 1);

	$res = $argusd->command( func  => 'notify_ack',
				 user  => $me->{auth}{user},
				 idno  => $id );
	return $me->error( "unable to connect to server" ) unless $res;
	return $me->error( "Unable to access <I>$id</I><BR>$res->{resultcode} $res->{resultmsg}" )
	    unless $res->{resultcode} == 200;
    }

    if( $q->request_method() eq 'POST'){
	$me->heavy_redirect( $q->url() . "?func=ntfylsua" );
    }else{
	$me->light_redirect( $q->url() . "?func=ntfylsua" );
    }
}

sub web_ntfydetail {
    my $me = shift;
    my( $res, $n, $esc );

    my $q   = $me->{q};
    my $id  = $q->param('idno');

    return $me->error( 'invalid notification' ) unless $id =~ /^\d+$/;
    $res = $argusd->command( func => 'notify_detail',
			     idno => $id );

    return $me->error( "unable to connect to server" ) unless $res;
    return $me->error( "Unable to access <I>$id</I><BR>$res->{resultcode} $res->{resultmsg}" )
	unless $res->{resultcode} == 200;

    # check ACL
    unless( $me->check_acl( decode($res->{acl_ntfydetail})) ){
	return $me->web_acl_error( 'ntfydetail' );
    }

    my $icon = ($res->{objstate} eq 'up') ? 'web icon_up' : 'web icon_down';

    $me->startpage( title      => "Notification $id",
		    refresh    => 60,
		    style      => decode($res->{'web style_sheet'}),
		    javascript => decode($res->{'web javascript'}),
		    bkgimg     => decode($res->{'web bkgimage'}),
		    icon       => decode($res->{$icon} || $res->{'web icon'}),
		    );

    print decode($res->{"web header"}), "\n";
    $me->top_of_table( title     => "Notification $id",
                       mainclass => 'notifydetailmain',
                       branding  => decode($res->{"web branding"}) );

    print "<TR><TD> <TABLE class=notifydetail cellspacing=0 cellpadding=0>\n";
    print "<TR><TD width=\"15%\"><B>ID</B></TD><TD>$id",
        ($res->{state} eq 'active' ? "&nbsp;&nbsp;&nbsp;<A HREF=\"". $q->url().
	 "?func=ntfyack;idno=$id\" class=ackbutton>Ack</A>" : ''),
	"</TD></TR>\n";
    print "<TR><TD><B>Object</B></TD><TD class=notifvalue><A HREF=\"", $q->url(), "?object=$res->{object};func=page\">",
        decode($res->{object}), "</A></TD></TR>\n";

    my $msg = decode($res->{msg_abbr});
    $msg =~ s/\n/<br>\n/gs;
    my $clr = web_status_color( $res->{objstate}, $res->{severity}, 'back' );

    print "<TR><TD><B>Message</B></TD><TD class=notifvalue BGCOLOR=\"$clr\">", $msg, "</TD></TR>\n";
    print "<TR><TD><B>Reason</B></TD><TD class=notifvalue>", decode($res->{reason}), "</TD></TR>\n" if $res->{reason};
    print "<TR><TD><B>Created</B></TD><TD>", l10n_localtime($res->{created}), "</TD></TR>\n";
    $esc = " / <B>Escalated</B>" if $res->{escalated};
    print "<TR><TD><B>Status</B></TD><TD>$res->{state}$esc</TD></TR>\n";
    print "<TR><TD><B>Severity</B></TD><TD>$res->{severity}</TD></TR>\n" if $res->{severity};
    print "<TR><TD><B>Priority</B></TD><TD>$res->{priority}</TD></TR>\n" if $res->{priority};
    print "<TR><TD><B>Audit Detail</B></TD><TD>$res->{detail}</TD></TR>\n" if $res->{detail};

    if( $res->{ackedby} ){
	print "<TR><TD><B>Acked By</B></TD><TD>$res->{ackedby}</TD></TR>\n";
	print "<TR><TD><B>Acked At</B></TD><TD>", l10n_localtime($res->{ackedat}), "</TD></TR>\n";
    }
    print "</TABLE>\n<HR>\n";

    print "<B class=heading>Per User Status</B><BR>\n";
    print "<div class=notifydetailstatus>\n"; # <TABLE BORDER=1>\n<TR>\n";
    foreach my $dst (split /\s+/, $res->{statuswho}){
	my $w = decode($dst);
	my $s = $res->{"status $dst"};
	# print "<TD><B>$w</B><BR>$s</TD>\n";
        print "<span class=notifyuser><b>$w</b><br>$s</span>\n";
    }
    # print "</TR>\n</TABLE>
    print "</div>\n<HR>\n";

    print "<B class=heading>Audit Trail</B><BR>\n";
    print "<div class=notifydetailaudit><TABLE cellspacing=0>\n";
    $n = $res->{loglines} - 1;
    my $l_color = web_element_color('log_altrow');

    foreach my $i (0..$n){
	my($t, $w, $m) = split /\s+/, $res->{"log $i"};

	$w = ($w eq '_') ? '' : decode($w);
	$m = decode($m);
        my $x = ($i%2) ? " BGCOLOR=\"".web_element_color('log_altrow') ."\"" : '';
	print "<TR$x><TD>", l10n_localtime($t), "</TD><TD>$w</TD><TD>$m</TD></TR>\n";
    }
    print "</TABLE></div>\n";
    print "</TD></TR>\n";
    $me->bot_of_table();
    print decode($res->{"web footer"}), "\n";
    $me->endpage();

}

sub notify_list_data {
    my $me   = shift;
    my $ackp = shift;


    my $res = $argusd->command_raw( func  => 'notify_list',
				    which => $ackp ? 'unacked' : ''
				    );

    return unless $res;
    return { error => $res } unless $res =~ /200/;

    my @d;
    while( $_ = $argusd->nextline() ){
	chop;
	last if /^$/;
	my( $id, $stt, $stat, $creat, $obj, $msg,
	    $prio, $seve ) = split;

	$prio = undef if $prio eq '_';
	$seve = undef if $seve eq '_';

	push @d, { id     => $id,
		   state  => $stt,
		   status => $stat,
		   create => $creat,
		   obj    => $obj,
		   msg    => $msg,
		   prio   => $prio,
		   seve   => $seve,
	       };

    }

    return { data => \@d };
}


1;
