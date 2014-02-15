# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Apr-03 19:27 (EST)
# Function: test exececution of a program
#
# $Id: Prog.pm,v 1.41 2008/02/03 03:00:43 jaw Exp $

package Prog;
@ISA = qw(Service);

use Argus::Encode;
use POSIX ('_exit');
use POSIX ':sys_wait_h';

# And what is written shall be executed.
#   -- Shakespeare, Titus Andronicus

# program success is either exit value or expected regex

use strict qw(refs vars);
use vars qw(@ISA $doc);

$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [qw(Service MonEl BaseIO)],
    methods => {},
    html   => 'services',
    fields => {
      prog::command => {
	  descr => 'command to run',
	  attrs => ['config'],
      },
      prog::pid => {
	  descr => 'process PID',
      },
      prog::error => {
	  descr => 'reason for failure',
      },
      prog::exit => {
	  descr => 'process\'s exit status',
      },
    },
};

my %bypid = ();
my $REAPRUNS    = 32;
my $needreapage = 0;
my $progrunning = 0;

# NB: must not do any work in signal handler - malloc/free are not
#     re-entrant. we will get:
#       perl in free(): warning: recursive call.
#       perl in malloc(): warning: recursive call
# we punt, and reap from main()
# allegedly, perl 5.8 gets this right...
#
# For he that soweth to his flesh shall of the flesh reap *corruption*
#   -- Galatians 6:8

#$SIG{CHLD} = sub {
#    $needreapage = 1;
#};

# The enemy that sowed them is the devil; the harvest is the end of the
# world; and the reapers are the angels.
#   -- Matthew 13:39
sub reap {
    my ( $s, $pid );

    #return unless $needreapage;
    #$needreapage = 0;

    while( ($pid = waitpid(-1, WNOHANG)) > 0 ){
	$s = $bypid{$pid};
	delete $bypid{$pid};
	next unless $s;
	$s->debug( "Prog exited: $?" );
	$s->{prog}{exit} = $?;
	$s->{prog}{pid} = 0;
	while( $s->{wantread} ){
	    # make sure we read any/all still unread data
	    $s->readable();
	}
	$s->progdone();
    }
}

sub register {
    my $me  = shift;
    my $pid = shift;

    $bypid{$pid} = $me;

    unless( ++$progrunning % $REAPRUNS ){
	reap();
    }
}

sub probe {
    my $name = shift;

    return ( $name =~ /^Prog/ ) ? [ 4, \&config ] : undef;
}

sub config {
    my $me = shift;
    my $cf = shift;

    $me->init_from_config( $cf, $doc, 'prog' );
    $me->{uname} = "Prog_$me->{prog}{command}";

    return $cf->error( 'command not specified' )
	unless $me->{prog}{command};
    
    bless $me if( ref($me) eq 'Service' );
    $me;
}

sub start {
    my $me = shift;
    my( $fh, $pid );
    
    $me->debug( "Prog starting - $me->{prog}{command}" );
    
    $me->{fd} = $fh = BaseIO::anon_fh();

    # I do not well understand that. Will you play upon this pipe?
    #   -- Shakespeare, Hamlet
    unless( pipe($fh, W) ){
	my $m = "pipe failed: $!";
	::sysproblem( "PROG $m" );
	$me->debug( $m );
	$me->done();
	return;
    }

    $me->baseio_init();
    $me->SUPER::start();

    $pid = fork();
    
    if( !defined($pid) ){
	# fork failed
	my $m = "fork failed: $!";
	close W;
	close $fh;
	::sysproblem( "PROG $m" );
	$me->debug( $m );
	return $me->done();
    }
    
    unless( $pid ){
	# child
        BaseIO::closeall();
	close STDOUT; open( STDOUT, ">&W" );
	close STDERR; open( STDERR, ">&W" );
	close STDIN;  open( STDIN, "/dev/null" );
	close $fh;
	close W;
	$ENV{ARGUS_OBJNAME} = $me->unique();
	$ENV{ARGUS_OBJFILE} = $me->filename();
	$ENV{ARGUS_UNAME}   = $me->{uname};
        $ENV{ARGUS_DEBUG}   = $me->{debug} || ::topconf('debug');

	# Oh my fur and whiskers!  She'll get me
        # executed, as sure as ferrets are ferrets!
	#   -- Alice in Wonderland
	exec( $me->{prog}{command} ); # no, I didn't mean system() when I said exec()
	# and yes, I am aware the following statement is unlikely to be reached.
	syswrite( STDERR, "exec failed: $!\n" );
	_exit(-1);
    }
    
    close W;
    $me->{prog}{pid} = $pid;
    $me->debug( "PROG pid $pid" );
    delete $me->{prog}{error};
    delete $me->{prog}{exit};
    $me->register($pid);
    $me->{prog}{rbuffer} = '';
    $me->wantread(1);
    $me->wantwrit(0);
    $me->settimeout( $me->{srvc}{timeout} );
}

sub timeout {
    my $me = shift;

    # try jit reap
    reap() if $me->{prog}{pid};
    return if $me->{srvc}{state} eq 'done';
    
    $me->debug( 'Prog Timeout' );
    if( defined($me->{prog}{exit}) ){
	$me->progdone();
    }else{
        # First forc'd an entrance thro' their thick array; 
        # Then, glutted with their slaughter, freed my way. 
	#   -- Virgil, Aeneid
	$me->debug( 'killing' );
	kill 9, $me->{prog}{pid} if $me->{prog}{pid};
	$me->{prog}{error} = 'Prog timeout';
	$me->{srvc}{state} = 'reaping';
    }
}

sub readable {
    my $me = shift;
    my( $fh, $i, $l );

    $fh = $me->{fd};
    $i = sysread $fh, $l, 8192;
    if( $i ){
	$me->debug( "Prog read $i bytes" );
	$me->{prog}{rbuffer} .= $l;
    }
    elsif( !defined($i) ){
	if( $me->{prog}{pid} ){
	    # $i is undef -> error
	    $me->{prog}{error} = "Prog read failed: $!";
	    $me->{srvc}{state} = 'reaping';
	    $me->debug( $me->{prog}{error} );
	    $me->debug( 'killing' );
	    kill 9, $me->{prog}{pid} if $me->{prog}{pid};
	}else{
	    # no error if program already exited
	}
	$me->wantread(0);
    }
    else{
	# got eof
	$me->debug( 'Prog eof' );
	$me->wantread(0);
	$me->{srvc}{state} = 'reaping';
	# wait until exit or timeout
    }
}

sub progdone {
    my $me = shift;
    my( $e );

    $me->debug( 'Prog - done' );

    $me->{srvc}{state} = 'done';
    return $me->isdown( $me->{prog}{error}, 'error' ) if $me->{prog}{error};
    # QQQ
    # return $me->isdown( 'Prog - exited with error', 'error' ) if $me->{prog}{exit};
    $me->{srvc}{result} = $me->{prog}{rbuffer} if $me->{prog}{rbuffer};
    
    if( $me->{test}{testedp} ){
	return $me->generic_test( $me->{prog}{rbuffer}, 'PROG' );
    }elsif( $me->{prog}{exit} ){
	return $me->isdown('Prog - exited with error', 'error');
    }else{
	return $me->isup();
    }
}



################################################################
# and also object methods
################################################################

sub about_more {
    my $me = shift;
    my $ctl = shift;
    my( $k, $v );

    $me->SUPER::about_more($ctl);
    $me->more_about_whom($ctl, 'prog');
}

sub webpage_more {
    my $me = shift;
    my $fh = shift;
    my( $k, $v );
    
    foreach $k (qw(command)){
	$v = $me->{prog}{$k};
	print $fh "<TR><TD><L10N $k></TD><TD>$v</TD></TR>\n" if defined($v);
    }
}


################################################################
# global config
################################################################
Doc::register( $doc );
push @Service::probes, \&probe;

Cron->new( freq => 5,
	   text => 'Prog reap',
	   func => \&reap );
1;

