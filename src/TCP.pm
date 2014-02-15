# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Apr-03 15:59 (EST)
# Function: testing of TCP services
#
# $Id: TCP.pm,v 1.92 2012/12/02 22:21:40 jaw Exp $


package TCP;
use Argus::Encode;
use SSL;
use DNS::TCP;
use Argus::SIP::TCP;
use Argus::RPC::TCP;
use Argus::IP;

use Fcntl;
use Socket;
use POSIX qw(:errno_h);
BEGIN {
    eval { require Socket6; import Socket6; };
}

@ISA = qw(Service Argus::IP);

use strict qw(refs vars);
use vars qw(@ISA $doc);

$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [qw(Service MonEl BaseIO)],
    methods => {},
    html   => 'services',
    fields => {
      tcp::port => {
	  descr => 'TCP port to test',
	  attrs => ['config'],
      },

      tcp::send => {
	  descr => 'text to send once connected',
	  attrs => ['config'],
      },
      tcp::url => {
	  descr => 'url to check',
	  attrs => ['config'],
	  exmpl => 'http://www.example.com/cgi-bin/shopping.pl',
      },
      tcp::browser => {
	  descr => 'browser spoofing for URL checks',
	  attrs => ['config', 'inherit'],
	  exmpl => 'Mozilla/1.0 (compatible; MSIE 1.0; Windblows 19100; Argus Test)',
      },
      tcp::referer => {
	  descr => 'referer spoofing for URL checks',
	  attrs => ['config', 'inherit'],
	  versn => '3.2',
	  exmpl => 'http://argus.tcp4me.com/',
      },
      tcp::http_version => {
	  descr => 'http version',
	  attrs => ['config', 'inherit'],
	  versn => '3.7',
	  exmpl => '1.1',
      },
      tcp::http_accept => {
	  descr => 'http accept header',
	  attrs => ['config', 'inherit'],
	  versn => '3.7',
	  exmpl => '*/*',
      },

      tcp::readhow => {
	  descr => 'how much data should be read from the server before checking expect',
	  attrs => ['config'],
	  vals  => ['banner', 'toeof', 'once'],
      },
      tcp::ssl => {
	  descr => 'communicate over a SSL/TLS session',
	  attrs => ['config', 'bool'],
	  versn => '3.3',
      },

      tcp::altsend => {
	  descr => 'text to send once connected, instead of normal value',
	  # used by redirect handler
      },
      tcp::rbuffer => {
	  descr => 'read buffer',
      },
      tcp::wbuffer => {
	  descr => 'write buffer',
      },
      tcp::redircount => {
	  descr => 'number of times we have gotten an HTTP redirect',
	  # to do simplistic redirect loop detection
      },
      tcp::ssldata => { descr => 'internal SSL state' },
      tcp::build   => {},
    },

};

my %config =
(

 SMTP   => {
     # send   => "MAIL\r\n",  # not RFC compliant, but quiets sendmails logs
     port   => 25,	expect => '^220',	readhow => "banner",
 },

 FTP    => {
     port   => 21,	expect => '^220',	readhow => "banner",
 },

 POP    => {
     port   => 110,	expect => '^\+OK',	readhow => "banner",
 },

 NNTP   => {
     port   => 119,	expect => '^200',	readhow => "banner",
 },

 HTTP   => {
     port   => 80,
     # send gets built below
     expect => "HTTP/",				readhow => "toeof",
 },

 # this is different than HTTP--it tests the content of a page
 # and will follow (to limited extent) http redirects
 # and can do browser spoofing (browser: Mozilla/4.0...)
 URL   => {
     expect => "HTTP/[0-9\.]+ 200",		readhow => 'toeof',
 },

 Telnet => {
     port => 23,
 },

 Gopher => {
     port => 70,
     send => "\r\n",
     expect  => "\.\r\n",			readhow => 'toeof',
 },

 SSH => {
     port => 22,                                readhow => 'banner',
     send => "SSH-1.99-argus\r\n",
     expect => '^SSH',
 },

 IMAP => {
     port => 143, expect => '^\* OK',           readhow => 'banner',
 },

 SSL => {
     port => 443, 				ssl => 1,
     expect => "HTTP/",				readhow => "toeof",
 },
 HTTPS => {
     port => 443,				ssl => 1,
     expect => "HTTP/",				readhow => "toeof",
 },

 Whois => {
     port => 43, send => "\r\n",
 },

  Rwhois => {
     port   => 4321, expect => '^%rwhois', readhow => "banner",
 },

 NFS => {
     port => 2049, readhow => 'once',
     send => pack( "CCn NN NN NN x16", 0x80, 0, 40, $$, 0,  2, 100003, 2, 0),
     # fragment header, xid, type, rpcver, prog, ver, func, cred(flavor, len, null), verf(flavor, len, null)
 },
 NFSv3 => {
     port => 2049, readhow => 'once',
     send => pack( "CCn NN NN NN x16", 0x80, 0, 40, $$, 0,  3, 100003, 2, 0),
     #                                                      ^
 },

 LPD => {
     # lpd must be configured to permit connections from non-reserved ports
     port => 515, readhow => 'toeof', send => "\3lp\n",
 },

 POPS  => {
     port   => 995,	expect => '^\+OK',	readhow => "banner",
     ssl    => 1,
 },

 IMAPS  => {
     port   => 993,     ssl => 1,
     expect => '^\* OK', readhow => 'banner',
 },

 SMTPS  => {
     port   => 465, 	expect => '^220',	readhow => "banner",
     ssl    => 1,
     # send   => "MAIL\r\n",  # not RFC compliant, but quiets sendmail
 },
 NNTPS  => {
     port   => 563,	expect => '^200',	readhow => "banner",
     ssl    => 1,
 },

 Argus => {
     expect => 'running', readhow => 'banner',
 },

 SlimServer => {
     port    => 9090,       send   => "version ?\r\n",
     readhow => 'banner',   expect => 'version',
 },


 );

# what? like this might change?
my $PROTO_TCP = getprotobyname('tcp');

sub probe {
    my $name = shift;

    return ( $name =~ /^TCP/ ) ? [ 3, \&config ] : undef;
}

sub config {
    my $me = shift;
    my $cf = shift;
    my( $name );

    $name = $me->{name};
    $name =~ s/^TCP\/?//;

    if( $config{$name} ){
	$me->{tcp}{port}         ||= $config{$name}{port};
	$me->{tcp}{send}         ||= $config{$name}{send};
	$me->{tcp}{readhow}      ||= $config{$name}{readhow};
	$me->{tcp}{ssl}          ||= $config{$name}{ssl};
        $me->{tcp}{maybe_expect} ||= $config{$name}{expect};
    }

    $me->{label_right_maybe} ||= $name;

    $me->Argus::IP::init( $cf );
    $me->init_from_config( $cf, $doc, 'tcp' );

    if( $name =~ /^(HTTP|HTTPS|SSL)$/ ){
        $me->{tcp}{http_host} = $me->{ip}{hostname};
	$me->{tcp}{send}    ||= http_request($me, 'HEAD', '/');
    }
    if( $name eq 'URL' ){
	my( $host, $port, $file ) = $me->{tcp}{url} =~ m|https?://([^:/]+)(?::([^/]+))?(/.*)?|;
	$me->{tcp}{ssl}  = $me->{tcp}{url} =~ /https:/ ? 1 : undef;
	$me->{tcp}{port} ||= $port || ($me->{tcp}{ssl} ? 443 : 80);
	$file ||= '/';
	$me->{ip}{hostname} ||= $host;
	$me->{uname} = "URL_$host:$port$file";
	unless( $host ){
	    return $cf->error( 'invalid URL' );
	}
	if( $me->{tcp}{ssl} && ! $::HAVE_SSL ){
	    return $cf->error( 'https url support not available' );
	}

	# bug in some web servers if we always send the port
	if( $me->{tcp}{ssl} ){
	    $host .= ":$port" if $port && $port != 443;
	}else{
	    $host .= ":$port" if $port && $port != 80;
	}

	$file =~ s/\s/%20/g;
        $me->{tcp}{http_host} = $host;
        $me->{tcp}{http_file} = $file;
	$me->{tcp}{send}      = http_request($me, 'GET', $file);
    }

    $me->Argus::IP::config( $cf );

    $me->{friendlyname} = ($config{$name} ? $name : "TCP/$me->{tcp}{port}") . " on $me->{ip}{hostname}";

    if( $name eq 'URL' ){
	$me->{friendlyname} = "URL $me->{tcp}{url}";
    }elsif( $name =~ /NFS/ ){
	$me->{uname} = "TCP_${name}_$me->{ip}{hostname}";
	$me->{friendlyname} = "TCP/$name on $me->{ip}{hostname}";
    }else{
	if( $name ){
	    $me->{uname} = "${name}_$me->{ip}{hostname}";
	}else{
	    $me->{uname} = "TCP_$me->{tcp}{port}_$me->{ip}{hostname}";
	}
    }

    if( $me->{tcp}{ssl} && ! $::HAVE_SSL ){
	# QQQ - fall back to only verifying that we can connect
	$cf->warning( "SSL support missing, falling back to simple port test" );
	$me->{tcp}{ssl} = $me->{tcp}{send} =
	    $me->{tcp}{readhow} = $me->{test}{expect} = undef;
    }

    unless( $me->{tcp}{port} ){
	return $cf->error( "Incomplete specification or unknown protocol for Service $name" );
    }

    bless $me if( ref($me) eq 'Service' );

    $me;
}

sub configured {
    my $me = shift;

    my $t = $me->{test};
    # do not use the expect from above if the value is being changed
    unless( $t->{expect} || $t->{pluck} || $t->{unpack} ){
        $t->{expect} = $me->{tcp}{maybe_expect} if $me->{tcp}{maybe_expect};
    }

    delete $me->{tcp}{maybe_expect};
    $me->Argus::IP::done_done();
}

sub http_request {
    my $me   = shift;
    my $meth = shift;
    my $file = shift;
    my $host = shift;
    my %hdrs = @_;

    # build http request
    $meth ||= 'GET';
    $file ||= '/';
    $host ||= $me->{tcp}{http_host};
    my $ver = $me->{tcp}{http_version} || ($host ? '1.1' : '1.0');

    my $http = "$meth $file HTTP/$ver\r\n";
    $http .= "Host: $host\r\n"                     if $host;
    $http .= "Connection: close\r\n";
    $http .= "Accept: $me->{tcp}{http_accept}\r\n" if $me->{tcp}{http_accept};
    $http .= "User-Agent: $me->{tcp}{browser}\r\n" if $me->{tcp}{browser};
    $http .= "Referer: $me->{tcp}{referer}\r\n"    if $me->{tcp}{referer};
    # to assist in debugging...
    $http .= "X-Argus-Version: $::VERSION\r\n";
    $http .= "X-Argus-URL: $::ARGUS_URL\r\n";

    $http .= "$_: $hdrs{$_}\r\n" for keys %hdrs;

    $http .= "\r\n";
    $http;
}

sub start {
    my $me = shift;
    my( $i, $fh, $ipv );

    $me->SUPER::start();

    $me->{ip}{addr}->refresh($me);

    if( $me->{ip}{addr}->is_timed_out() ){
        return $me->isdown( "cannot resolve hostname" );
    }

    unless( $me->{ip}{addr}->is_valid() ){
        $me->debug( 'Test skipped - resolv still pending' );
        # prevent retrydelay from kicking in
        $me->{srvc}{tries} = 0;
        return $me->done();
    }

    my $ip = $me->{ip}{addr}->addr();

    $me->{fd} = $fh = BaseIO::anon_fh();

    if( length($ip) == 4 ){
	$i = socket($fh, PF_INET, SOCK_STREAM, $PROTO_TCP);
    }else{
	$i = socket($fh, PF_INET6, SOCK_STREAM, $PROTO_TCP);
	$ipv = ' IPv6';
    }
    unless($i){
	my $m = "socket failed: $!";
	::sysproblem( "TCP $m" );
	$me->debug( $m );
	return $me->done();
    }
    $me->baseio_init();

    my $ipa = ::xxx_inet_ntoa($ip);
    $me->debug( "TCP Start: connecting -$ipv tcp/$me->{tcp}{port}, ".
		"$me->{ip}{hostname}/$ipa, try $me->{srvc}{tries}" );

    $me->set_src_addr( 1 )
	|| return $me->done();

    alarm(3);
    # in some cases this may block, even though we set non-blocking
    if( length($ip) == 4 ){
	$i = connect( $fh, sockaddr_in($me->{tcp}{port}, $ip) );
    }else{
	$i = connect( $fh, pack_sockaddr_in6($me->{tcp}{port}, $ip) );
    }
    alarm(0);
    unless( $i || $! == EALREADY || $! == EINPROGRESS ){
	# some OSes will not re-report the error in the SO_ERROR query below...
        $me->{ip}{addr}->try_another();
	return $me->isdown( "TCP connect failed: $!", "connect failed" );
    }
    # if the connect fails for other reasons, we get the error in writable()


    if( $me->{tcp}{build} ){
	$me->{tcp}{build}->($me);
    }

    $me->{srvc}{state} = 'connecting';
    $me->wantread(0);
    $me->wantwrit(1);
    $me->settimeout( $me->{srvc}{timeout} );
    $me->{tcp}{rbuffer} = '';
    $me->{tcp}{wbuffer} = '';

}

sub timeout {
    my $me = shift;

    $me->{ip}{addr}->try_another() if $me->{srvc}{state} eq 'connecting';
    $me->isdown( "TCP timeout: $me->{srvc}{state}", "timeout" );
}

sub done {
    my $me = shift;

    $me->SSL::cleanup() if $me->{tcp}{ssldata};
    $me->Argus::IP::done();
    $me->Service::done();
    $me->Argus::IP::done_done();
}

sub http_redirect {
    my $me = shift;
    my( $url, $file, $loc );

    # NB: this code path never calls done
    $me->shutdown();

    ($loc) = grep /^Location:/, split( /\n/, $me->{tcp}{rbuffer} );
    $loc =~ tr/\r//d;
    ($url)  = $loc =~ /^Location:\s+(.*)/;
    ($file) = $url =~ m|(?:https?://[^/]*)?(.*)|;
    # NB: cannot redirect to another host

    $me->{tcp}{altsend} = $me->http_request('GET', $file );

    $me->debug( "HTTP Redirect -> $url" );
    if( ++$me->{tcp}{redircount} > 15 ){
	undef $me->{tcp}{redircount} ;
	return $me->isdown( 'HTTP Redirect Loop', 'loop' );
    }
    # start over without rescheduling
    $me->start();
}

sub http_auth {
    my $me = shift;
    my( $url, $file, $loc );

    $me->shutdown();

    my($auth) = grep /^WWW-Authenticate:/, split( /\n/, $me->{tcp}{rbuffer} );
    my($scheme, $realm) = $auth =~ /^WWW-Authenticate:\s+(\S+)\s+realm="(.*)"/;


    # ...


    $me->{tcp}{send} = $me->http_request('GET', $me->{tcp}{http_file});

    $me->debug( "HTTP Auth [$scheme, $realm] -> $url" );

    if( ++$me->{tcp}{redircount} > 15 ){
	undef $me->{tcp}{redircount} ;
	return $me->isdown( 'HTTP Redirect/Auth Loop', 'loop' );
    }

    # start over without rescheduling
    $me->start();
}



sub writable {
    my $me = shift;

    return $me->SSL::writable() if $me->{tcp}{ssl};
    if( $me->{srvc}{state} eq 'connecting' ){
	my $fh = $me->{fd};
	my $i = unpack('L', getsockopt($fh, SOL_SOCKET, SO_ERROR));
	if( $i ){
	    $! = $i;
	    # QQQ, should I try to sort out errors, down on some, sysproblem on others?
            $me->{ip}{addr}->try_another();
	    return $me->isdown( "TCP connect failed: $!", 'connect failed' );
	}

	$me->debug( 'TCP - connected' );
	$me->{tcp}{wbuffer} = $me->{tcp}{altsend} || $me->{tcp}{send};
	undef $me->{tcp}{altsend};
	$me->{srvc}{state} = 'sending';
        $me->{srvc}{starttesttime} = BaseIO::ctime();
	$me->settimeout( $me->{srvc}{timeout} );
    }

    if( $me->{tcp}{wbuffer} ){
	my( $b, $i, $l, $fh );
	$fh = $me->{fd};
	$b = $me->{tcp}{wbuffer};
	$l = length($b);
	# And he asked for a writing table, and wrote
	#   -- Luke 1:63
	$i = syswrite( $fh, $b, $l );
	if( defined $i ){
	    $me->debug( "TCP - wrote $i bytes of $l" );
	}else{
	    return $me->isdown( "TCP write failed: $!", 'write failed' );
	}
	$b = substr( $b, $i, $l );
	$me->{tcp}{wbuffer} = $b;
    }

    if( !$me->{tcp}{wbuffer} ){
	if( $me->{tcp}{readhow} ){
	    $me->{srvc}{state} = 'expecting';
	    $me->wantread(1);
	    $me->wantwrit(0);
	    $me->settimeout( $me->{srvc}{timeout} );
	}else{
	    # success is a connected socket
	    $me->isup();
	}
    }
}

sub readable {
    my $me = shift;
    my( $fh, $i, $l, $testp );

    return $me->SSL::readable() if $me->{tcp}{ssl};

    $fh = $me->{fd};
    $i = sysread( $fh, $l, 8192 );

    # And this is the writing that was written: MENE, MENE, TEKEL, UPHARSIN.
    #   -- daniel 5:25
    if( $i ){
	$me->debug( "TCP - read data $i" );
	$me->{tcp}{rbuffer} .= $l;
    }
    elsif( defined($i) ){
        # And it came to pass, when Moses had made an end of writing ...
	#   -- dueteronomy 31:24
	# $i is 0 -> eof
	$me->debug( 'TCP - read eof' );
	$testp = 1;
    }
    else{
	# $i is undef -> error
	return $me->isdown( "TCP read failed: $!", 'read failed' );
    }

    if( $me->{tcp}{readhow} eq 'banner' ){
	# My ears have not yet drunk a hundred words
	# Of that tongue's utterance, yet I know the sound:
	#   -- Shakespeare, Romeo+Juliet

	$testp = 1 if $me->{tcp}{rbuffer} =~ /\n/;
    }
    elsif( $me->{tcp}{readhow} eq 'toblank' ){
	$testp = 1 if $me->{tcp}{rbuffer} =~ /\r\n\r\n/;
    }
    elsif( $me->{tcp}{readhow} eq 'once' ){
	$testp = 1;
    }
    elsif( $me->{tcp}{readhow} eq 'toeof' ){
	# $testp = 0;
    }
    elsif( $me->{tcp}{readhow} > 0 ){
	# if readhow is a number, read at least that many bytes
	$testp = 1 if length($me->{tcp}{rbuffer}) >= $me->{tcp}{readhow};
    }
    if( $testp ){
	return $me->test();
    }else{
	# kibbles and bits, kibbles and bits, give me more kibbles and bits
	#   -- Dog Food Commercial
	$me->wantread(1);
	$me->wantwrit(0);
    }
}

sub test {
    my $me = shift;
    my( $e );

    if( $me->{name} eq 'TCP/URL' ){
        if( $me->{tcp}{rbuffer} =~ /HTTP\/1\.\d+\s+30[12]/ ){
            # once or twice she had peeped into the book her sister was reading, but
            # it had no pictures or conversations in it,
            #   -- Alice in Wonderland
            # try to handle redirect
            return $me->http_redirect();
        # }elsif( $me->{tcp}{rbuffer} =~ /HTTP\/1\.\d+\s+401/ ){
        #     return $me->http_auth();
        }else{
            undef $me->{tcp}{redircount};
        }
    }

    # There is a written scroll! I'll read the writing.
    #   -- Shakespeare, Merchant of Venice

    return $me->generic_test($me->{tcp}{rbuffer});

}


################################################################
# and also object methods
################################################################

sub about_more {
    my $me = shift;
    my $ctl = shift;

    $me->SUPER::about_more($ctl);
    $me->more_about_whom($ctl, 'ip', 'tcp');
}

sub webpage_more {
    my $me = shift;
    my $fh = shift;

    $me->Argus::IP::webpage_more($fh);

    foreach my $k (qw(port url)){
	my $v = $me->{tcp}{$k};
	next unless defined $v;
	# I see a lot of long URLs...
	if( $k eq 'url' ){
	    my $c = $v;
	    $c = substr($c, 0, 70) . '...'
		if( length($c) > 70 );
	    $v = qq{<A HREF="$v">$c</A>};
	}
	print $fh "<TR><TD><L10N $k></TD><TD>$v</TD></TR>\n";
    }
}


################################################################
# global config
################################################################
Doc::register( $doc );
push @Service::probes, \&probe;



1;
