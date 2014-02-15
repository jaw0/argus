# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Apr-06 21:30 (EST)
# Function: web page stuff
#
# $Id: Web.pm,v 1.82 2012/10/02 01:38:26 jaw Exp $

package MonEl;
use Argus::Color;
use strict;
use vars qw(%byname);

# they could hear Circe within, singing most beautifully as she worked
# at her loom, making a web so fine, so soft, and of such dazzling colours
# as no one but a goddess could weave.
#   -- Homer, Odyssey

sub web_build {
    my $me = shift;
    my $topp = shift;
    my( $h, $file, $fh );

    return undef if ::topconf('_test_mode');
    $h = $topp ? 'bldtimetop' : 'bldtime';
    $file = "$::datadir/html/" . $me->pathname() . ($topp ? '.top' : '.base');
    return $file if $me->{web}{$h} > $me->{web}{transtime};

    $topp = 0 if $me->{web}{alwaysbase};
    $fh   = BaseIO::anon_fh();
    return ::loggit( "Cannot open web file '$file': $!", 0 )
	unless open( $fh, "> $file" ) ;

    $me->web_top($fh, $topp);
    $me->webpage($fh, $topp);	# virt func
    unless( $topp ){
	print $fh "<HR>\n";
	if( $me->{graph} ){
	    $me->web_graphs($fh);
	}
	if( $me->{web}{showstats} && !$me->{nostats} && $me->web_stats($fh) ){
	    print $fh "<HR>\n";
	}
	$me->web_notifs($fh);
	$me->web_logs($fh);
    }
    $me->web_bottom($fh, $topp);

    close $fh;
    $me->{web}{$h} = $^T;
    return $file;

}

sub web_header {
    my $me    = shift;
    my $fh    = shift;
    my $title = shift;
    my $id    = shift;

    $title ||= $me->unique();
    $id    ||= $me->filename();

    my $refresh = $me->{web}{refresh};
    my $bkgimg  = $me->{web}{bkgimage};
    $bkgimg = "BACKGROUND=\"$bkgimg\"" if $bkgimg;

    print $fh "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\">\n";
    print $fh "<!-- start of web_header -->\n";
    print $fh "<!-- cachestale: $me->{web}{cachestale} -->\n";
    print $fh "<HTML><HEAD><TITLE>Argus - $title</TITLE>\n";
    print $fh "<META HTTP-EQUIV=\"REFRESH\" CONTENT=\"$refresh\">\n" if $refresh;
    print $fh "<!-- PUT HEADERS HERE -->\n";

    my $icon = $me->{web}{"icon.$me->{currseverity}"};
    if( $me->{ovstatus} eq 'up' ){
	$icon ||= $me->{web}{icon_up};
    }elsif( $me->{ovstatus} eq 'down' ){
	$icon ||= $me->{web}{icon_down};
    }
    $icon ||= $me->{web}{icon};
    print $fh "<LINK REL=\"icon\" HREF=\"$icon\" TYPE=\"image/gif\">\n"
	if $icon;

    # permit mutiple style sheets + javascripts
    for my $ss ( split /\s+/, $me->{web}{style_sheet} ){
	print $fh "<LINK REL=\"stylesheet\" TYPE=\"text/css\" HREF=\"$ss\">\n";
    }
    for my $js ( split /\s+/, $me->{web}{javascript} ){
	print $fh "<SCRIPT TYPE=\"text/javascript\" SRC=\"$js\"></SCRIPT>\n";
    }
    print $fh "</HEAD><BODY $bkgimg BGCOLOR=\"#FFFFFF\" ID=\"$id\">\n";

    print $fh "<DIV CLASS=HEADER>\n";
    print $fh "$me->{web}{header_all}\n" if $me->{web}{header_all};
    print $fh "$me->{web}{header}\n" if $me->{web}{header};
    print $fh "</DIV>\n";
    print $fh "<!-- end of web_header -->\n";

}

sub web_show_has_errors {
    my $me = shift;
    my $fh = shift;
    my $nc = shift;

    my $color = web_element_color('top_error');
    print $fh <<X;
        <TR CLASS=WARNING BGCOLOR="$color"><TD COLSPAN=$nc>
	<TABLE CLASS=WARNING><TR><TD>
	<H2>Warning&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</H2>
	</TD><TD>
	<B>Errors detected during startup</B><BR>
	Attempting to run anyway<BR>
	Examine the <A HREF="__BASEURL__?func=logfile;abridge=1">Error Log</A> for details
	</TD></TR></TABLE>
	</TD></TR>
X
    ;
}

sub web_branding {
    my $me = shift;
    my $fh = shift;
    my $cs = shift;

    $cs = "colspan=" . ($cs - 1) if $cs;

    print $fh qq(<tr><td $cs valign=bottom align=left class=headerbranding>$me->{web}{header_branding}</td><td valign=bottom align=right class=headerargus><A HREF="$::ARGUS_URL">Argus Monitoring</A></td></tr>\n);

}
sub web_top {
    my $me = shift;
    my $fh = shift;
    my $topp = shift;
    my( $wav, $t );

    my $n = $me->unique();
    my $file = $me->filename();

    print $fh "<!-- start of web_top -->\n";
    $me->web_header($fh);
    print $fh "<!-- START AUTHORIZATION READ NEEDED $me->{acl_page} -->\n";

    if( $me->{alarm} ){
	$t = $me->{sirentime};
	$wav = $me->{web}{sirensong};
	if( $wav ){
	    # Song that as greatly doth transcend our Muses,
	    # Our Sirens, in those dulcet clarions,
	    # As primal splendour that which is reflected.
	    #   -- Dante, Divine Comedy

	    # cgi will do browser detection and re-write this
	    print $fh "<!-- START SIREN $t $wav -->\n";
	}
    }

    print $fh "<TABLE WIDTH=\"100%\" BORDER=0 cellpadding=0 cellspacing=0 CLASS=MAIN>\n";

    my $color = web_element_color( $Conf::has_errors ? 'top_error' : 'top_normal' );

    my $nospkr = $me->{web}{nospkr_icon};
    $nospkr = "<IMG SRC=\"$nospkr\" ALT=\"speaker off\">" if $nospkr;
    $me->web_branding($fh);

    if( $Conf::has_errors && $topp ){
	$me->web_show_has_errors($fh, 2);
    }

    print $fh <<X;
<!-- PUT WARNINGS HERE -->
<TR BGCOLOR="$color"><TD COLSPAN=2>
  <TABLE BORDER=0 WIDTH="100%" CLASS=TOPBAR>
    <TR> <TD ALIGN=LEFT class=objectname>$n</TD> <TD ALIGN=RIGHT class=username><L10N User>: <TT>__USER__</TT>
	<!-- SIREN ICON -->$nospkr
	</TD> </TR>
  </TABLE>
</TD></TR>
<TR><TD VALIGN=TOP class=maincontent>
<!-- end of web_top -->
X
    ;

}

# I saw by night, and behold a man riding upon a red horse, and
# he stood among the myrtle trees that were in the bottom;
#   -- zechariah 1:8
sub web_bottom {
    my $me = shift;
    my $fh = shift;
    my $topp = shift;

    print $fh "<!-- start of web_bottom -->\n</TD><TD VALIGN=TOP class=sidebuttons>\n";
    $me->web_side_buttons($fh, $topp);
    print $fh "</TD></TR>\n</TABLE>\n";

    print $fh "<!-- END AUTHORIZATION READ NEEDED -->\n";

    $me->web_arjax($fh, $topp) if $me->{web}{javascript};

    $me->web_footer($fh);
    print $fh "<!-- end of web_bottom -->\n";
}

sub web_footer {
    my $me = shift;
    my $fh = shift;

    print $fh "<!-- start of web_footer -->\n";
    print $fh "<DIV CLASS=FOOTER>\n";
    print $fh "$me->{web}{footer}\n" if $me->{web}{footer};
    print $fh "$me->{web}{footer_all}\n" if $me->{web}{footer_all};
    print $fh "</DIV>\n";
    print $fh "<DIV CLASS=FOOTERARGUS>$me->{web}{footer_argus}</DIV>\n"
	if $me->{web}{footer_argus};

    # warn the user if the css/js files are missing or out of date
    # the current argus.css + argus.js will hide these divs
    # update version number occasionally
    print $fh "<div id=\"arguserror_js37\"><b>Error: cannot load argus javascript</b></div>\n";
    print $fh "<div id=\"arguserror_ss37\"><b>Error: cannot load argus style_sheet</b></div>\n";
    print $fh "</BODY>\n";
    print $fh "<!-- end of web_footer -->\n";
    print $fh "</HTML>\n";
}

# I must remove Some thousands of these logs and pile them up
#   -- Shakespeare, Tempest
sub web_logs {
    my $me = shift;
    my $fh = shift;

    return undef unless $me->{stats}{log} && @{$me->{stats}{log}};
    print $fh "<!-- start of web_logs -->\n";
    print $fh "<B class=heading><L10N Recent Activity></B><BR>\n";
    print $fh "<TABLE CELLSPACING=0 CLASS=LOGS>\n";
    print $fh "<tr><th><L10N when></th><th><L10N state></th><th><L10N reason></th></tr>\n";

    my $n = 0;
    my $l_color = web_element_color('log_altrow');
    foreach my $l ( reverse @{$me->{stats}{log}} ){
	# [time, status, ovstatus, tag, msg]
	my $st = $l->[2];
        my $rcolor = ($n++ % 2) ? qq( BGCOLOR="$l_color") : '';
	my $scolor = web_status_color( $l->[1], '', 'fore' );

	print $fh "<TR$rcolor><TD ALIGN=RIGHT><LOCALTIME $l->[0]> ",
	    "</TD><TD style=\"color:$scolor;}\"> <L10N $st> </TD><TD> $l->[3] - $l->[4]</TD></TR>\n";

    }
    print $fh "</TABLE>\n";
    print $fh "<!-- end of web_logs -->\n";
    1;
}

sub percent {
    my $n = shift;
    my $d = shift;
    my( $x, $y );

    return "0.00" unless $d;
    $x = 100 * $n/$d;
    return "100.0" if $x == 100;
    if( $x > 99.99 && $x < 100.0 ){
	sprintf "%.4f", $x;
    }else{
	sprintf "%.2f", $x;
    }
}

sub elapsed {
    my $e = shift;
    my( $r, @e );

    @e = gmtime($e);
    $e[5] -= 70;
    $e[3] --;
    $e[4] += 12 * $e[5];

    $r = sprintf " %dm %dd %d:%0.2d:%0.2d", @e[4,3,2,1,0];
    $r =~ s/ 0[md]//g;
    $r =~ s/^\s+//;
    $r;
}

sub web_stat_line {
    my $me = shift;
    my $fh = shift;
    my $label = shift;
    my $set   = shift;
    my $n     = shift;
    my( $x, $e );

    $x = $me->{stats}{$set}[$n];
    return unless $x;
    $e = $x->{elapsed};
    my $scolor = web_element_color('statline_altrow');

    my $color = $n ? '' : qq( BGCOLOR="$scolor");

    print $fh "<TR$color><TD><L10N $label> </TD><TD ALIGN=RIGHT>&nbsp; <LOCALTIME $x->{start}>",
    	"</TD><TD ALIGN=RIGHT> ",
    elapsed($x->{elapsed}), " </TD><TD ALIGN=RIGHT>&nbsp; ", percent($x->{up}, $e),
    "</TD><TD ALIGN=RIGHT>&nbsp; ", percent($x->{down}, $e),
    "</TD><TD ALIGN=RIGHT> $x->{ndown}</TD></TR>\n";

}

sub web_stats {
    my $me = shift;
    my $fh = shift;

    print $fh "<!-- start of web_stats -->\n";

    print $fh "<B class=heading><L10N Status></B>: <span class=statussince><L10N $me->{status} since> <LOCALTIME $me->{transtime}></span><BR>\n";
    print $fh "<TABLE BORDER=0 CELLSPACING=0 CLASS=STATS>\n";
    print $fh "<TR><TH>&nbsp;</TH><TH><L10N start></TH><TH><L10N elapsed time></TH>",
    "<TH>% <L10N up></TH><TH>% <L10N down></TH><TH><L10N times down></TH></TR>\n";

    $me->web_stat_line($fh, 'Today', 'daily', 0);
    $me->web_stat_line($fh, 'Yesterday', 'daily', 1);
    $me->web_stat_line($fh, '2 Days Ago', 'daily', 2);

    $me->web_stat_line($fh, 'This Month', 'monthly', 0);
    $me->web_stat_line($fh, 'Last Month', 'monthly', 1);
    $me->web_stat_line($fh, '2 Months Ago', 'monthly', 2);

    $me->web_stat_line($fh, 'This Year', 'yearly', 0);
    $me->web_stat_line($fh, 'Last Year', 'yearly', 1);
    $me->web_stat_line($fh, '2 Years Ago', 'yearly', 2);
    print $fh "</TABLE>\n";

    print $fh "<!-- end of web_stats -->\n";
    1;
}

sub web_override {
    my $me = shift;
    my $fh = shift;

    return unless $me->{override};
    print $fh "<!-- start of web_override -->\n";
    print $fh "<HR>\n<B class=heading><L10N Override></B>\n<TABLE CLASS=OVERRIDE>\n";
    foreach my $k (qw(user time expires mode ticket text)){
	my $v = $me->{override}{$k};
	next unless $v;
	$v = "<LOCALTIME $v>" if( $k eq 'time' || $k eq 'expires' );
	if( $k eq 'ticket' && use_tkt() ){
	    $v = $me->tkt_watch_web($v);
	}
	print $fh "<TR><TD>&nbsp;</TD><TD><L10N $k></TD><TD>$v</TD></TR>\n";
    }


    print $fh "</TABLE>\n";
    print $fh "<!-- end of web_override -->\n";
}


sub web_button {
    my $me    = shift;
    my $label = shift;
    my $class = shift;
    my $link  = $me->url(@_);

    my $id;
    foreach my $p (@_){
	my($func) = $p =~ /func=(.*)/;
	$id ||= $func;
    }

    $id = qq( id="button_$id") if $id;
    $me->web_button_text( "<A$id HREF=\"$link\"><L10N $label></A>", $class )
}

sub web_button_no {
    my $me    = shift;
    my $label = shift;
    my $class = shift;
    my $link  = join( ';', @_ );

    $link = '__BASEURL__' . ($link ? '?' : '') . $link;
    $me->web_button_text( "<A HREF=\"$link\"><L10N $label></A>", $class )
}

sub web_button_text {
    my $me    = shift;
    my $txt   = shift;
    my $class = shift;

    $class ||= 'BUTTON';
    "<TABLE BORDER=0 cellspacing=0 WIDTH=\"100%\" CLASS=BUTTON><TR><TD CLASS=$class ALIGN=CENTER>".
    "$txt</TD></TR></TABLE>\n";
}

sub web_side_buttons {
    my $me = shift;
    my $fh = shift;
    my $topp = shift || 0;

    my $top = $byname{Top};
    print $fh $me->{web}{buttons_top_html}, "\n" if $me->{web}{buttons_top_html};

    unless( $topp ){
	if( $me->{overridable} ){
	    print $fh "<!-- START AUTHORIZATION RW NEEDED $me->{acl_override} -->\n";
	    if( $me->{override} ){
		print $fh $me->web_button('Remove Override', undef, 'func=rmoverride');
	    }else{
		print $fh $me->web_button('Override', undef, 'func=override');
	    }
	    print $fh "<!-- END AUTHORIZATION RW NEEDED -->\n";
	}

	print $fh "<!-- START AUTHORIZATION RW NEEDED $me->{acl_annotate} -->\n";
	if( $me->{annotation} ){
	    print $fh $me->web_button('Remove Annotation', undef, 'func=rmannotate', 'phase=1');
	}else{
	    print $fh $me->web_button('Annotate', undef, 'func=annotate');
	}
	print $fh "<!-- END AUTHORIZATION RW NEEDED -->\n";

	print $fh "<!-- START AUTHORIZATION RW NEEDED $me->{acl_checknow} -->\n";
	print $fh $me->web_button('Check&nbsp;Now', undef, 'func=checknow');
	print $fh "<!-- END AUTHORIZATION RW NEEDED -->\n";
    }

    print $fh "<!-- START AUTHORIZATION RW NEEDED $me->{acl_getconf} -->\n";
    print $fh $me->web_button('View&nbsp;Config', undef, 'func=dispconf');
    print $fh "<!-- END AUTHORIZATION RW NEEDED -->\n";

    print $fh "<!-- START AUTHORIZATION DEBUG NEEDED $me->{acl_about} -->\n";
    print $fh $me->web_button('Debugging', undef, 'func=about');
    print $fh "<!-- END AUTHORIZATION DEBUG NEEDED -->\n";

    # paging...
    print $fh "<!-- START AUTHORIZATION RW NEEDED $top->{acl_ntfylist} -->\n";
    print $fh $me->web_button_no('Notifies', undef, 'func=ntfylist');
    print $fh $me->web_button_no('Un-Acked__NUMUNACKED__', '__UNACKEDCLASS__', 'func=ntfylsua');
    print $fh "<!-- END AUTHORIZATION RW NEEDED -->\n";

    print $fh $me->web_button_no('Overview', undef, 'object=overview', 'func=page');

    # error log
    print $fh "<!-- START AUTHORIZATION RW NEEDED $top->{acl_logfile} -->\n";

    my $errclass = $Conf::has_errors ? 'ERRORSBUTTON' : undef;
    print $fh $me->web_button_no('Error Log', $errclass, 'func=logfile', 'abridge=1' );
    print $fh "<!-- END AUTHORIZATION RW NEEDED -->\n";

    if( $me->{alarm} && $me->{web}{sirensong} ){
	my $t = $me->{sirentime};
	print $fh "<!-- START SIRENBUTTON $t -->\n";
	if( $topp ){
	    print $fh $me->web_button('Hush Siren', undef, 'func=hushsiren', 'top=1');
	}else{
	    print $fh $me->web_button('Hush Siren', undef, 'func=hushsiren');
	}
	print $fh "<!-- END SIRENBUTTON -->\n";
    }

    # Top
    print $fh "<BR>\n";
    print $fh $me->web_button_text( "<A HREF=\"__BASEURL__?object=__TOP__;func=page\"><span class=buttonarrow>&lArr;</span>Top</A>" )
	unless $topp;

    # parents
    foreach my $p (@{$me->{parents}}){
	unless( $p->{name} eq 'Top' ){
	    print $fh "<!-- START AUTHORIZATION RW NEEDED $p->{acl_page} -->\n";
            my $url = $p->url('func=page');
	    print $fh $me->web_button_text( qq(<A HREF="$url"><span class=buttonarrow>&larr;</span>$p->{name}</A>) );
	    print $fh "<!-- END AUTHORIZATION RW NEEDED -->\n";
	}
    }

    # dashboards
    my @dash = Argus::Dashboard::list();
    if( @dash ){
        for my $dash (sort @dash){
            print $fh $me->web_button_text( "<A HREF=\"__BASEURL__?object=Dash:$dash;func=page\" title=\"<L10N dashboard>\">"
                                         . "<span class=buttonarrow>&sect;</span>$dash</A>" );
        }
    }

    print $fh "<BR>\n";
    print $fh $me->{web}{buttons_bottom_html}, "\n" if $me->{web}{buttons_bottom_html};

    # logout
    print $fh $me->web_button('Logout', undef, 'func=logout');


}

sub web_page_row_top {
    my $me = shift;
    my $fh = shift;
    my $label = shift;

    return if $me->{web}{hidden};
    return unless @{$me->{children}};
    print $fh "<TR><TD><A HREF=\"", $me->url('func=page'), "\">",
        ($label||$me->{label_left}||$me->{name}), "</A></TD>";

    my $smy = $me->summary();
    my $csv = $smy->{severity};

    foreach my $s ('up', 'down', 'override'){
	my $color = $smy->{$s} ? (" BGCOLOR=\"" . web_status_color($s, $csv, 'back') . "\"" ) : '';
	print $fh "<TD WIDTH=\"25%\" ALIGN=RIGHT$color>", ($smy->{$s}||0), "</TD>";
    }
    print $fh "</TR>\n";
}

sub web_notifs {
    my $me = shift;
    my $fh = shift;

    return unless $me->{notify}{list} && @{$me->{notify}{list}};
    return unless $me->{web}{shownotiflist};
    print $fh "<!-- start of web_notifs -->\n";
    print $fh "<!-- START AUTHORIZATION RW NEEDED $me->{acl_ntfydetail} -->\n";
    print $fh "<B class=heading><L10N Notifications>:</B> \n";

    my $MAX = 20;
    foreach my $n ( reverse @{$me->{notify}{list}} ){
	my $link = "__BASEURL__?func=ntfydetail;idno=$n->{idno}";
	my $color = web_status_color( $n->{objstate}, $n->{severity}, 'fore' );
	print $fh "<A HREF=\"$link\"><FONT COLOR=$color>$n->{idno}</FONT></A>\n";
        last unless $MAX--;
    }
    print $fh "<BR>\n<HR>\n";
    print $fh "<!-- END AUTHORIZATION RW NEEDED -->\n";
    print $fh "<!-- end of web_notifs -->\n";

}

sub web_graphs {
    my $me = shift;
    my $fh = shift;

    return unless $me->{graph};
    return if ::topconf('_no_images');

    print $fh "<!-- start of web_graphs -->\n";
    print $fh "<DIV CLASS=GRAPHS>\n";
    my @p;
    push @p, ht => $me->{image}{gr_height} if $me->{image}{gr_height};
    for my $w (qw(samples hours days)){
	next unless $me->{image}{"gr_show_$w"};
	my $url = $me->url('func=graph', "which=$w", 'size=thumb', @p, 'ext=.png');
	my $big = $me->url('func=graphpage', "which=$w", 'size=full' );
	print $fh "\t<DIV CLASS=GRAPH><A HREF=\"$big\"><IMG HEIGHT=80 WIDTH=200 BORDER=0 CLASS=THUMB ",
	"SRC=\"$url\" ALT=\"graph\"></A><BR><A class=graphlabel HREF=\"$big\"><L10N $w></A></DIV>\n";
    }
    print $fh "</DIV>\n";
    print $fh "<HR>\n";
    print $fh "<!-- end of web_graphs -->\n";
}

################################################################

sub web_arjax {
    my $me = shift;
    my $fh = shift;
    my $topp = shift;

    my $obj = $me->filename();
    my $ovbase = $me->url('func=override');
    $ovbase =~ s/\?.*//;

    print $fh <<EOFORM;
    <!-- START AUTHORIZATION RW NEEDED $me->{acl_annotate} -->
    <div id="annotatediv" style="display: none;"><div class=inner>
    <form name=annotateform method=post action="__BASEURL__">
    <input type=hidden name=func value=annotate>
    <input type=hidden name=phase value=1>
    <input type=hidden name=object value="$obj">
    <center><b class=heading><L10N Annotation></b></center><center><input type=text name=text size=32></center>
    <br><center><input type=submit> <input id=annotatecancel type=button value=Cancel></center>
    </form>
    </div></div>
    <!-- END AUTHORIZATION RW NEEDED -->

    <!-- START AUTHORIZATION RW NEEDED $me->{acl_override} -->
    <div id="overridediv" style="display: none;"><div class=inner>
    <form name=overrideform method=post action="$ovbase">
    <input type=hidden name=func value=override>
    <input type=hidden name=phase value=1>
    <input type=hidden name=object value="$obj">

    <center><b class=heading><L10N Override></b></center>
    <table cellpadding=0 cellspacing=0>
    <tr><td><L10N Comment>: </td><td><input type="text" name="text" size="32" /></td></tr>
EOFORM
    ;

    # include ticket link if tkt is configured
    print $fh qq{<tr><td><L10N Ticket No.>: </td><td><input type="text" name="ticket" size="16" /></td></tr>\n}
        if use_tkt();

    # default to manual if up, else auto
    my $autop = $me->{ovstatus} eq 'up' ? '' : 'selected=1';
    my $manup = $autop ? '' : 'selected=1';

    print $fh <<OVF2;
<tr><td><L10N Mode>: </td><td><select name="mode">
<option $autop value="auto"><L10N auto></option>
<option $manup value="manual"><L10N manual></option></select></td></tr>
<tr><td><L10N Expires>: </td><td><select name="expires" tabindex="4">
<option value="0">never</option><option value="900">15 min</option><option value="1800">30 min</option>
<option value="3600">1 hour</option><option value="7200">2 hours</option><option value="10800">3 hours</option>
<option selected="selected" value="14400">4 hours</option>
<option value="21600">6 hours</option><option value="28800">8 hours</option><option value="43200">12 hours</option>
<option value="64800">18 hours</option><option value="86400">24 hours</option><option value="129600">36 hours</option>
<option value="172800">2 days</option><option value="259200">3 days</option><option value="345600">4 days</option>
<option value="432000">5 days</option><option value="604800">7 days</option><option value="864000">10 days</option>
<option value="1209600">14 days</option><option value="1728000">20 days</option>
<option value="2592000">30 days</option><option value="3888000">45 days</option>
</select></td></tr>
OVF2
    ;

    print $fh <<EOF2;
    <tr><td colspan=2><br><center><input type=submit>
	<input id=overridecancel type=button value=Cancel></center></td></tr>
    </table>
    <div id=overridefoot><L10N auto mode - disengage override when status returns to up><br>
    <L10N manual mode - require override be disengaged manually></div>
    </form>
    </div></div>

    <!-- END AUTHORIZATION RW NEEDED -->
EOF2
    ;
}

################################################################

sub cmd_webpage {
    my $ctl = shift;
    my $param = shift;

    if( $param->{object} eq 'overview' ){
	my  $f = web_overview();
	$ctl->ok();
	$ctl->write( "file: $f\n" );
	$ctl->write("\n");
	return;
    }

    my $x = $MonEl::byname{ $param->{object} };
    $x ||= Argus::Dashboard::find( $param->{object} );

    if( $x ){
	my $f = $x->web_build( ($param->{top} eq 'yes')? 1 : 0 );
	$ctl->ok();
	$ctl->write( "file: $f\n" );
        $ctl->write( "unacked: " . Notify::num_unacked() . "\n" );
	$ctl->write("\n");
    }else{
	::loggit( "object not found: $param->{object}", 0 );
        $ctl->bummer(404, 'Object Not Found');
    }
}

# This was what she said, and we assented; whereon we could see her
# working on her great web all day long, but at night she would unpick
# the stitches again by torchlight.
#   -- Homer, Odyssey
sub cmd_flushpage {
    my $ctl = shift;
    my $param = shift;
    my( $x );

    $x = $MonEl::byname{ $param->{object} };
    if( $x ){
	$x->{web}{transtime} = $^T;
	$ctl->ok_n();
    }else{
        $ctl->bummer(404, 'Object Not Found');
    }
}

# spit out data used on login webpage
sub cmd_logindata {
    my $ctl = shift;

    my $x = $MonEl::byname{Top};
    $ctl->ok();
    $ctl->write( "branding: ". encode($x->{web}{header_branding}) . "\n");
    $ctl->write( "header: ". encode("$x->{web}{header_all}") . "\n");
    $ctl->write( "footer: ". encode("<div class=footer>$x->{web}{footer_all}</div> " .
					  "<div class=footerargus>$x->{web}{footer_argus}</div>") . "\n");
    $ctl->write( "bkgimg: ". encode($x->{web}{bkgimage}) . "\n");
    $ctl->write( "style_sheet: ". encode($x->{web}{style_sheet}) . "\n");
    $ctl->write( "icon: ". encode($x->{web}{icon}) . "\n");
    $ctl->final();
}



################################################################
Control::command_install( 'webpage',   \&cmd_webpage,   "build webpage for object",        "object top" );
Control::command_install( 'flushpage', \&cmd_flushpage, "force cached data to be flushed", "object" );
Control::command_install( 'logindata', \&cmd_logindata, 'return decorations for login page' );


1;

