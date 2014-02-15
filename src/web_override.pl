# -*- perl -*-

# Copyright (c) 2005 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2005-Dec-10 12:50 (EST)
# Function: cgi override functions
#
# $Id: web_override.pl,v 1.6 2011/10/31 04:16:59 jaw Exp $

package Argus::Web;
use strict;
use vars qw($argusd);

sub web_override {
    my $me = shift;
    my( $q, $st, $r, $obj );
    
    $obj = decode( $me->{q}->param('object') );
    return unless $me->check_acl_func($obj, 'override', 1);
    $q = $me->{q};
    
    if( $q->param('phase') ){
	my( $mode, $txt );

	$mode = $q->param('mode');
	
	# check params
	if( $mode !~ /^(manual|auto)$/ ){
	    return $me->error( "invalid mode" );
	}

	if( $me->can('override_policy') ){
	    return unless $me->override_policy();
	}
		
	$txt = $q->param('text');
	$txt =~ s/</&lt\;/g;
	$txt =~ s/>/&gt\;/g;
	
    	$r = $argusd->command( func => 'override',
			       object => encode($obj),
			       user => $me->{auth}{user},
			       text => encode($txt),
			       mode => $mode,
			       expires => $q->param('expires') ? ($^T + $q->param('expires')) : 0,
			       ticket => encode($q->param('ticket')),
			       );
	return $me->error( "unable to connect to server" ) unless $r;
	return $me->error( "Unable to access <I>$obj</I><BR>$r->{resultcode} $r->{resultmsg}" )
	    unless $r->{resultcode} == 200;

	return $me->light_redirect( $q->url() . "?object=" . $q->param('object') . ";func=page" );
    }
    
    $me->startpage( title => l10n("Override") . " $obj" );
    $st = get_status($obj);
    my $tkt = $argusd->command( func => 'use_tkt', object => encode($obj) );

    print $q->startform(-method=>'get'), "\n";
    print "<INPUT TYPE=HIDDEN NAME=func VALUE=override>\n";
    print "<INPUT TYPE=HIDDEN NAME=phase VALUE=1>\n";
    print "<INPUT TYPE=HIDDEN NAME=object VALUE=", encode($obj), ">\n";
    print l10n("Comment"), ": ", $q->textfield('text', '', 50), "<BR>\n";
    print l10n("Mode"),    ": ", $q->popup_menu('mode', [ 'auto', 'manual' ],
                                   ($st eq 'up' ? 'manual' : 'auto') ), "<BR>";

    print l10n("Ticket No."), ": ", $q->textfield('ticket', '', 16), "<BR>"
	if $tkt->{resultcode} == 200;

    my %exp = (
            0             => 'never',
            15 * 60       => '15 min',
            30 * 60       => '30 min',
            60 * 60       => '1 hour',
            2  * 60 * 60  => '2 hours',
            3  * 60 * 60  => '3 hours',
            4  * 60 * 60  => '4 hours',
            6  * 60 * 60  => '6 hours',
            8  * 60 * 60  => '8 hours',
            12 * 60 * 60  => '12 hours',
            18 * 60 * 60  => '18 hours',
            24 * 60 * 60  => '24 hours',
            36 * 60 * 60  => '36 hours',
            2 * 24 * 60 * 60   => '2 days',
            3 * 24 * 60 * 60   => '3 days',
            4 * 24 * 60 * 60   => '4 days',
            5 * 24 * 60 * 60   => '5 days',
            7 * 24 * 60 * 60   => '7 days',
            10 * 24 * 60 * 60  => '10 days',
            14 * 24 * 60 * 60  => '14 days',
            20 * 24 * 60 * 60  => '20 days',
            30 * 24 * 60 * 60  => '30 days',
            45 * 24 * 60 * 60  => '45 days',
            );
    
    print l10n("Expires"), ": ", $q->popup_menu('expires',
                                      [ sort {$a<=>$b} keys %exp ], 4 * 60 * 60, \%exp );
    print "<P>\n";
    print $q->submit(), "\n";
    print $q->endform(), "\n";
    print "<HR>\n<I>NB:";
    print l10n("auto mode - disengage override when status returns to up"), "<BR>\n";
    print l10n("manual mode - require override be disengaged manually"), "<BR>\n";

    # QQQ - include note that javascript is not properly installed/configured?

    $me->endpage();
}

sub web_rmoverride {
    my $me = shift;
    my( $r, $obj );
    
    $obj = decode( $me->{q}->param('object') );
    return unless $me->check_acl_func($obj, 'override', 1);

    if( $me->can('override_policy') ){
	return unless $me->override_policy();
    }

    $r = $argusd->command( func => 'override',
			   object => encode($obj),
			   remove => 'yes',
			   user => $me->{auth}{user},
			   );
    return $me->error( "unable to connect to server" ) unless $r;
    return $me->error( "Unable to access <I>$obj</I><BR>$r->{resultcode} $r->{resultmsg}" )
	unless $r->{resultcode} == 200;
    
    return $me->heavy_redirect( $me->{q}->url() . "?object=" . $me->{q}->param('object') . ";func=page" );
}

sub web_annotate {
    my $me = shift;
    my( $obj, $r, $q );

    $obj = decode( $me->{q}->param('object') );
    return unless $me->check_acl_func($obj, 'annotate', 1);
    if( $me->{q}->param('phase') ){
	my $txt = $me->{q}->param('text');
	$txt =~ s/</&lt\;/g;
	$txt =~ s/>/&gt\;/g;
	$r = $argusd->command( func => 'annotate',
			       object => encode($obj),
			       user => $me->{auth}{user},
			       text => encode($txt),
			       );
	return $me->error( "unable to connect to server" ) unless $r;
	return $me->error( "Unable to access <I>$obj</I><BR>$r->{resultcode} $r->{resultmsg}" )
	    unless $r->{resultcode} == 200;

	return $me->light_redirect( $me->{q}->url() . "?object=" . $me->{q}->param('object')
				    . ";func=page");
    }
    
    $me->startpage( title => l10n("Annotate") . " $obj" );
    $q = $me->{q}; 

    print $q->startform(-method=>'get'), "\n";
    print "<INPUT TYPE=HIDDEN NAME=func VALUE=annotate>\n";
    print "<INPUT TYPE=HIDDEN NAME=phase VALUE=1>\n";
    print "<INPUT TYPE=HIDDEN NAME=object VALUE=", encode($obj), ">\n";
    print l10n("Annotation"), ": ", $q->textfield('text', '', 32, 64), "<BR>\n";

    # QQQ - include note that javascript is not properly installed/configured?

    print $q->submit(), "\n";
    print $q->endform(), "\n";
    $me->endpage();
}

sub get_status {
    my $obj = shift;
    my( $r );

    $r = $argusd->command( func => 'getparam',
			   object => encode($obj),
			   param => 'ovstatus'
			   );
    return $r->{value} if $r && $r->{value};
    undef;
}
    
1;
