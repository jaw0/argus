# -*- perl -*-

# Copyright (c) 2007 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2007-Dec-30 15:42 (EST)
# Function: web page overview
#
# $Id: Argus::Web::Overview.pm,v 1.9 2012/09/23 15:44:53 jaw Exp $

package MonEl;
use Argus::Color;
use strict;
use vars qw(%byname %isdown %inoverride);


sub web_overview {

    my $file = "$::datadir/html/" . ::hashed_directory('overview') . '/overview';
    my $top  = $::Top;

    return $file if( ($top->{web}{buildtimeov} > $top->{web}{transtime})
		  && ($top->{web}{buildtimeov} > Notify::lastupd()) );

    my $fh = BaseIO::anon_fh();
    return ::loggit( "Cannot open web file '$file': $!", 0 )
	unless open( $fh, "> $file" ) ;
    $top->{web}{buildtimeov} = $^T;

    $top->web_header($fh, 'Overview', 'Overview' );

    print $fh "<TABLE WIDTH=\"100%\" BORDER=0 CLASS=OVERVIEW>\n";

    $top->web_branding($fh, 3);
    $top->web_show_has_errors($fh, 3) if $Conf::has_errors;

    my $color = web_element_color( $Conf::has_errors ? 'top_error' : 'top_normal' );

    print $fh <<X;
<!-- PUT WARNINGS HERE -->
<TR BGCOLOR="$color"><TD COLSPAN=3>
  <TABLE BORDER=0 WIDTH="100%" CLASS=TOPBAR>
    <TR><TD ALIGN=LEFT class=objectname><L10N Overview></TD> <TD ALIGN=RIGHT class=username><L10N User>: <TT>__USER__</TT></TD>
    </TR>
  </TABLE>
</TD></TR>
<TR>
X
    ;

    # interesting down, override, unacked
    # recent notify?
    web_overview_down_ov($fh);
    web_overview_override_ov($fh);
    web_overview_unacked_ov($fh);


    print $fh "</TR>\n</TABLE>\n";

    $top->web_footer($fh);

    return $file;
}

sub web_overview_down_ov {
    my $fh = shift;

    print $fh <<XD;
<TD VALIGN=TOP class=coloverviewdown>
<center><b class=heading><L10N Down></b></center>
XD
    ;
    web_overview_down($fh);
    print $fh "</TD>";
}

sub web_overview_down {
    my $fh = shift;

    print $fh "<table class=overviewdown>\n";

    # sort by severity, then newest
    my @obj = sort {
        ($severity_sort{ $b->{currseverity} } <=> $severity_sort{ $a->{currseverity} })
          ||
        ($b->{transtime} <=> $a->{transtime})
    } map { $byname{$_} } keys %isdown;

    for my $x (@obj){
	next unless $x;
	next unless $x->{interesting};
	next if $x->{anc_in_ov};
	next if $x->{ovstatus} eq 'depends';
	my $url   = $x->url('func=page');
	my $label = $x->{label_overview} || $x->unique();
	my $color = web_status_color($x->{ovstatus}, $x->{currseverity}, 'bulk');

	print $fh "<!-- START AUTHORIZATION RW NEEDED $x->{acl_page} -->\n";
	print $fh "<tr><td BGCOLOR=\"$color\"><a href=\"$url\"><font color=\"#000000\">$label</font></a></td></tr>\n";
	print $fh "<!-- END AUTHORIZATION RW NEEDED -->\n";
    }

    print $fh "</table>\n";
}

sub web_overview_override_ov {
    my $fh = shift;

    print $fh <<XD;
<TD VALIGN=TOP class=coloverviewoverride>
<center><b class=heading><L10N Override></b></center>
XD
    ;
    web_overview_override($fh);
    print $fh "</TD>";
}

sub web_overview_override {
    my $fh = shift;

    print $fh "<table class=overviewoverride>\n";

    # uniquify + skip dead
    my %obj;
    %obj = map {$_ => $byname{$_}} keys %inoverride;

    for my $k (keys %DARP::Master::remote_override){
        $obj{$_} = $byname{$_} for @{ $DARP::Master::remote_override{$k} };
    }

    my @obj = grep {$_} values %obj;

    # newest first
    for my $x (sort { $b->{override}{time} <=> $a->{override}{time} } @obj){
	my $url   = $x->url('func=page');
	my $label = $x->{label_overview} || $x->unique();
	my $color = web_status_color($x->{ovstatus}, $x->{currseverity}, 'bulk');

	print $fh "<!-- START AUTHORIZATION RW NEEDED $x->{acl_page} -->\n";
	print $fh "<tr><td BGCOLOR=\"$color\"><a href=\"$url\"><font color=\"#000000\">$label</font></a></td></tr>\n";
	print $fh "<!-- END AUTHORIZATION RW NEEDED -->\n";
    }

    print $fh "</table>\n";
}

sub web_overview_unacked_ov {
    my $fh = shift;

    print $fh <<XD;
<TD VALIGN=TOP class=coloverviewunacked>
<center><b class=heading><L10N Un-Acked></b></center>
XD
    ;
    web_overview_unacked($fh);
    print $fh "</TD>";
}


sub web_overview_unacked {
    my $fh = shift;

    print $fh "<table class=overviewunacked>\n";

    my $unacked = Notify::unacked();
    for my $p (sort {$a->{created} <=> $b->{created}} values %$unacked){
        my $color = web_element_color(($p->{status} eq 'acked') ? 'acked' : 'unacked', '', 'bulk');

	my $txt = $p->{msg};
	$txt =~ s/\n/<br>\n/gs;
	my $url = "__BASEURL__?func=ntfydetail;idno=$p->{idno}";

	print $fh "<!-- START AUTHORIZATION RW NEEDED $p->{obj}{acl_page} -->\n";
	print $fh "<tr><td BGCOLOR=\"$color\"><a href=\"$url\"><font color=\"#000000\">$txt</font></a></td></tr>\n";
	print $fh "<!-- END AUTHORIZATION RW NEEDED -->\n";
    }

    print $fh "</table>\n";
}


1;
