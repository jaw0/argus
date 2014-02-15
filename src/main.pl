#!__PERL__
# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Apr-02 12:09 (EST)
# Function: argus startup and glue
#
# $Id: main.pl,v 1.77 2012/12/29 21:47:41 jaw Exp $

# In God we trust, everyone else we monitor.
#   -- U2 pilot motto

use lib('__LIBDIR__');
BEGIN{
    require "conf.pl";
    require "misc.pl";
    require "common.pl";
}
BEGIN{eval{require Diag;}}

use Doc;
use Control;
use BaseIO;
use Cron;
use Server;
use Commands;
use Conf;
use Configable;
use MonEl;
use Group;
use Alias;
use Service;
use Error;
use Notify;
use Graph;
use NullConf;
use UserCron;
use TestPort;
use Argus::Ctl;
use Argus::HashDir;
use Argus::Schedule;
use Argus::Ticket;
use Argus::Dashboard;
use Argus::Resolv;
use DARP;

BEGIN {
    # these may or may not be present

}

use Sys::Syslog qw(:DEFAULT setlogsock);
use POSIX qw(:errno_h setsid);
use __DATABASE__;
use Getopt::Std;

getopts("a:c:dfg:htu:CDEHS:T");

$DATABASE   = '__DATABASE__';
$MAX_PERIOD = 300;
$NAME = "Argus";

$mainpid   = 0;
$starttime = 0;
$mainstart = $^T;
$idletime  = 0;
$loopcount = 0;
($OSINFO = join(' ', (`uname -s`, `uname -r`, `uname -m`)))
    =~ s/[\n\r]//g;
$COOKIE;

my $childpid = 0;
my $exitinprogress = 0;

if( $opt_h ){
    print <<U;
usage: $0 [options]
	 -f    keep stdio open and run in foreground
	 -d    debugging
	 -a alt. data dir
	 -c alt. config file
	 -u user    change to the specified user at startup
	 -g group   change to the specified group at startup

    the following options will perform their function and exit
	 -h    display a message not entirely unlike this one
	 -D    describe config file parameters
	 -DS v describe config file parameters new or changed since specified version
	 -E    describe internal data structures
	 -C    describe control channel commands
	 -H    make above descriptions in html
	 -t    syntax check config files
	 -T    syntax check config files, and more...
U
    ;
    exit;
}

$datadir = $opt_a if $opt_a;
$opt_t ||= $opt_T;
$opt_f ||= $opt_d;
$opt_f ||= $opt_t;

Doc::describe_config( $opt_H, $opt_S )  if $opt_D;
Doc::describe_internal( $opt_H, $opt_S )if $opt_E;
Doc::describe_control( $opt_H ) if $opt_C;

if( $opt_t ){
    Conf::readconfigfiles( $opt_c || "$datadir/config" );
    exit $Conf::has_errors;
}

# change uid/gid
if( $opt_g ){
    my $gid = (getgrnam($opt_g))[2];
    $gid = $opt_g if( !defined($gid) && $opt_g =~ /^\d+$/ );
    die "invalid group for -g option. aborting.\n" unless defined $gid;
    $( = $gid; $) = $gid;
}
if( $opt_u ){
    my $uid = (getpwnam($opt_u))[2];
    $uid = $opt_u if( !defined($uid) && $opt_u =~ /^\d+$/ );
    die "invalid user for -u option. aborting.\n" unless defined $uid;
    $! = 0;
    $< = $> = $uid;
    die "unable to change uid: $!\n" if $!;
}

# check permissions now instead of failing later
foreach ('', qw(html/ gdata/ log notify/ notno stats/)){
    my $f = "$datadir/$_";
    if( $f =~ m,/$, ){
	die "no such directory '$f'. aborting.\n" unless -d $f;
    }else{
	die "no such file '$f'. aborting.\n" unless -f $f;
    }
    die "permission denied, cannot write '$f'. aborting.\n" unless -w $f;
    die "permission denied, cannot read '$f'. aborting.\n"  unless -r $f;
}

# is another argus already running?
if( -e "$datadir/control" ){
    my $ctl;
    eval {
	$ctl = Argus::Ctl->new( "$datadir/control",
				timeout	=> 2,
				retry	=> 0,
				# we expect the connect to fail
				onerror	=> sub { },
				);
    };
    if( $ctl && $ctl->connectedp() ){
	die "argus is already running. aborting.\n";
    }
}

# create subdirs
# NB: gcache might not be writable
my $wantclean;
foreach my $dir (qw(html gdata stats)){
    for my $a ('A'..'Z'){
	mkdir "$datadir/$dir/$a", 0777;
	for my $b ('A'..'Z'){
	    mkdir "$datadir/$dir/$a/$b", 0777;
	}
    }
}
MonEl::janitor() if -f "$datadir/stats/Top";

# daemonize
unless( $opt_f ){
    # The victor daemon mounts obscure in air,
    # While the ship sails without the pilot's care.
    #   -- Virgil, Aeneid
    close STDIN;
    close STDOUT;
    close STDERR;
    open( STDIN,  "/dev/null" );
    open( STDOUT, "/dev/null" );
    open( STDERR, "/dev/null" );
    fork && exit;
    setsid();
}

$SIG{PIPE} = 'IGNORE';
$SIG{HUP} = $SIG{QUIT} = $SIG{INT} = $SIG{TERM} = sub {
    $^T = time();
    if( $childpid > 1 ){
	kill "TERM", $childpid;
	wait;
    }
    if( $_[0] eq 'HUP' ){
	# loggit? no.
    }else{
	loggit( "parent caught signal SIG$_[0] - exiting", 1 );
	exit;
    }
};

$0 = "$NAME";

while(1){

    $^T = time();
    $mainpid = $$;
    if( !$opt_f && ($childpid = fork) ){
        # parent
	# parent blocks in wait, then reforks child
        while( 1 ){
            my $i;
            $i = waitpid $childpid, 0;
            next if( $i == -1 && $! == EINTR );	# => wait again
            last;				# => re-fork
        }
        next;
    }
    # child
    $SIG{HUP} = $SIG{QUIT} = $SIG{INT} = $SIG{TERM} = sub {
	return if $exitinprogress;
	$exitinprogress = 1;
	loggit( "child caught signal SIG$_[0] - exiting", 1 );
	exit;
    };
    $SIG{ALRM} = sub {};

    # for children programs
    $ENV{ARGUS_PID}  = $$;
    $ENV{ARGUS_VER}  = $::VERSION;
    $ENV{ARGUS_DATA} = $datadir;
    $ENV{ARGUS_LIB}  = '__LIBDIR__';
    $ENV{ARGUS_COOKIE} = $COOKIE = random_cookie(64);

    Conf::readconfigfiles( $opt_c || "$datadir/config" );
    Doc->check_all();

    Control->Server::new_local( "$datadir/control", oct(topconf('chmod_control')) );
    $ENV{ARGUS_CTL} = "$datadir/control";

    # load user specified perl code
    unshift @INC, "$datadir/perl";
    foreach my $m (split /\s+/, topconf('load_modules')){
	eval { require $m; };
	loggit( $@, 1 ) if $@;
    }
    # run user specified program
    system( topconf('runatstartup') ) if topconf('runatstartup');

    $^T = time();
    $starttime = $^T;
    loggit( "successful restart - $NAME running", 1 );

    if( defined &DB::reset ){
	# reset Devel::Profile if being profiled
        DB::reset();
	rename "prof.out", "prof.out.startup";
    }

    BaseIO::mainloop(
		     maxperiod => $MAX_PERIOD,
		     # run       => \&Prog::reap,	# annoys the profiler
		     );
    # not reached
}

