# -*- perl -*-

# Copyright (c) 2007 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2007-Jan-27 00:07 (EST)
# Function: archive data via a program
#
# $Id: Argus::Archivist.pm,v 1.7 2007/09/01 16:51:35 jaw Exp $

package Argus::Archivist;
@ISA = qw(BaseIO);
use Socket;
use POSIX ('_exit');
use vars qw($doc @ISA);
use strict qw(refs vars);

my $TIMEOUT     = 120;
my $BIG_HARD    = 500_000;
my $BIG_SOFT    = 100_000;
my $BIG_SOFT_LO = $BIG_SOFT * .75;

$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [@ISA],
    methods => {
    },
    fields => {
      archivist::wbuffer => {},
      archivist::name    => {},
      archivist::pid     => {},
      archivist::softhit => {},
    },
};

# keep track
my %history;

sub new {
    my $cl = shift;
    my $me = { archivist => {@_}};
    my( $fh, $pid );
    
    bless $me, $cl;
    $me->{type} = $cl;
    $me->debug( "new" );
    $me->{fd} = $fh = BaseIO::anon_fh();

    my $name = $me->{archivist}{name} || $cl;
    my $exec = $me->{archivist}{prog};
    $exec .= ' ' . $me->{archivist}{args} if $me->{archivist}{args};

    # make sure program is working, not dying and restarting
    if( $history{$name} ){
	my $last = $history{$name}{last};
	if( ($^T - $history{$name}{first}) > 300 ){
	    # reset history
	    delete $history{$name};
	}else{
	    if( ($^T - $last) < 60 && ($history{$name}{count}++ == 10) ){
		::sysproblem("Archivist/$name respawning rapidly");
	    }
	    $history{$name}{last} = $^T;
	}
    }
    $history{$name} ||= {
	last  => $^T,
	first => $^T,
	count => 1,
    };

    
    # we need to know if the child dies, pipe won't tell us (but we can catch sigchld)
    # but socketpair will select as readable if the child dies
    unless( socketpair($fh, AR, AF_UNIX, SOCK_STREAM, PF_UNSPEC) ){
	my $m = "socketpair failed: $!";
	::sysproblem( "Archivist/$name $m" );
	$me->debug( $m );
	$me->done();
	return;
    }
    $me->baseio_init();

    $pid = fork();
    
    if( !defined($pid) ){
	# fork failed
	my $m = "fork failed: $!";
	::sysproblem( "Archivist/$name $m" );
	$me->debug( $m );
	return $me->done();
    }
    
    unless( $pid ){
	# child
        BaseIO::closeall();
	close STDIN;  open( STDIN, "<&AR" );
	close STDOUT; open( STDOUT, ">/dev/null" );
	# let stderr go where ever argus's stderr goes
	close $fh;
	close AR;
	exec( $exec );
	# no, I didn't mean system() when I said exec()
	# and yes, I am aware the following statement is unlikely to be reached.
	_exit(-1);
    }
    close AR;


    $me->{archivist}{pid} = $pid;
    # need to learn if child dies, ask Prog for help
    # (just in case we don't already know)
    Prog::register( $me, $pid );
    $me->wantread(1);
    $me->wantwrit(0);
    $me->settimeout(0);

    $me;
}

# Fool! said my muse to me, look in thy heart, and write.
#   -- Sir Philip Sidney, Astrophel and Stella
sub write {
    my $me  = shift;
    my $msg = shift;

    $me->{archivist}{wbuffer} .= $msg;
    my $l = length($me->{archivist}{wbuffer});
    my $name = $me->{archivist}{name} || $me->{type};

    # watch buffer. make sure the program can keep up
    if( $l > $BIG_HARD ){
	::sysproblem("Archivist/$name program could not keep up. killing.");
	$me->kill();
	return;
    }
    if( $l > $BIG_SOFT && !$me->{archivist}{softhit} ){
	# warn each time soft limit is passed
	::sysproblem("Archivist/$name program is not keeping up");
	$me->{archivist}{softhit} = 1;
    }elsif( $l < $BIG_SOFT_LO ){
	# clear warning flag once buffer shrinks a bit
	$me->{archivist}{softhit} = 0;
    }
    
    $me->wantwrit(1);
    $me->settimeout($TIMEOUT);
}

sub writable {
    my $me = shift;
    my $fh = $me->{fd};
    
    if( my $buf = $me->{archivist}{wbuffer} ){
	my( $i, $l );
	
	$l = length($buf);
	$i = syswrite $fh, $buf, $l;
	if( ! $i ){
	    $me->debug( "write failed: $!" );
	    $me->done();
	    return;
	}else{
	    $me->debug( "wrote $i bytes" );
	    $me->{archivist}{wbuffer} = substr($buf, $i, $l);
	}
    }

    if( $me->{archivist}{wbuffer} ){
	$me->settimeout($TIMEOUT);
	$me->wantwrit(1);
    }else{
	# Stop close their mouths, let them not speak a word.
	#   -- Shakespeare, Titus Andronicus
	$me->settimeout(0);
	$me->wantwrit(0);
    }
}

sub readable {
    my $me = shift;

    # NB: running program has stdout sent to /dev/null
    # we only get here if it dies.
    $me->wantread(0);
    $me->done();
}

sub timeout {
    my $me = shift;

    $me->debug( "timeout" );
    $me->done();
}

sub progdone {
    my $me = shift;

    $me->debug( "reaped" );
    $me->done();
}

# what's done is done.
#   -- Shakespeare, Macbeth
sub done {
    my $me = shift;
    
    $me->shutdown();
}

sub kill {
    my $me = shift;
    
    kill 15, $me->{archivist}{pid} if $me->{archivist}{pid};

}

sub debug {
    my $me  = shift;
    my $msg = shift;

    return unless ::topconf('debug');
    my $f = $me->{fd} ? fileno($me->{fd}) : '';
    my $name = $me->{archivist}{name} || $me->{type};

    ::loggit( "DEBUG - Archivist/$name - [$f] $msg" );
}


1;
