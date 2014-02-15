# -*- perl -*-

# Copyright (c) 2003 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2003-Jan-16 22:43 (EST)
# Function: Monitor Object - for reporting Errors
#
# $Id: Error.pm,v 1.8 2011/10/30 21:00:29 jaw Exp $

# Error is the force that welds men together
#   -- Tolstoy, My Religion

package Error;
@ISA = qw(MonEl);
use Argus::Color;
use strict qw(refs vars);
use vars qw(@ISA $doc);

$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [@ISA],
    methods => {},

    fields => {
      error::status => {
	  attrs => ['config'],
	  default => 'down',
      },
      error::error => {
	  attrs => ['config'],
      },
	
    },
};


sub config {
    my $me = shift;
    my $cf = shift;
    
    $me->{transient} = 1;
    $me->init_from_config( $cf, $doc, 'error' );
    return undef unless $me->init($cf);

    # up | down only
    $me->{error}{status} = 'down' unless $me->{error}{status} eq 'up';
    
    $me->{status} = $me->{ovstatus} =
	$me->{prevstatus} = $me->{prevovstatus} =
	$me->{error}{status};
    
    $me->{web}{showstats} = 0;

    $me;
}

sub transition {
    my $me = shift;
    my $st = shift;
    my $sv = shift;
    
    $me->{currseverity} = ($me->{status} eq 'down') ? ($sv || $me->{severity}) : 'clear'; 
    $me->{alarm}        = (($me->{status} eq 'down') && $me->{siren}) ? 1 : 0;
    $me->transition2();
    $me->{ovstatussummary} = { $me->{ovstatus} => 1, total => 1, severity => $me->{currseverity} };
    
    $me->transition_propagate();
}

sub jiggle {
    my $me = shift;

    $me->transition();
}

sub webpage {
    my $me = shift;
    my $fh = shift;
    my( $k, $v, $x, $kk );

    print $fh "<!-- start of Error::webpage -->\n";
    
    # object data
    print $fh "<TABLE CLASS=ERRORDATA>\n";
    foreach $k (qw(name ovstatus error warning info note comment annotation details)){
	$v  = $me->{$k};
	$kk = $k;
	$x  = '';
	if( $k eq 'ovstatus' ){
	    $x  = ' BGCOLOR="' . web_status_color($me->{ovstatus}, $me->{severity}, 'back') . '"';
	    $kk = 'status';
	    $v  = 'ERROR';
	}
	if( $k eq 'error' ){
	    $kk = '<B><L10N ERROR></B>';
	    $v  = $me->{error}{error};
	}
	
	print $fh "<TR><TD>$kk</TD><TD$x>$v</TD></TR>\n" if defined($v);
    }
    
    $me->webpage_more($fh) if $me->can('webpage_more');
    print $fh "</TABLE>\n";

    $me->web_override($fh);
    
    print $fh "<!-- end of Error::webpage -->\n";
}


sub web_page_row_base {
    my $me = shift;
    my $fh = shift;
    my $label = shift;
    
    return if $me->{web}{hidden};
    my $st = $me->{status};
    my $cl = web_status_color($st, $me->{currseverity}, 'back');

    if( $st eq 'up' ){
	print $fh "<TR><TD><A HREF=\"", $me->url('func=page'), "\">",
        ($label||$me->{label_left}||$me->{name}), "</A></TD>";
	print $fh "<TD BGCOLOR=\"$cl\"><L10N ERROR></TD><TD></TD><TD></TD>";
	
    }else{
	print $fh "<TR><TD BGCOLOR=\"$cl\"><A HREF=\"", $me->url('func=page'), "\">",
        ($label||$me->{label_left}||$me->{name}), "</A></TD>";
	print $fh "<TD></TD><TD BGCOLOR=\"$cl\"><L10N ERROR></TD><TD></TD>";
    }
    print $fh "</TR>\n";
}

sub about_more {
    my $me = shift;
    my $ctl = shift;

    $me->more_about_whom($ctl, 'error');
}

################################################################
Doc::register( $doc );

1;
