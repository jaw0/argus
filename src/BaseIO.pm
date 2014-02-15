# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Apr-02 09:47 (EST)
# Function: BaseIO class
#
# $Id: BaseIO.pm,v 1.59 2012/10/06 19:51:07 jaw Exp $

# low-level I/O, non-blocking, select-loop

package BaseIO;
use Fcntl;
use POSIX qw(:errno_h);
# use the high resolution timer if we have it, and we aren't profiling
# currently, only Service elapsed time uses it
BEGIN { eval{ require Time::HiRes; import Time::HiRes qw(time) }
	unless defined &DB::DB; }

use strict qw(refs vars);
use vars qw($doc @bytime);

my $MAXSTARTS  = 50;	 # max starts per loop
my $MAXTOS     = 50;	 # max timeouts per loop
my $ATFLINMAX  = 1000;   # switch from linear to binary search
my @byfile = (); 	 # objects by fd
my @byfile_dbg = ();	 # for debugging...
   @bytime = (); 	 # accessed by various other places
			 # [ { time, elem[ { time, obj, func, args, text } ] }, ...]
my $rfds   = "\0\0\0\0"; # fds that want read
my $wfds   = "\0\0\0\0"; # fds that want write
my @timeouts = (); 	 # objects sorted by timeout. same shape as @bytime
my $loopdebug = 0;
my $nfd    = 0;		 # number of active file-descriptors (aprox)

# add_timed speed up
my( $addtimed_time, $addtimed_index );

$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [ ],
    methods => {
	wantread   => {
	    descr => 'set the want read parameter',
	},
	wantwrit   => {
	    descr => 'set the want write parameter',
	},
	settimeout => {
	    descr => 'set the timeout time',
	},
	readable   => {
	    descr => 'Called once the object becomes readable',
	    attrs => ['virtual'],
	},
	writable   => {
	    descr => 'Called once the object becomes writable',
	    attrs => ['virtual'],
	},
	timeout    => {
	    descr => 'Called once the object timeouts waiting to become readable or writable',
	    attrs => ['virtual'],
	},
	add_timed_func => {
	    descr => 'Add a function to run at a specified time',
	},
	clear_timed_funcs => {
	    descr => 'remove all currently scheduled timed functions',
	},
	shutdown   => {
	    descr => 'Called to shutdown the object',
	},
    },
    fields => {
	wantread   => {
	    descr => 'This object is waiting for data to read',
	    attrs => ['internal'],
	},
	wantwrit   => {
	    descr => 'This object is waiting to output data',
	    attrs => ['internal'],
	},
	fd         => {
	    descr => 'The objects filehandle',
	    attrs => ['internal'],
	},
	type       => {
	    descr => 'descriptive name of object type, for debugging',
	},
	timeout    => {
	    descr => 'When should object stop waiting',
	    attrs => ['internal'],
	},
	opentime => {
	    descr => 'When the file descriptor was last opened',
	    #         not cleared on close, for debugging
	},

      # baseio stats
      bios::reads    => {},
      bios::writes   => {},
      bios::timeouts => {},
      bios::timefs   => {},
      bios::inits    => {},
      bios::shuts    => {},
      bios::settos   => {},
      bios::addtfs   => {},
    },
};

################################################################
# public object methods
################################################################

sub wantread {
    my $me = shift;
    my $wm = shift;

    return unless defined $me->{fd};
    vec($rfds, fileno($me->{fd}), 1) = $wm;
    $me->{wantread} = $wm;
}

sub wantwrit {
    my $me = shift;
    my $wm = shift;

    return unless defined $me->{fd};
    vec($wfds, fileno($me->{fd}), 1) = $wm;
    $me->{wantwrit} = $wm;
}


sub timedarray_insert {
    my $a = shift;
    my $n = shift;
    my $i = shift;
    my $t = shift;
    my $e = shift;

    # insert at, or before $i
    if( $i == @$a ){
	# at end
	push @$a, { $n => $t, elem => [$e] };
    }elsif( $a->[$i]{$n} == $t ){
	# append to existing bucket
	push @{$a->[$i]{elem}}, $e;
    }else{
	# insert new bucket
	splice @$a, $i, 0, { $n => $t, elem => [$e] };
    }
}

sub settimeout {
    my $me = shift;
    my $t  = shift;

    # arg is deltaT
    # 0 removes timeout

    unless( $t ){
	$me->remove_timeout();
	return;
    }

    # make t absolute, return if unchanged
    $t = int( $t + $^T );

    return if $t == $me->{timeout};

    if( $me->{timeout} ){
	# remove existing entry
	$me->remove_timeout();
    }

    # add
    my $i = 0;
    $me->{timeout} = $t;

    # put where?
    $i = ::binary_search(\@timeouts, 'timeout', $t);

    # insert at, or before $i
    timedarray_insert(\@timeouts, 'timeout', $i, $t, $me);

    $me->{bios}{settos} ++;

}

sub remove_timeout {
    my $me = shift;

    return unless $me->{timeout};

    my $i = ::binary_search(\@timeouts, 'timeout', $me->{timeout});
    my @e = grep { $_ != $me } @{$timeouts[$i]{elem}};
    $timeouts[$i]{elem} = \@e;
    delete $me->{timeout};
}


# initialize fd
sub baseio_init {
    my $me = shift;
    my $f  = $me->{fd};

    $me->{bios}{inits} ++;
    if( $f ){
	my $n = fileno($f);
	$me->{opentime} = $^T;
	$byfile[ $n ]     = $me;
	$byfile_dbg[ $n ] = $me;
	$me->setnbio();
	$nfd ++;
    }else{
	::warning( "basio_init called on invalid fd " .
		   ($me->can('unique') ? $me->unique() : 'unknown') );
    }
}

sub te_info {
    my $x = shift;

    my $t = $x->{text};

    if( $x->{text} eq "cron" ){
        $x .= "/$x->{obj}{cron}{freq} - $x->{obj}{cron}{text}";
    }
    elsif( $x->{obj} && $x->{obj}->can('unique') ){
        $t .= " " . $x->{obj}->unique();
    }

    return $t;
}

# { time func text }
sub add_timed_func {
    my $me = shift;
    my @param = @_;
    my( $t );

    $t = { @param };
    $t->{obj} = $me;
    my $tt = int $t->{time};

    unless( $tt && $tt >= $^T ){
	my $c = ref $me;
	::sysproblem( "BUG in module $c - attempt to schedule in the past (req=$tt now=$^T)");
	return;
    }
    $me->{bios}{addtfs} ++;

    # handle trivial case: bytime is empty
    unless( @bytime ){
	@bytime = ( { time => $tt, elem => [ $t ] } );
	return;
    }

    # QQQ - profiler says that add_timed_func "needs to be better"
    # sort is O(n log(n)) (but in C), but the data is already sorted
    # is just finding proper spot and inserting faster - O(n) (but perl)
    # Yes - 0.0014s -> 0.0004s

    # with huge configs, the profiler once again
    # says that even this was too slow.
    # at 10000 services, we spend 95% of our time here
    # => switching to a 2 level structure that can be binary searched

    my $i;
    if( $tt == $addtimed_time && $addtimed_index < @bytime ){
	# oftentimes, many srvcs with the same freq finish at the same time
	# eg. bulk Pings
	# they will all want to be scheduled at the same time again
	# we try to cache the index and reuse
	$i = $addtimed_index;

	# check that we hit
	$i = undef unless $addtimed_time == $bytime[$i]{time};
    }

    unless(defined $i){
	$i = ::binary_search(\@bytime, 'time', $tt);
	$addtimed_time  = $tt;
	$addtimed_index = $i;
    }

    # insert at, or before $i
    timedarray_insert(\@bytime, 'time', $i, $tt, $t);
}


# remove from schedule
sub clear_timed_funcs {
    my $me = shift;
    my $st = shift;

    $st = int($st);
    foreach my $t (@bytime){
        next if $st && $st != $t->{time};
	foreach my $x ( @{$t->{elem}} ){
	    next unless $x;
	    $x = undef if $x->{obj} == $me;
	}
        last if $st && $st < $t->{time};
    }
}

# all done with fd
sub shutdown {
    my $me = shift;
    my $fd = $me->{fd};

    $me->{bios}{shuts} ++;
    $me->settimeout(0) if $me->{timeout};
    return unless $fd;
    $me->wantread(0);
    $me->wantwrit(0);
    $byfile[ fileno($fd) ] = undef;
    delete $me->{fd};
    close $fd;
    $nfd -- if $nfd;
}

sub recycle {
    my $me = shift;

    $me->shutdown();
    $me->clear_timed_funcs();
}

################################################################

# readable/writable/timeout should be overridden in subclasses if used
sub readable {
    my $me = shift;
    my $class = ref($me);

    ::warning("BUG ALERT - read from $class (output-only)! ignoring");
    -1;
}

sub writable {
    my $me = shift;
    my $class = ref($me);

    ::warning("BUG ALERT - write to $class (input-only)! ignoring");
    -1;
}

sub timeout {
    my $me = shift;
    my $class = ref($me);

    ::warning("BUG ALERT - timeout in $class (input-only)! ignoring");
    -1;
}

################################################################
# private object methods
################################################################

sub setnbio {
    my $me = shift;

    my $fh = $me->{fd};
    # QQQ - is this portable?
    fcntl($fh, F_SETFL, O_NDELAY);
}

################################################################
# class methods
################################################################

# return an anonymous filehandle
sub anon_fh {
    do { local *FILEHANDLE };
}

sub closeall {

    foreach my $x (@byfile){
	close $x->{fd} if $x->{fd};
    }
}

sub ctime { time() };

sub nfds {
    # scalar grep {$_} @byfile;
    $nfd;
}
sub maxfds {
    scalar @byfile;
}

################################################################
# private
################################################################

# return ($rfds, $wfds, $to)
# with the re-write of wantread/wantwrit this needs only find the TO
sub selectwhat {
    my( $t, $bt );

    $t = $timeouts[0]->{timeout} if( @timeouts );
    if( @bytime ){
	$bt = $bytime[0]->{time};
	$t  = $bt if( !$t || ($bt < $t) );
    }
    ($rfds, $wfds, $t);
}

# now private
# dispatch readable/writable/timeout based on values returned by select
sub dispatch {
    my $rfd = shift;
    my $wfd = shift;
    my( $i, $n, $nc, $m, $x, $xr, $xw, $rs, $ws, $ts, $fs, @hrd );

    $xr = $rfds; $xw = $wfds;
    # most fd's will not be ready, check 8 at a time
    $nc = int( (@byfile + 7) / 8 );
    for( $n=0; $n < $nc; $n++ ){

	if( vec($rfd, $n, 8) ){
	    for($i=0; $i<8; $i++){
		$m = $n * 8 + $i;
		if( vec($rfd, $m, 1) ){
		    $x = $byfile[ $m ];
		    if( $x ){
			$x->{bios}{reads} ++;
			$rs ++;
			$x->readable();
			$hrd[$m] = 1;	# to prevent warn below if object shutsdown
                        ::dbg_svc_not_sched("read $x " . ($x->can('unique') ? $x->unique() : '-'));
		    }elsif( $^W ){
			vec($rfds, $m, 1) = 0;
			::warning( "BUG? unknown file handle $m returned from select/r - IGNORING" );
			::warning( "...fd $m was set in rfds" )
			    if vec($xr, $m, 1);
			::warning( "...perhaps by $byfile_dbg[$m]=" .
				   ($byfile_dbg[$m]->can('unique') ?
				    $byfile_dbg[$m]->unique() : 'unknown'))
			    if $byfile_dbg[$m];
		    }
		}
	    }
	}

	if( vec($wfd, $n, 8) ){
	    for($i=0; $i<8; $i++){
		$m = $n * 8 + $i;
		if( vec($wfd, $m, 1) ){
		    $x = $byfile[ $m ];
		    if( $x ){
			$x->{bios}{writes} ++;
			$ws ++;
			$x->writable();
                        ::dbg_svc_not_sched("write $x " . ($x->can('unique') ? $x->unique() : '-'));
		    }elsif( $hrd[$m] ){
			# object must have shutdown during readable
			# no warn
		    }elsif( $^W ){
			vec($wfds, $m, 1) = 0;
			::warning( "BUG? unknown file handle $m returned from select/w - IGNORING" );
			::warning( "...fd $m was set in wfds" )
			    if vec($xw, $m, 1);
			::warning( "...perhaps by $byfile_dbg[$m]=" .
				   ($byfile_dbg[$m]->can('unique') ?
				    $byfile_dbg[$m]->unique() : 'unknown'))
			    if $byfile_dbg[$m];
		    }
		}
	    }
	}
    }

    $ts = timedarray_dispatch(\@timeouts, 'timeout', $MAXTOS, \&timeouts_timed_dispatch);
    $fs = timedarray_dispatch(\@bytime,   'time', $MAXSTARTS, \&bytime_timed_dispatch);

    print STDERR "dispatched: r=$rs, w=$ws, to=$ts, fs=$fs\n" if $loopdebug;
    # $loopdebug = 1 unless $rs + $ws + $ts + $fs;
}

sub timeouts_timed_dispatch {
    my $x = shift;
    delete $x->{timeout};
    $x->{bios}{timeouts} ++;
    $x->timeout();
}

sub bytime_timed_dispatch {
    my $x = shift;
    $x->{obj}{bios}{timefs} ++;
    $x->{func}->( $x->{obj}, $x->{args} );
}

sub timedarray_dispatch {
    my $a = shift;
    my $n = shift;
    my $max = shift;
    my $f = shift;

    my $done = 0;

    while( @$a && $a->[0]{$n} <= $^T ){
	my $o = $a->[0];
	my $e = $o->{elem};
	while( @$e ){
	    my $x = shift @$e;
	    next unless $x;	# skip hole
	    $f->($x);
	    $done++;
            ::dbg_svc_not_sched("timed $x " . te_info($x) );

	    # prevent resource starvation under load
	    return if $max && $done > $max;
	}

        if( $o == $a->[0] ){
            shift @$a;
        }else{
            # something was added
            @$a = grep { $_ != $o } @$a;
        }
    }
}

# with a large config, the large startup delay
# may cause lots of services to be ready all at once
# and the huge surge will hurt
# reschedule them
sub initial_resched {

    my $rs = 0;
    while( @bytime && $bytime[0]{time} <= $^T ){
	my $e = $bytime[0]{elem};
	while( @$e ){
	    my $x = shift @$e;
	    next unless $x;	# skip hole
	    my $o = $x->{obj};

	    if( $o->can('reschedule') ){
		# services - reschedule
		$o->reschedule();
		$rs ++;
	    }else{
		# other things - run
		$o->{bios}{timefs} ++;
		$x->{func}->( $o, $x->{args} );
	    }
	}

	shift @bytime;
    }

    ::loggit( "rescheduled $rs services to improve startup" ) if $rs;
}

sub xxxmainloop {
    my %param = @_;
    my( $pt, $pl );

    $::idletime  = 0;
    $::loopcount = 0;
    $pt = $^T = $::TIME = time();
    while(1){
	oneloop( %param );

	if( $pt != $^T ){
	    my $dl = $::loopcount - $pl;
	    my $dt = $^T - $pt;
	    my $rl = $dl / $dt;

	    if( $rl > 100 ){
		print STDERR "rl: $rl, dt: $dt, dl: $dl\n";
		$loopdebug = 1;
	    }else{
		$loopdebug = 0;
	    }

	    $pl = $::loopcount;
	    $pt = $^T;
	}
    }
}

# aka 'the program'
sub mainloop {
    my %param = @_;

    $^T = $::TIME = time();
    initial_resched();

    $::idletime  = 0;
    $::loopcount = 0;
    $^T = $::TIME = time();
    while(1){
	oneloop( %param );
    }
}

sub oneloop {
    my %param = @_;
    my( $i, $ti );

    # chk_schedule();
    my ($r, $w, $t) = selectwhat();
    if( $t ){
	$t -= $^T;
	$t = $param{maxperiod} if $param{maxperiod} && ($t > $param{maxperiod});
    }else{
	$t = $param{maxperiod};
    }
    $t = 1 if $t < 1;

    $^T = $ti = $::TIME = time();
    print STDERR "selecting: ", ::hexstr($r), ", ", ::hexstr($w), ", $t\n" if $loopdebug;
    $i = select($r, $w, undef, $t);
    print STDERR "selected:  ", ::hexstr($r), ", ", ::hexstr($w), ", $i\n" if $loopdebug;

    $^T = $::TIME = time();
    $::idletime  += $::TIME - $ti;
    $::loopcount ++;
    if( $i == -1 ){
	::sysproblem( "select failed: $!" ) unless $! == EINTR;
	return;
    }

    dispatch($r, $w);
    # $param{run}->() if $param{run}; # need to keep the profiler happy
    # Prog::reap();  # moved to cron - better performance if argus is busy
}

# try debugging a scheduling issue
sub chk_schedule {
    my( $lt, $er );

    return;

    # RSN - rewrite for new bytime structure

    foreach my $x (@bytime){
	next unless $x;
	$er = 1 if $lt && $lt > $x->{time};
	$lt = $x->{time};
    }
    if( $er ){
	print STDERR "schedule corrupt!\n";
	dump_schedule();
    }
}

sub dump_schedule {

    print STDERR "dumping schedule\n";
    open(X, ">/tmp/sched.dump");

    foreach my $t (@bytime){
	unless( $t ){
	    print X "** empty slot!\n";
	    next;
	}
	print X "==== bucket $t => $t->{time} ====\n";

	unless( $t->{elem} ){
	    print X "** elem slot empty!\n";
	    print X join('; ', map { "$_ => $t->{$_}" } keys %$t), "\n";
	    next;
	}
	unless( @{$t->{elem}} ){
	    print X "*** elem slot 0 elems\n";
	    next;
	}
	foreach my $x ( @{$t->{elem}} ){
	    if( !$x ){
		print X "[] empty elem slot\n";
		next;
	    }
	    print X "[", scalar(localtime($x->{time})) , "] $x->{text}";
            print X te_info($x), "\n";
	}
    }
    close X;
}

# rebuild various data structures
sub janitor {
    my( @sched );

    foreach my $x (@bytime ){
	next unless $x;
	my @e = grep{ defined $_ } @{$x->{elem}};
	next unless @e;
	$x->{elem} = \@e;
	push @sched, $x;
    }
    @bytime = sort {$a->{time} <=> $b->{time}} @sched;
}

################################################################
# these functions provide useful debugging info

sub cmd_filinfo {
    my $ctl = shift;

    my $tot = @byfile;
    my $act = scalar grep {defined $_} @byfile;

    $ctl->ok();
    $ctl->write("active: $act\n");
    $ctl->write("total:  $tot\n");
    $ctl->write("nfd:    $nfd\n");
    $ctl->final();
}

sub cmd_files {
    my $ctl = shift;
    my( $i, $x );

    $ctl->ok();

    my $sl = fileno(Sys::Syslog::SYSLOG);

    # fileno type [age] read/write/to uniquename

    for($i=0; $i<=$#byfile; $i++){
	if( $byfile[$i] && $byfile[$i]{fd} ){
	    $x = $byfile[$i];
	    $ctl->write( "$i $x->{type}  [". ($^T - $x->{opentime}) .
			 "]  $x->{wantread}/$x->{wantwrit}/" .
			 ($x->{timeout} ? $x->{timeout} - $^T: 0) );
	    $ctl->write( " " . $x->unique() ) if $x->can( 'unique' );
	    $ctl->write( "\n" );
	}elsif( $i <= 2 ){
	    $ctl->write("$i system-stdio\n");
	}elsif( $i == $sl ){
	    $ctl->write("$i system-syslog\n");
	}
    }
    $ctl->final();
}

# What's here? the portrait of a blinking idiot,
# Presenting me a schedule! I will read it.
#   -- Shakespeare, Merchant of Venice
sub cmd_schedule {
    my $ctl = shift;
    my $param = shift;

    my( $q, $v );

    $ctl->ok();
    $q = $param->{queue};
    $v = $param->{verbose};

    foreach my $t (@bytime){
	unless( $t ){
	    $ctl->write("** empty slot!\n") if $v;
	    next;
	}
	foreach my $x ( @{$t->{elem}} ){
	    if( !$x ){
		$ctl->write( "[] empty elem slot\n" ) if $v;
		next;
	    }
	    if( !$q || ($x->{text} eq "cron" && $x->{obj}{cron}{queue} eq $q) ){
		$ctl->write( "[". scalar(localtime($x->{time})) .
			     "] $x->{text}" );

		if( $x->{text} eq "cron" ){
		    $ctl->write( " - /". ($x->{obj}{cron}{freq} ? $x->{obj}{cron}{freq} : "at") .
				 " - $x->{obj}{cron}{text}");
		}
		elsif( $v && $x->{obj}->can('unique') ){
		    $ctl->write( " - " . $x->{obj}->unique() );
		}
		$ctl->write("\n");
	    }
	}
    }
    $ctl->final();
}

################################################################
# initialization
################################################################

Control::command_install( 'filinfo', \&cmd_filinfo,  "file info" );
Control::command_install( 'files',   \&cmd_files,    "list all open file descriptors" );
Control::command_install( 'sched',   \&cmd_schedule, "list all scheduled tasks" );
Doc::register( $doc );

1;
