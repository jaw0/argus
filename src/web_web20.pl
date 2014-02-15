# -*- perl -*-

# Copyright (c) 2007 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2007-Jan-14 12:10 (EST)
# Function: json + rss output for integration with other apps
#
# $Id: web_web20.pl,v 1.3 2008/02/04 04:56:21 jaw Exp $

package Argus::Web;
use strict;
use vars qw($argusd $VERSION);

# A lord of Trojan blood, nephew to Hector;
# They call him Ajax.
#   -- Shakespeare, troilus And Cressida

sub web_summary {
    my $me = shift;
    
    # RSN - other formats?
    web_summary_json($me);
}

# Were not so wonder-struck as you shall be,
# When Jason they beheld a ploughman made!
#   -- Dante, Divine Comedy
sub web_summary_json {
    my $me = shift;

    my $obj  = decode( $me->{q}->param('object') );

    # And when they had taken security of Jason, and of the other, they let them go.
    #   -- Act 17:9
    return unless $me->check_acl_func($obj, 'page', 1);
    
    my $r = $argusd->command( func => 'summary',
			      object => encode($obj)
			      );

    # Ajax was wrecked, for Neptune drove him on to the great rocks of Gyrae
    #   -- Homer, Odyssey
    return $me->error( "unable to connect to server" ) unless $r;
    return $me->error( "Unable to access <I>summary data</I><BR>$r->{resultmsg}" ) unless $r->{resultcode} =~ /200/;

    $me->{header} = 1;

    print <<EOPAGE;
Content-Type: text/javascript

{ status: '$r->{status}', up: $r->{up}, down: $r->{down}, override: $r->{override}, total: $r->{total} }
EOPAGE
    ;

}

# Sit down and feed, and welcome to our table.
#   -- Shakespeare, As You Like It
sub web_notify_rss {
    my $me = shift;

    return unless $me->check_acl_func('Top', 'ntfylist', 1);
    my $q = $me->{q};
    my $url = $q->url();

    my $r = notify_list_data($me, 0);

    return $me->error( "unable to connect to server" ) unless $r;
    return $me->error( "Unable to access <I>notify list</I><BR>$r->{error}" ) if $r->{error};


    print "Content-Type: application/xml\n\n";
    $me->{header} = 1;
    print <<EOCHAN;
<?xml version="1.0"?>
<rss version="2.0">
   <channel>
      <title>Argus Notifications</title>
      <link>$url/?func=ntfylist</link>
      <description>Argus Notifications</description>
      <generator>Argus $VERSION</generator>
      <ttl>2</ttl>
EOCHAN
    ;

    # Throw me in the channel!
    #   -- Shakespeare, 2 king Henry IV
    foreach my $nd (@{$r->{data}}){
	my $dt  = strftime "%a, %d %b %Y %R %z", localtime($nd->{create});
	my $obj = decode($nd->{obj});
	my $msg = decode($nd->{msg});
	my $id  = $nd->{id};

	print <<EOITEM;
      <item>
  	<guid>$id</guid>
  	<pubDate>$dt</pubDate>
  	<link>$url?func=ntfydetail;idno=$id</link>
  	<description>$msg</description>
      </item>
EOITEM
    ;
	
    }

    print "  </channel>\n</rss>\n";
}

# We are the Jasons, we have won the fleece.
#   -- Shakespeare, Merchant of Venice
sub web_notify_json {
    my $me = shift;

    return unless $me->check_acl_func('Top', 'ntfylist', 1);
    my $q = $me->{q};
    my $url = $q->url();

    my $r = notify_list_data($me, 0);

    return $me->error( "unable to connect to server" ) unless $r;
    return $me->error( "Unable to access <I>notify list</I><BR>$r->{error}" ) if $r->{error};


    print "Content-Type: text/javascript\n\n";
    $me->{header} = 1;

    print "[\n";
    my $n;

    foreach my $nd (@{$r->{data}}){
	my $dt = strftime "%Y-%m-%dT%T", localtime($nd->{create}); # QQQ
	my $obj = decode($nd->{obj});
	my $msg = decode($nd->{msg});
	my $id  = $nd->{id};

	print ",\n" if $n++;
	# That," answered Helen, "is huge Ajax"
	#   -- Homer, Iliad
	print "\t{ id: $id, time: '$dt', timet: $nd->{create}, status: '$nd->{status}', state: '$nd->{state}', priority: '$nd->{prio}', severity: '$nd->{seve}', object: '$obj', msg: '$msg' }";
	
    }

    print "\n" if $n;
    print "]\n";

}


1;
