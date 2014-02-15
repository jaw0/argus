# -*- perl -*-

# Copyright (c) 2003 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2003-Jul-29 22:53 (EDT)
# Function: speak SSL
#
# $Id: SSL.pm,v 1.10 2012/09/29 21:23:01 jaw Exp $

# based on ideas and discussions with Tim Skirivin

package SSL;
use Socket;
# versions prior to 1.09 are missing a lot of functions...
BEGIN{ eval{ require Net::SSLeay; Net::SSLeay->VERSION(1.09); $::HAVE_SSL = 1 } }

use strict qw(refs vars);

if( $::HAVE_SSL ){
  Net::SSLeay::load_error_strings();
  Net::SSLeay::SSLeay_add_ssl_algorithms();
  Net::SSLeay::randomize();
}

sub problem {
    my $me = shift;
    my $er = shift;

    ::sysproblem( "TCP/SSL $er" );
    $me->debug( $er );
    die "$er\n";
}

sub init {
    my $me = shift;
    my $i;

    $me->debug( 'SSL init' );
    my $ctx = Net::SSLeay::CTX_new();
    problem( $me, "CTX failed: $!" ) unless $ctx;
    
    $i = Net::SSLeay::CTX_set_options($ctx, Net::SSLeay::OP_ALL);
    # problem( $me, "set options failed: $!" ) if $i;

    my $ssl = Net::SSLeay::new($ctx);
    problem( $me, "new failed: $!" ) unless $ssl;
    
    $i = Net::SSLeay::set_fd($ssl, fileno($me->{fd}));
    problem( $me, "set_fd failed: $!" ) unless $i;

    $me->{tcp}{ssldata} = { ssl => $ssl, ctx => $ctx };
    $me->{srvc}{state} = 'SSL connecting';
    $me->debug( 'SSL init ok' );
    $me->wantread(1);
    $me->wantwrit(1);

    0;
}

sub cleanup {
    my $me = shift;

    # need to manually free things, otherwise we leak memory
    # this is just so anti-perl...
    Net::SSLeay::CTX_free( $me->{tcp}{ssldata}{ctx} );
    Net::SSLeay::free( $me->{tcp}{ssldata}{ssl} );
    delete $me->{tcp}{ssldata};
}

sub connect {
    my $me = shift;
    my $ssl = $me->{tcp}{ssldata}{ssl};
    my $i;

    $me->debug( 'TCP/SSL connect' );
    
    $i = Net::SSLeay::connect($ssl);
    $me->{srvc}{state} = 'SSL established';
    
    if( $i == -1 ){
	my $e = Net::SSLeay::ERR_get_error();
	my $es = Net::SSLeay::ERR_error_string($e);
	
	if( $e == Net::SSLeay::ERROR_WANT_READ() ){
	    $me->wantread(1);
	    $me->{srvc}{state} = 'SSL connecting';
	    return 1;
	}elsif( $e == Net::SSLeay::ERROR_WANT_WRITE() ){
	    $me->wantwrite(1);
	    $me->{srvc}{state} = 'SSL connecting';
	    return 1;
	}elsif( $e ){
	    problem( $me, "connect failed: $es" );
	}
    }

    $me->debug( 'TCP/SSL connect ok' );

    0;
}

sub writable {
    my $me = shift;

    if( $me->{srvc}{state} eq 'connecting' ){
	my $fh = $me->{fd};
	my $i = unpack('L', getsockopt($fh, SOL_SOCKET, SO_ERROR));
	if( $i ){
	    $! = $i;
	    # QQQ, should I try to sort out errors, down on some, sysproblem on others?
	    return $me->isdown( "TCP connect failed: $!", 'connect failed' );
	}
	
	$me->debug( 'TCP - connected' );
	eval {
	    $me->SSL::init();
	};
	if( $@ ){
	    return $me->done();
	}
	
	$me->{tcp}{wbuffer} = $me->{tcp}{altsend} || $me->{tcp}{send};
	undef $me->{tcp}{altsend};
	$me->settimeout( $me->{srvc}{timeout} );
    }
    
    if( $me->{srvc}{state} eq 'SSL connecting' ){
	my $r;
	eval {
	    $r = $me->SSL::connect();
	};
	if( $@ ){
	    return $me->isdown( $@, 'SSL error' );
	}
	# connect still in progress
	return if $r;
    }
    
    if( $me->{tcp}{wbuffer} ){
	$me->debug( "SSL writing" );
	my $ssl = $me->{tcp}{ssldata}{ssl};
	my $i = Net::SSLeay::write( $ssl, $me->{tcp}{wbuffer} );
	my $e = Net::SSLeay::ERR_get_error();
	my $es = Net::SSLeay::ERR_error_string($e);
	# $me->debug( "SSL wrote $i/$e" );
	
	if( $i > 0 || ! $e ){
	    $me->debug( "SSL - wrote $i bytes" );
	}else{
	    unless( $e == Net::SSLeay::ERROR_WANT_WRITE() || $e == Net::SSLeay::ERROR_WANT_READ() ){
		return $me->isdown( "SSL write failed: $es", 'write failed' );
	    }
	}
	
	if( Net::SSLeay::want_write($ssl) ){
	    $me->wantwrit(1);
	}else{
	    $me->wantwrit(0);
	}
    }else{
	$me->wantwrit(0);
    }

    return;
}

sub readable {
    my $me = shift;
    my( $fh, $ssl, $i, $l, $e, $es, $testp );

    $fh = $me->{fd};

    if( $me->{srvc}{state} eq 'SSL connecting' ){
	return 0 if $me->SSL::connect();
    }

    if( $me->{srvc}{state} eq 'SSL connecting' ){
	return 0 if $me->SSL::connect();
    }
    $ssl = $me->{tcp}{ssldata}{ssl};
    $i  = Net::SSLeay::read( $ssl );
    $e  = Net::SSLeay::ERR_get_error();
    $es = Net::SSLeay::ERR_error_string($e);

    # And this is the writing that was written: MENE, MENE, TEKEL, UPHARSIN.
    #   -- daniel 5:25
    if( $i ){
	$me->debug( "SSL - read data $i" );
	$me->{tcp}{rbuffer} .= $i;
    }
    elsif( defined($i) ){
        # And it came to pass, when Moses had made an end of writing ...
	#   -- dueteronomy 31:24
	# $i is 0 -> eof
	$me->debug( 'SSL - read eof?' );
	$testp = 1;
    }
    elsif( ! $e ){
	$me->debug( 'SSL - read nothing, try again' );
	# no data, no error, keep going
    }
    else{
	# $i is undef -> error
	return $me->isdown( "SSL read failed: $es", 'read failed' );
    }

    if( $me->{tcp}{readhow} eq 'banner' ){
	# My ears have not yet drunk a hundred words
	# Of that tongue's utterance, yet I know the sound:
	#   -- Shakespeare, Romeo+Juliet
	if( $me->{tcp}{rbuffer} =~ /\n/ ){
	    $me->debug( "banner" );
	    $testp = 1;
	}
    }
    elsif( $me->{tcp}{readhow} eq 'once' ){
	$me->debug( "once" );
	$testp = 1;
    }
    elsif( $me->{tcp}{readhow} eq 'toeof' ){
	# $testp = 0;
    }
    elsif( $me->{tcp}{readhow} > 0 ){
	# if readhow is a number, read at least that many bytes
	if( length($me->{tcp}{rbuffer}) >= $me->{tcp}{readhow} ){
	    $me->debug( "bytes" );
	    $testp = 1;
	}
    }

    if( $testp ){
	return $me->test();
    }else{
	# kibbles and bits, kibbles and bits, give me more kibbles and bits
	#   -- Dog Food Commercial
	$me->wantread(1);
    }
}


1;
