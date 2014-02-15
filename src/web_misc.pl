# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Apr-02 23:39 (EST)
# Function: misc web stuff
#
# $Id: web_misc.pl,v 1.27 2012/09/29 21:23:02 jaw Exp $

package Argus::Web;
use Argus::Color;

sub web_error {
    my $me = shift;
    my( $file );

    $file = $me->{q}->path_info();
    $me->error("Method Not Implemented<BR>Cannot Access $file");
}

sub httpheader {
    my $me = shift;

    my @a;

    if( $me->{co} ){
	@a = ( -cookie => $me->makecookie() );
    }
    if( $me->{charset} ){
	push @a, -charset => $me->{charset};
    }

    print $me->{q}->header( @a );
    $me->{header} = 1;
}

sub startpage {
    my $me = shift;
    my %p  = @_;

    $me->httpheader();
    print "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\">\n";
    print "<HTML><HEAD><TITLE>$p{title}</TITLE>\n";
    print "<META HTTP-EQUIV=\"REFRESH\" CONTENT=\"$p{refresh}\">\n" if $p{refresh};
    $me->mobile_headers(0);
    print "<LINK REL=\"icon\" HREF=\"$p{icon}\" TYPE=\"image/gif\">\n" if $p{icon};
    print "<LINK REL=\"alternate\" TYPE=\"application/rss+xml\" title=\"RSS\" href=\"$p{rss}\">\n" if $p{rss};

    for my $ss ( split /\s+/, $p{style} ){
	print "<LINK REL=\"stylesheet\" TYPE=\"text/css\" HREF=\"$ss\">\n";
    }
    for my $js ( split /\s+/, $p{javascript} ){
	print "<SCRIPT TYPE=\"text/javascript\" SRC=\"$js\"></SCRIPT>\n";
    }

    print "</HEAD><BODY BGCOLOR=\"#FFFFFF\" ", ($p{bkgimg} ? "BACKGROUND=\"$p{bkgimg}\"" : ''), ">\n";
    $me->header();
}

sub top_of_table {
    my $me = shift;
    my %p  = @_;

    my $color = web_element_color('top_normal');
    print <<EOTP;
<TABLE WIDTH="100%" BORDER=0 class=$p{mainclass}>
<tr><td valign=bottom align=left class=headerbranding>$p{branding}</td>
    <td colspan=2 valign=bottom align=right class=headerargus><A HREF="$ARGUS_URL">Argus Monitoring</A></td></tr>
<TR BGCOLOR="$color"><TD COLSPAN=2>
  <TABLE BORDER=0 WIDTH="100%" CLASS=TOPBAR>
    <TR> <TD ALIGN=LEFT class=objectname>$p{title}</TD>
EOTP
    ;
    if( $me->{auth}{user} ){
        my $l_user = l10n('User');
        print "<TD ALIGN=RIGHT class=username>$l_user: <TT>$me->{auth}{user}</TT></TD>\n";
    }else{
        print "<TD></TD>\n";
    }
    print "</TR></TABLE></TD></TR>\n";

}

sub bot_of_table {
    my $me = shift;

    print "</TABLE>\n";

}

sub endpage {
    my $me = shift;

    $me->footer();
    print $me->{q}->end_html;
}

sub error {
    my $me  = shift;
    my $msg = shift;
    my $faq = shift;
    my $a;

    $a = "<A HREF=\"$ARGUS_URL/faq.html#$faq\"><I>please explain</I></A>"
	if $faq;

    my $color = web_element_color('top_error');
    $me->startpage(title => "ERROR", refresh => 60) unless $me->{header};
    print <<EOW;
    <TABLE BORDER=0 BGCOLOR="$color" WIDTH="100%" cellspacing=0 cellpadding=5><TR><TD>
    <TABLE><TR><TD>
    <H2>ERROR&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</H2>
    $a
    </TD><TD>
    $msg
    </TD></TR></TABLE>
    </TD></TR></TABLE>
EOW
    ;
    $me->endpage();
    my $obj = $me->{q}->param('object');
    print STDERR "[$$] ($me->{auth}{user} $obj) ERROR: $msg\n";
    die;
}

sub warning {
    my $me  = shift;
    my $msg = shift;
    my $faq = shift;
    my( $a, $url );

    $a = "<A HREF=\"$ARGUS_URL/faq.html#$faq\"><I>please explain</I></A>"
	if $faq;
    $url = $me->{q}->url() . "?func=logfile;abridge=1";
    my $color = web_element_color('top_error');

    print <<X;
    <TABLE BGCOLOR="$color" WIDTH="100%" cellspacing=0 cellpadding=5><TR><TD>
    <TABLE cellspacing=0 cellpadding=0><TR><TD>
    <H2>Warning&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</H2>
    $a
    </TD><TD>
    $msg
    <P>Examine the <A HREF="$url">Error Log</A> for details
    </TD></TR></TABLE>
    </TD></TR></TABLE>
X
    ;
}

# Mozilla/5.0 (iPhone; CPU iPhone OS 5_0 like Mac OS X) AppleWebKit/534.46 (KHTML, like Gecko) Version/5.1 Mobile/9A334 Safari/7534.48.3
# Mozilla/5.0 (Linux; U; Android 3.2.2; en-us; Xoom Build/HLK75D) AppleWebKit/534.13 (KHTML, like Gecko) Version/4.0 Safari/534.13
# Opera/9.80 (iPhone; Opera Mini/6.5.22931/26.1069; U; en) Presto/2.8.119 Version/10.54

sub is_mobile {

    my $ua = $ENV{HTTP_USER_AGENT};
    return 1 if $ua =~ /iphone|android/i;
    return ;
}

sub mobile_headers {
    my $me = shift;
    my $hard = shift;

    return unless is_mobile();

    print qq(<meta name="format-detection" content="telephone=no">\n);
    if( $hard ){
        print qq(<meta name="viewport" content="width=640, user-scalable=no">\n);
    }else{
        print qq(<meta name="viewport" content="width=640">\n);
    }
}


sub header {}
sub footer {}

sub makecookie {
    my $me = shift;

    $me->{q}->cookie(-name    => $COOKIENAME,
                     -value   => $me->{co},
                     -expires => '+1M',
                     );
}

# this is needed to avoid problem with IE and redirecting from a POST
sub heavy_redirect {
    my $me  = shift;
    my $url = shift;

    $me->httpheader();
    print "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\">\n";
    print "<HTML><HEAD><TITLE>Redirecting...</TITLE>\n";
    print "<META HTTP-EQUIV=\"REFRESH\" CONTENT=\"0; URL=$url\">\n";
    print "</HEAD><BODY BGCOLOR=\"#FFFFFF\">\n";
#     print "<I>Redirecting to <A HREF=$url>Next Page</A></I>...\n";
    print "</BODY></HTML>\n";
    $me->{header} = 1;
}

sub light_redirect {
    my $me  = shift;
    my $url = shift;

    return $me->heavy_redirect( $url ) if $me->{co};

    print $me->{q}->redirect( $url );
    $me->{header} = 1;
}

my $warned_about_random = 0;
sub new_cookie {
    return random_cookie(64);
}

1;

