# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Oct-22 16:06 (EDT)
# Function: Notification Method base class
#
# $Id: NotMe.pm,v 1.41 2010/01/10 22:23:19 jaw Exp $

package NotMe;
# but I seek my master, and my master seeks not me
#   -- Shakespeare, Two Gentlemen of Verona

@ISA = qw(Configable);
use POSIX ('_exit', 'strftime', 'tzset');

use strict;
use vars qw(@ISA $doc %methods);

%methods;

$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [ ],
    methods => {},
    versn   => '3.2',
    html    => 'notif',
    conf => {
	quotp => 1,
	bodyp => 1,
    },
    fields  =>  {
	function => {},
	command => {
	    descr => 'command to run',
	    attrs => ['config'],
	},
	send => {
	    descr => 'text to send to command on stdin',
	    attrs => ['config'],
	},
	qtime => {
	    descr => 'amount of time (seconds) for determining whether to send a notification or queue it',
	    attrs => ['config', 'inherit'],
	    default => 0,	# default for user-defined methods, not built-ins
	},
	nolotsmsgs => {
	    descr => 'list all msgs, dont summarize into Lots DOWN/UP',
	    attrs => ['config', 'inherit'],
	    versn => '3.3',
	},
	message_fmt => {
	    descr => 'conversion format for messages (%M)',
	    attrs => ['config'],
	    versn => '3.3',
	},

        'schedule::schedule critical' => {
            descr => 'schedule specifying when to send critical notifications',
            attrs => ['config', 'sched'],
            versn => '3.7',
            html  => 'schedule',
        },
        'schedule::schedule major' => {
            descr => 'schedule specifying when to send major notifications',
            attrs => ['config', 'sched'],
            versn => '3.7',
            html  => 'schedule',
        },
        'schedule::schedule minor' => {
            descr => 'schedule specifying when to send minor notifications',
            attrs => ['config', 'sched'],
            versn => '3.7',
            html  => 'schedule',
        },
        'schedule::schedule warning' => {
            descr => 'schedule specifying when to send warning notifications',
            attrs => ['config', 'sched'],
            versn => '3.7',
            html  => 'schedule',
        },
        'schedule::schedule clear' => {
            descr => 'schedule specifying when to send clear notifications',
            attrs => ['config', 'sched'],
            versn => '3.7',
            html  => 'schedule',
        },
    },
};

sub permit_now {
    my $dst  = shift;
    my $sev  = shift;

    my( $meth, $addr ) = dst2m_a($dst);
    my $m = $methods{$meth};

    return 1 unless $m->{schedule}{$sev};
    return $m->{schedule}{$sev}->permit_now();
}

sub transmit {
    my $note = shift;
    my $dst  = shift;
    my $msg  = shift;
    my $extra= shift;
    my @more = @_;
    
    my( $meth, $addr ) = dst2m_a($dst);
    
    # Though this be madness, yet there is method in 't.
    #   -- Shakespeare, Hamlet

    my $m = $methods{$meth};
    
    if( $m ){
	if( $m->{message_fmt} ){
	    $msg = '';
	    foreach my $n ($note, @more){
		$msg .= expand( $n, $m->{message_fmt}, $meth, $addr, $n->{msg}, $extra );
	    }
	}
	
	if( exists $m->{function} ){
	    $m->{function}->($note, $meth, $addr, $msg, $extra);
	}else{
	    my $pid = fork();
	    
	    if( !defined($pid) ){
		my $e = "fork failed: $!";
		::sysproblem( "NOTIFY $e" );
		return $e;
	    }

	    if( $pid ){
		# parent
	        Prog::register( undef, $pid );
		  
	    }else{
		# child
		my $cmd  = expand( $note, $m->{command}, $meth, $addr, $msg, $extra );
		my $send = expand( $note, $m->{send},    $meth, $addr, $msg, $extra );

		# QQQ - set various env vars?
		open( Q, "| $cmd" ) || die "notify method failed: $m: $!\n";
		print Q "$send\n";
		close Q;
		_exit(0);
	    }
	}
    }else{
	$note->loggit( $addr, "unknown method ($meth) - cannot send", 1 );
    }

    undef;
}

sub dst2m_a {
    my $dst = shift;
    my($m, $a) = split /:/, $dst, 2;
    
    if( !$a ){
	if( $methods{$m} ){
	    $a = 'nobody';
	}else{
	    $m = 'mail'; $a = $dst;
	}
    }

    ($m, $a);
}
    
sub qtime {
    my $dst = shift;
    my($m) = dst2m_a($dst);

    $methods{$m} ? $methods{$m}{qtime} : undef;
}

sub nolots {
    my $dst = shift;
    my($m) = dst2m_a($dst);

    $methods{$m} ? $methods{$m}{nolotsmsgs} : undef;
}    

sub bnew {
    my $me = __PACKAGE__->new(@_);
    $me->cfinit(undef, '?', 'Method');
    $me->{builtin} = 1;
    $me;
}

# null notification method
sub null {}

# for debugging
sub nlog {
    my $note = shift;
    my $meth = shift;
    my $addr = shift;
    my $msg  = shift;
    my $extra= shift;

    ::loggit( "($addr) NOTIFY: $msg $extra" );
}

sub autoack {
    my $note = shift;
    
    $note->ack();
}

sub expand {
    my $note = shift;
    my $txt  = shift;
    my $meth = shift;
    my $addr = shift;
    my $msg  = shift;
    my $extr = shift;
    
    while( $txt =~ /%[ZT]/ ){
	my $tz = $ENV{TZ};
	my( $t, $z, $f, @l );
	
	if( $note->{timezone} ){
	    $ENV{TZ} = $note->{timezone};
	    tzset();
	}
	if( $txt =~ /%T{([^\}]+)}/ ){
	    $f = $1;
	}else{
	    $f = "%d/%b %R";		# dd/Mon hh:mm
	}
	@l = localtime($note->{created});
	$t = strftime $f, @l;
	$z = strftime "%Z", @l;
	if( $note->{timezone} ){
	    $ENV{TZ} = $tz;
	    delete $ENV{TZ} unless defined $tz;
	    tzset();
	}
	
	$txt =~ s/%Z/$z/g;
	$txt =~ s/%T({[^\}]+})?/$t/;
    }

    while( $txt =~ /%O/ ){
    	my( $param, $value );
	
	if( $txt =~ /%O{([^\}]+)}/ ){
	    $param = $1;
	    $param =~ s/^\s+//;
	    $param =~ s/\s+$//;

	    eval {
		$value = $note->{obj}->getparam($param);
	    };
	    if( $@ ){
		$value = 'Param Not Found';
            }
	}else{
	    $value = $note->{obj}->unique();
	}
        $txt =~ s/%O({[^\}]+})?/$value/;
    }
    
    # %lowercase are expanded in Notify
    
    $txt =~ s/%A/$note->{detail}/g;
    $txt =~ s/%C/$note->{sentcnt}/g;
    $txt =~ s/%D/$DARP::info->{tag}/ if defined $DARP::info;
    $txt =~ s/%E/$extr/g;
    $txt =~ s/%F/$note->{mailfrom}/g;
    $txt =~ s/%I/$note->{idno}/g;
    $txt =~ s/%M/$msg/g;
    $txt =~ s/%N/$meth/g;
    # %O above
    $txt =~ s/%P/$note->{priority}/g;
    $txt =~ s/%R/$addr/g;
    $txt =~ s/%S/$note->{objstate}/g;
    # %T above
    $txt =~ s/%V/$note->{objovstate}/g;		# is this useful, it will never be override...
    $txt =~ s/%Y/$note->{severity}/g;
    # %Z above 

    $txt =~ s/%&//g;
    
    # $txt =~ ...

    $txt = ::expand_conditionals( $txt );
    $txt;
}

sub config {
    my $me = shift;
    my $cf = shift;

    my $name = $me->{name};
    $me->init_from_config($cf, $doc, '');
    $me->init_from_config($cf, $doc, 'schedule');

    # if redefining a builtin, and no command is specified, copy
    if( $methods{$name} && $methods{$name}{builtin} ){
	$me->{command} ||= $methods{$name}{command};
    }

    unless($me->{command}){
        $cf->nonfatal( "invalid Notification Method - command not specified" );
	return;
    };

    # don't warn if redefining a builtin
    $cf->warning( "redefinition of Notification Method '$name'" )
	if $methods{$name} && !$methods{$name}{builtin};

    $me->check_typos($cf);

    $methods{$name} = $me;
}

sub gen_confs {
    my( $r );
    
    foreach my $m (sort keys %methods){
	next unless ref($methods{$m}) eq __PACKAGE__;
	next unless exists $methods{$m}{config};
	$r .= $methods{$m}->gen_conf();
    }
    $r = "\n$r" if $r;
    
    $r;
}

################################################################

$methods{null} = bnew(
    qtime    => 0,
    function => \&null,
);
$methods{log}  = bnew(
    qtime    => 0,
    function => \&nlog,
);
$methods{autoack} = bnew(
    qtime    => 0,
    function => \&autoack,
);			 

$methods{qpage} = bnew(
    command => "$::path_qpage %R",
    send    => "%M%E",
) if $::path_qpage;

$methods{mail} = bnew(
    command => "$::path_sendmail -t",
    send    => "To: %R\nFrom: %F\nSubject: Argus%E\n\n%M\n",
) if $::path_sendmail;

################################################################
Doc::register( $doc );

1;
