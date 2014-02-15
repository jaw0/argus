# -*- perl -*-

# Copyright (c) 2005 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2005-Dec-10 12:53 (EST)
# Function: cgi main page display
#
# $Id: web_page.pl,v 1.9 2012/10/02 01:38:26 jaw Exp $

package Argus::Web;
use strict;
use vars qw($argusd $WEBCACHE);

# Let them eat cake!
my $CAKESTALE = 120;

sub web_page {
    my $me = shift;
    my( $r, $file, $warning, $siren_icon, $cached );

    my $cakestale = $CAKESTALE;
    my $obj  = decode( $me->{q}->param('object') );
    my $topp = $me->{q}->param('top');
    my $url  = $me->{q}->url( -path_info => 1 );
    my $user = $me->{auth}{user};
    my $home = $me->{auth}{home};

    $r = $argusd->command( func => 'webpage',
			   object => encode($obj),
			   top => ($topp?'yes':'no'),
			   );
    if( !$r ){
	# try again
	print STDERR "[$$] connect to argusd failed\n";
	reconnect();
	$r = $argusd->command( func => 'webpage',
			       object => encode($obj),
			       top => ($topp?'yes':'no'),
			       );
    }
    if( !$r ){
	# could not connect to server, try to serve cached data
	print STDERR "[$$] connect to argusd failed (again)\n";
	my $enc = encode($obj);
	$file = "$WEBCACHE/" . hashed_directory($enc) . "/$enc";
	$file .= ($topp? '.top' : '.base') if $obj =~ /^Top/;

	if( -f $file ){
	    # Soon her eye fell on a little glass box that was lying under
	    # the table:  she opened it, and found in it a very small cake, on
	    # which the words `EAT ME' were beautifully marked in currants
	    #   -- Alice in Wonderland
	    $cached = (stat($file))[9];
	    open( F, $file ) || return $me->error( "could not open file: $!" );

	    # only warn if cache is more than several minutes old (see below)
	    $warning = "<B>Unable to contact server - using cached data - please investigate</B>\n" .
	        "<BR>Cached: " . l10n_localtime($cached) .
	        "<BR>\n";
	}else{
	    return $me->error( "unable to connect to server<BR><I>checking cache...</I>" .
			       "unable to locate cached data<BR><B>ABORTING</B>",
			       'aborting'
			       );
	}
    }else{
	# all is good
	$file = $r->{file};
	return $me->error( "Unable to access <I>$obj</I><BR>$r->{resultcode} $r->{resultmsg}" ) unless $file;
	open( F, $file ) || return $me->error( "could not open file: $!" );
    }

    my $unackedclass = $r->{unacked} ? 'ATTNBUTTON' : 'BUTTON';
    my $numunacked   = $r->{unacked} ? " ($r->{unacked})" : '';

    $me->httpheader();
    while( <F> ){

	s/__BASEURL__/$url/g;
	s/__USER__/$user/g;
	s/__TOP__/$home\;top=1/g;
        s/__UNACKEDCLASS__/$unackedclass/g;
        s/__NUMUNACKED__/$numunacked/g;
	s/<LOCALTIME\s+(\d+)\s*>/l10n_localtime($1)/ge;
	s/<L10N\s+([^<>]+)\s*>/l10n($1)/ge;

	if( /cachestale: (\d+)/ ){
	    $cakestale = $1;
	    next;
	}

        if( /PUT HEADERS HERE/ ){
            $me->mobile_headers(1);
            next;
        }

	if( /PUT WARNINGS HERE/ && $cached && $cached + $cakestale < $^T ){
	    # He brought a Grecian queen, whose youth and freshness
	    # Wrinkles Apollo's, and makes stale the morning.
	    #   -- Shakespeare, Troilus And Cressida
	    print;
            if( $warning ){
                print "<tr class=warning><td colspan=3>\n";
                $me->warning( $warning );
                print "</td></tr>\n";
                $warning = '';
            }
	    next;
	}

        # Is it for you to ravage seas and land,
        # Unauthoriz'd by my supreme command?
	#   -- Virgil, Aeneid

	next if /END AUTHORIZATION/;

	if( /START AUTHORIZATION READ NEEDED (.*) --/ ){
	    next if $me->check_acl( $1 );
	    $me->web_acl_error( 'page' );
	    while( <F> ){
		last if /END AUTHORIZATION READ NEEDED/;
	    }
	    next;
	}

	if( /START AUTHORIZATION RW NEEDED (.*) --/ && ! $me->check_acl( $1 ) ){
	    while( <F> ){
		last if /END AUTHORIZATION RW NEEDED/;
	    }
	    next;
	}
	if( /START AUTHORIZATION DEBUG NEEDED (.*) --/ && ! $me->check_acl( $1 ) ){
	    while( <F> ){
		last if /END AUTHORIZATION DEBUG NEEDED/;
	    }
	    next;
	}
	if( /START AUTHORIZATION CONF NEEDED (.*) --/ && ! $me->check_acl( $1 ) ){
	    while( <F> ){
		last if /END AUTHORIZATION CONF NEEDED/;
	    }
	    next;
	}

	next if /START AUTHORIZATION/;

	if( /START SIRENBUTTON (\d+)/ ){
	    if( $1 < $me->{auth}{hush} ){
		# They've taken of his buttons off an' cut his stripes away
		#   -- Kipling
		while( <F> ){
		    last if /END SIRENBUTTON/;
		}
	    }
	    next;
	}
	next if /END SIRENBUTTON/;

	if( /START SIREN (\d+) (.*) / ){
	    # (sirentime, sirensong)
	    my $s = $2;
	    if( $1 < $me->{auth}{hush} ){
		# Therefore pass these Sirens by, and stop your men's
		# ears with wax that none of them may hear
		#   -- Homer, Odyssey
		$siren_icon = 1;
	    }else{
		my $ua = $ENV{HTTP_USER_AGENT};
		# we had got within earshot of the land, and the ship was going at a
		# good rate, the Sirens saw that we were getting in shore and began
		# with their singing.
		#   -- Homer, Odyssey
		if( $ua =~ /MSIE/ ){
		    print qq{<BGSOUND SRC="$s">\n};
		}elsif( $ua =~ /Safari/ ){
		    print qq{<embed src="$s" hidden="true" autostart="true"></embed>\n};
		}else{
		    print qq{<OBJECT DATA="$s" TYPE="audio/x-wav" HEIGHT=0></OBJECT>\n};
		}
	    }

	    next;
	}
	if( /SIREN ICON/ && !$siren_icon ){
	    next;
	}

	print;
    }
    close F;

}

1;
