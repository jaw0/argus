# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Nov-16 15:10 (EST)
# Function: listen for new connections
#
# $Id: Server.pm,v 1.11 2004/04/29 21:15:02 jaw Exp $

package Server;
@ISA = qw(BaseIO);

use Fcntl;
use Socket;

# The open ear of youth doth always listen;
#	-- Shakespeare King Richard II

use strict qw(refs vars);
use vars qw(@ISA $doc);

$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [@ISA],
    methods => {
    },
    fields  => {
      server::class => { descr => 'class of server' },
      server::type  => { descr => 'type of server' },
    },
};

sub new_local {
    my $class = shift;
    my $file  = shift;
    my $perm  = shift || 0777;	# to reduce the amount of email the author receives...
    my( $me, $fh, $i, $p );

    return if $::opt_t;
    $me = {};
    bless $me;
    $me->{type} = $class . 'D';
    $me->{server}{class} = $class;
    $me->{server}{type}  = 'local';
    $me->{fd} = $fh = BaseIO::anon_fh();

    # perl doesn't know that NetBSD renamed this PF_LOCAL...
    socket($fh, PF_UNIX, SOCK_STREAM, 0);
    unlink $file;
    # Do as I bid you; shut doors after you:
    # Fast bind, fast find;
    #   -- Shakespeare, Merchant of Venice
    $i = bind($fh, sockaddr_un($file));
    return ::warning( "Cannot bind $class to unix/$file: $!" )
	unless $i;

    chmod $perm, $file if $perm;
    
    ::loggit( "$class server: listening on unix/$file", 0 );
    listen( $fh, 10 );
    $me->wantread(1);
    $me->wantwrit(0);
    $me->settimeout(0);
    $me->baseio_init();

    $me;
}

sub new_inet {
    my $class = shift;
    my $port  = shift;
    my $aclf  = shift;
    my( $me, $fh, $i, $p );

    return if $::opt_t;
    $me = {};
    bless $me;
    $me->{type} = $class . 'D';
    $me->{server}{class} = $class;
    $me->{server}{type}  = 'inet';
    $me->{server}{aclf}  = $aclf;
    $me->{fd} = $fh = BaseIO::anon_fh();

    # Their sockets were like rings without the gems
    #   -- Dante, Divine Comedy
    socket($fh, PF_INET, SOCK_STREAM, getprotobyname('tcp'));
    setsockopt($fh, SOL_SOCKET, SO_REUSEADDR, 1);
    $i = bind($fh, sockaddr_in($port, INADDR_ANY));
    return ::warning( "Cannot bind $class to tcp/$port: $!" )
	unless $i;
	
    ::loggit( "$class server: listening on tcp/$port", 0 );
    listen( $fh, 10 );
    $me->wantread(1);
    $me->wantwrit(0);
    $me->settimeout(0);
    $me->baseio_init();

    $me;
}


# becomes readable if someone connects - create a new control channel
sub readable {
    my $me = shift;
    my( $fh, $nfh, $c, $i, $data );

    $fh  = $me->{fd};
    $nfh = BaseIO::anon_fh();
    $i = accept( $nfh, $fh );
    return ::loggit( "Control accept failed - $!", 0 )
	unless $i;

    if( $me->{server}{type} eq 'local' ){
	$data = 'local';
    }else{
	$data = ::xxx_inet_ntoa( (sockaddr_in(getpeername($nfh)))[1] );
    }

    # print STDERR "new connection from $data, type $me->{server}{class}\n";
    $c = $me->{server}{class}->new( $nfh, $data );
    $c->{debug} = $me->{debug} if $c;

    $c;
}

################################################################
# class global init
################################################################
Doc::register( $doc );

1;
