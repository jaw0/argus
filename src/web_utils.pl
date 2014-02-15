# -*- perl -*-

# Copyright (c) 2005 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2005-Dec-11 11:37 (EST)
# Function: 
#
# $Id: web_utils.pl,v 1.4 2011/10/30 21:00:29 jaw Exp $

package Argus::Web;
use strict;
use vars qw($argusd);

sub web_getconf {
    my $me = shift;
    my( $obj, $r, $k, $v );

    $obj  = decode( $me->{q}->param('object') );
    return unless $me->check_acl_func($obj, 'getconf', 1);
    my $rd = $argusd->command( func => 'logindata' ) || {};
    return $me->error( "unable to connect to server" ) unless $rd;

    $me->startpage(title  => "Config: $obj",
                   bkgimg => decode($rd->{bkgimg}),
                   style  => decode($rd->{style_sheet}),
                   icon   => decode($rd->{icon}) );

    print decode($rd->{"header"}), "\n";
    $me->top_of_table( title     => "Config: $obj",
                       mainclass => 'aboutmain',
                       branding  => decode($rd->{branding}),
                      );
    print "<TR><TD VALIGN=TOP>\n";

    $r = $argusd->command_raw( func   => 'getconf',
			       object => encode($obj),
			       );
    return $me->error( "Unable to access <I>$obj</I><BR>$r" ) unless $r =~ /200/;

    print "<PRE>\n";
    while( $_ = $argusd->nextline() ){
	chop;
	last if /^$/;
	s/^-//;
	s/</\&lt\;/g;
	s/>/\&gt\;/g;
	s,((?<!\\)\#.*),<FONT COLOR=red>$1</FONT>,;
	print "$_\n";
    }
    print "</PRE>\n";

    print "</TD></TR>\n";
    $me->bot_of_table();
    print decode($rd->{footer}), "\n";

    $me->endpage();
}

sub web_flushcache {
    my $me = shift;

    my $obj = decode( $me->{q}->param('object') );
    return unless $me->check_acl_func($obj, 'flush', 1);
    my $r = $argusd->command( func   => 'flushpage',
			      object => encode($obj),
			      );
    return $me->error( "unable to connect to server" ) unless $r;
    return $me->error( "Unable to access <I>$obj</I><BR>$r->{resultcode} $r->{resultmsg}" )
	unless $r->{resultcode} == 200;

    return $me->light_redirect( $me->{q}->url() . "?object=" . $me->{q}->param('object') . ";func=page" );
}


sub web_checknow {
    my $me = shift;

    my $obj = decode( $me->{q}->param('object') );
    return unless $me->check_acl_func($obj, 'checknow', 1);
    my $r = $argusd->command( func   => 'checknow',
			      object => encode($obj),
			      );
    return $me->error( "unable to connect to server" ) unless $r;
    return $me->error( "Unable to access <I>$obj</I><BR>$r->{resultcode} $r->{resultmsg}" )
	unless $r->{resultcode} == 200;
    
    return $me->light_redirect( $me->{q}->url() . "?object=" . $me->{q}->param('object') . ";func=page" );    
}

1;
