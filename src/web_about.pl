# -*- perl -*-

# Copyright (c) 2005 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2005-Dec-11 11:39 (EST)
# Function:
#
# $Id: web_about.pl,v 1.5 2011/11/03 02:13:41 jaw Exp $

package Argus::Web;
use strict;
use vars qw($argusd $ARGUS_URL);


# names of "interesting" fields - these become colored
my @hl_fields = qw(ovstatus status srvc::lasttesttime
		 srvc::reason srvc::result test::currvalue);

sub web_about {
    my $me = shift;
    my( $obj, $r, $k, $v );

    $obj  = decode( $me->{q}->param('object') );
    return unless $me->check_acl_func($obj, 'about', 1);

    $r = $argusd->command( func => 'about',
			   object => encode($obj),
			   );

    my $rd = $argusd->command( func => 'logindata' ) || {};

    return $me->error( "unable to connect to server" ) unless $r;
    return $me->error( "Unable to access <I>$obj</I><BR>$r->{resultcode} $r->{resultmsg}" )
	unless $r->{resultcode} == 200;

    $me->startpage(title  => "About: $obj",
                   bkgimg => decode($rd->{bkgimg}),
                   style  => decode($rd->{style_sheet}),
                   icon   => decode($rd->{icon}) );
    print decode($rd->{"header"}), "\n";
    $me->top_of_table( title     => l10n("Debugging Dump: $obj"),
                       mainclass => 'aboutmain',
                       branding  => decode($rd->{branding}),
                      );
    print "<TR><TD VALIGN=TOP>\n";

    print
    "&nbsp;&nbsp;&nbsp;&nbsp;<FONT SIZE=\"-1\"><I>documentation for some fields can be found ",
    "<A HREF=\"$ARGUS_URL/debug-details.html\">on the argus website</A> ",
    "or by running <TT>argusd -E</TT></I></FONT><P>\n";

    print "<TABLE CLASS=DEBUGGING>\n";
    foreach $k (sort keys %$r){

	my( $toolong, $color );
	next if $k eq 'resultcode' || $k eq 'resultmsg';
	$v = $r->{$k};
	$v =~ s/~x([234567].)/chr(hex($1))/ge;
	$v = l10n_localtime($v)
	    if( $v && $k =~ /time/ && $v > 1_000_000_000 );
	if( length($v) > 80 ){
	    $toolong = 1;
	    $v = substr($v,0,80);
	}
	if( $v eq "#<REF>" ){
	    $v = "<I>unprintable data structure</I>";
	}else{
	    $v =~ s/&/\&amp\;/g;
	    $v =~ s/</\&lt\;/g;
	    $v =~ s/>/\&gt\;/g;
	    $v =~ s/~x09/ <FONT COLOR=\"\#0000CC\">____ <\/FONT>/g;	# expand tabs
	}
	$v =~ s/(~x..)/<FONT COLOR=\"\#0000CC\">$1<\/FONT>/g;
	$v .= "<FONT COLOR=\"#FF0000\"><B>. . .</B></FONT>" if $toolong;
	$color = ' BGCOLOR="88FF88"' if grep {$_ eq $k} @hl_fields;
	$k = "<A HREF=\"$ARGUS_URL/debug-details.html#$k\"><FONT COLOR=black>$k</FONT></A>"
	    unless $k =~ /^_/;
	print "<TR$color><TD class=debugkey>$k</TD><TD class=debugval>$v</TD></TR>\n";
    }
    print "</TABLE>\n";

    # QQQ - is this useful?
    print "<HR>\n<B>Dump of Current User</B><P><TABLE>\n";
    print "<TR><TD>user</TD><TD>$me->{auth}{user}</TD></TR>\n";
    print "<TR><TD>groups</TD><TD>@{$me->{auth}{grps}}</TD></TR>\n";
    print "<TR><TD>home</TD><TD>$me->{auth}{home}</TD></TR>\n";
    print "<TR><TD>pref</TD><TD>$me->{auth}{pref}</TD></TR>\n" if $me->{auth}{pref};
    # print "<TR><TD>location</TD><TD>$me->{auth}{addr}</TD></TR>\n";
    my $l = l10n_curr_lang();
    print "<TR><TD>locale</TD><TD>$l</TD></TR>\n" if $l;

    my $ht = $me->{auth}{hush} ? l10n_localtime($me->{auth}{hush}) : 'never';
    print "<TR><TD>hush time</TD><TD>$ht</TD></TR>\n";
    print "</TABLE>\n";


    print "</TD></TR>\n";
    $me->bot_of_table();
    print decode($rd->{footer}), "\n";
    $me->endpage();

}

1;
