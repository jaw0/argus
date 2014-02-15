# -*- perl -*-

# Copyright (c) 2005 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2005-Dec-10 12:55 (EST)
# Function: 
#
# $Id: web_login.pl,v 1.7 2012/09/03 15:24:54 jaw Exp $

package Argus::Web;
use strict;
use vars qw($argusd %auth);

sub web_logout {
    my $me = shift;

    if( $me->{ci} ){
	delete $auth{$me->{ci}};
	sync_db();
    }
    $me->{co} = 'invalid';
    $me->heavy_redirect( $me->{q}->url() );
}

sub authenticate {
    my $me   = shift;
    my $user = shift;
    my $pass = shift;

    my @a;
    if( !defined &auth_user ){
	# no auth function. allow access.
	@a = ('Top', 'root', 'staff', 'user' );
	$user = 'webanon';
    }else{
	expire_auth();
	@a = auth_user( $user, $pass );
    }
    if( @a ){
	$me->create_auth( $user, @a );
	return ( $user, @a );
    }
    return ;
}

sub web_login {
    my $me = shift;
    my $q  = $me->{q};
    
    my $user = $q->param('name');

    unless( $user ){
	$me->web_login_form();
	return ;
    }
    
    my @a = $me->authenticate( $user, $q->param('passwd') );

    unless(@a){
	my $emsg = l10n('Authentication Failed');
	$me->web_login_form($emsg);
	return ;
    }

    my $param;
    my $next = $q->param('next');

    if( $next ){
        $param = $next;
    }else{
        my($home, $top);
        if( $q->param('home') ){
            $home = $q->param('home');
            $top  = $q->param('top');
        }else{
            $home = $a[1];
            $top  = 1;
        }
        $param = "object=$home;func=page;top=$top";
    }
    return $me->heavy_redirect( $me->{q}->url() . "?$param");
}

sub web_login_form {
    my $me = shift;
    my $emsg = shift;
    my( $q, $r );

    $q = $me->{q};
    $r = $argusd->command( func => 'logindata' ) || {};
    # no error if we fail to connect

    $me->startpage( title  => l10n('Login'),
		    bkgimg => decode($r->{bkgimg}),
		    style  => decode($r->{style_sheet}),
		    icon   => decode($r->{icon}) );

    print decode($r->{"header"}), "\n";
    $me->top_of_table( title     => l10n("Please log in"),
                       mainclass => 'loginmain',
                       branding  => decode($r->{branding}) );

    print "<TR><TD VALIGN=TOP>\n";
    print "<H2><FONT COLOR=\"#FF0000\">", l10n('ERROR'), ": $emsg</FONT></H2>\n" if $emsg;
    print "<TABLE WIDTH=\"95%\" cellspacing=0 cellpadding=5>\n<TR><TD VALIGN=TOP>\n";

    print $q->startform(), "\n";
    print "<INPUT TYPE=HIDDEN NAME=func VALUE=login>\n";
    print "<INPUT TYPE=HIDDEN NAME=next VALUE=\"", $q->param('next'), "\">\n";
    print "<TABLE>\n";
    print "<TR><TH>", l10n("Username"), ": </TH><TD>", $q->textfield('name', '', 32, 32), "</TD></TR>\n";
    print "<TR><TH>", l10n("Password"), ": </TH><TD>", $q->password_field('passwd', '', 32, 32), "</TD></TR>\n";
    print "<TR><TD COLSPAN=2>", $q->submit(-name=>l10n('Login')), "</TD></TR>\n";
    print "</TABLE><P>\n";
    print $q->endform(), "\n";
    print "</TD></TR></TABLE>\n";

    print "</TD></TR>\n";
    $me->bot_of_table();
    print decode($r->{footer}), "\n";
    $me->endpage();
}


1;
