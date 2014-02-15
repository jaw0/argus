# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Apr-03 08:56 (EST)
# Function: the service class
#
# $Id: Service.pm,v 1.143 2012/12/29 21:47:33 jaw Exp $

package Service;
@ISA = qw(MonEl BaseIO);

# to put fresh wood on the fire, chop fuel, carve, cook, pour out wine,
# and do all those services that poor men have to do for their betters.
#   -- Homer, Odyssey

use TCP;
use UDP;
use Prog;
use Ping;
use Self;
use DataBase;
use Argus::Color;
use Argus::Agent;
use Argus::Asterisk;
use Argus::Freeswitch;
use Argus::Compute;
use Argus::Encode;
use Argus::Archive;
use Argus::HWAB;
use Argus::MHWAB;

my $HAVE_MD5;
BEGIN {
    # these may or may not be present
    eval { require Digest::MD5;  $HAVE_MD5  = 1; };
}

use POSIX;
use strict qw(refs vars);
use vars qw(@ISA $doc $n_services $n_tested @probes);

my $ZERO_FREQ    = 60;
my $PHASE_QUANTA = 6;
$n_services   = 0;	# initialized in Conf.pm readconfig()
$n_tested     = 0;
@probes;	# this is not a useless use of a variable. it is documentation.


$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [@ISA],
    conf => {
	quotp => 0,
	bodyp => 0,
    },
    methods => {
	start   => {},
	done    => {},
	timeout => {},
	isdown  => {},
	isup    => {},
	update  => {},
    },
    html  => 'services',
    fields => {
      srvc::frequency => {
	  descr => 'how often the should the service be tested',
	  attrs => ['config', 'inherit', 'timespec'],
	  versn => '3.5',
	  default => 60,
      },
      srvc::phi     => {
	  descr => 'phase - a scheduling parameter',
      },
      srvc::retries => {
	  descr => 'number of times to retry a service before declaring it down',
	  attrs => ['config', 'inherit'],
	  default => 2,
      },
      srvc::retrydelay => {
	  # NB: can be 0 to retry immediately
	  #     default (undef) - wait until next scheduled test
	  descr => 'how soon to retry a test after a failure, instead of waiting until the next scheduled test',
	  attrs => ['config', 'inherit', 'timespec'],
	  versn => '3.5',
      },
      srvc::timeout => {
	  descr => 'how long to wait for a response before giving up',
	  attrs => ['config', 'inherit', 'timespec'],
	  default => 60,
	  versn => '3.5',
      },
      srvc::status  => { descr => 'raw status from most recent test' },
      srvc::lasttesttime => {
	  descr => 'time of last test',
      },
      srvc::nexttesttime => {
	  descr => 'time of next test'
      },
      srvc::state => {
	  descr => 'state of the test underway',
      },
      srvc::tries => {
	  descr => 'number of times tried',
      },
      srvc::reason => {
	  descr => 'reason the test failed',
      },
      srvc::result => {
	  # calculated by g_test, used as input to graphing
	  descr => 'any result data returned by the test',
      },
      srvc::dead => {
	  descr => 'is this service dead',	# for debugging
      },
      srvc::elapsed => {
	  # with very coarse resolution, unless Time::HiRes is installed
	  descr => 'how long did the test take',
      },
      srvc::showreason => {
	  descr => 'display the reason the service is down on the web page',
	  attrs => ['config', 'inherit', 'bool'],
	  default => 'no',
	  versn => '3.2',
      },
      srvc::showresult => {
	  descr => 'display the test result on the web page',
	  attrs => ['config', 'inherit', 'bool'],
	  default => 'no',
	  versn => '3.6',
      },
      srvc::finished => {
	  descr => 'for detecting buggy code',
      },

      srvc::disabled => {
	  descr => 'the test is temporarily disabled and not being run',
	  versn => '3.3',
	  # if set, should specify some indication of who or why it is disabled
	  # used by DARP, also perhaps useful to toggle via argusctl or cron
      },

      srvc::invert_status => {
	  attrs => ['config', 'bool'],
	  versn => '3.3',
      },

      srvc::__demo_is_force => {
	  attrs => ['config', 'inherit'],
	  versn => '3.5',
      },

      # generic test calculations
      test::snmpcalc => {
	  descr => 'deprecated, use calc instead',
	  attrs => ['config', 'deprecated'],
	  versn => '3.2',
      },
      test::calc => {
	  descr => 'manipulate value in some manner(s): ave: calculate the average value over time; rate: calculate the rate at which a value changes; bits: multiply result by 8; jitter: calculate the deviation of a value over time',
	  attrs => ['config'],
	  # ave, rate, jitter, bits, delta, inet, one
	  # one - only interesting for debugging
	  exmpl => 'rate, ave, bits',
	  versn => '3.2',
	  html  => 'xtservices',
      },
      test::calc_sigfigs => {
	  descr => 'significant figures',
	  attrs => ['config'],
	  versn => '3.6',
	  html  => 'xtservices',
	  default => 8,
      },
      test::perlexpr => {
	  descr => 'manipulate value in some manner with perl',
	  attrs => ['config'],
	  exmpl => 'log($value) * 4',
	  versn => '3.3',
	  html  => 'xtservices',
      },
      test::alpha => {
	  descr => 'time constant for decaying average (and jitter) calculation',
	  # ave = (alpha * ave + value) / (alpha + 1)
	  # if you don't understand, leave it alone
	  attrs => ['config', 'inherit'],
	  default => '1',
	  versn => '3.2',
	  html  => 'xtservices',
      },
      test::pluck => {
	  # we process the value with the regex, and replace with $1
	  descr => 'use this regex to pluck a value to test out of the result. should contain ()s',
	  attrs => ['config'],
	  exmpl => '\s+(\d+)%',
	  versn => '3.2',
	  html  => 'xtservices',
      },
      test::unpack => {
	  # in standard perl unpack syntax $value = unpack($unpack, $value)
	  descr => 'a perl unpack template for unpacking a binary data structure',
	  attrs => ['config'],
	  exmpl => 'x8 N',
	  versn => '3.2',
	  html  => 'xtservices',
      },
      test::scale => {
	  # $value /= $scale
	  descr => 'apply a scale factor',
	  attrs => ['config'],
	  versn => '3.2',
	  html  => 'xtservices',
      },
      test::spike_supress => {
	  descr => 'supress transient spikes',
	  attrs => ['config', 'inherit'],
	  default => 1,
	  versn => '3.4',
      },
      test::rawvalue => {
	  descr => 'initial raw value for test',
      },
      test::calcdata => {
	  descr => 'assorted data',
      },
      test::currvalue => {
	  descr => 'most recent value returned by query (rawvalue after processing)',
      },
      test::testedp => {
	  descr => 'is there a test configured?',
      },

      # generic test value fields
      test::expect => {
	  descr => 'test value - fail test if value does not match regex',
	  attrs => ['config'],
      },
      test::nexpect => {
	  # I'm not sure that this is useful, but it provides symmetry
	  descr => 'test value - fail test if value does match regex',
	  attrs => ['config'],
	  versn => '3.2',
	  html  => 'xtservices',
      },
      test::minvalue => {
	  descr => 'test value - fail test if value falls below this',
	  attrs => ['config'],
	  versn => '3.2',
	  html  => 'xtservices',
      },
      test::maxvalue => {
	  descr => 'test value - fail test if value rises above this',
	  attrs => ['config'],
	  versn => '3.2',
	  html  => 'xtservices',
      },
      test::eqvalue => {
	  descr => 'test value - fail test if value does not equal this',
	  attrs => ['config'],
	  versn => '3.2',
	  html  => 'xtservices',
      },
      test::nevalue => {
	  descr => 'test value - fail test if value equals this',
	  attrs => ['config'],
	  versn => '3.2',
	  html  => 'xtservices',
      },
      # changing hwab model or period will cause the forecaster to reset
      test::hwab_model  => {
          descr => 'holt-winters seasonal growth model: additive, multiplicative',
	  attrs => ['config', 'inherit'],
          vals  => ['additive', 'multiplicative'],
          default => 'additive',
	  versn => '3.7',
	  html  => 'hwab',
      },
      test::hwab_period  => {
          descr => 'holt-winters seasonal period',
	  attrs => ['config', 'inherit', 'timespec'],
          default => 7 * 24 * 3600,
	  versn => '3.7',
	  html  => 'hwab',
      },
      test::hwab_alpha => {
          descr	=> 'holt-winters alpha parameter',
	  attrs => ['config', 'inherit'],
          default => 0.005,
	  versn => '3.7',
	  html  => 'hwab',
      },
      test::hwab_beta => {
          descr	=> 'holt-winters beta parameter',
	  attrs => ['config', 'inherit'],
          default => 0.0005,
	  versn => '3.7',
	  html  => 'hwab',
      },
      test::hwab_gamma => {
          descr	=> 'holt-winters gamma parameter',
	  attrs => ['config', 'inherit'],
          default => 0.1,
	  versn => '3.7',
	  html  => 'hwab',
      },
      test::hwab_zeta => {
          descr	=> 'holt-winters zeta parameter',
	  attrs => ['config', 'inherit'],
          default => .1,
	  versn => '3.7',
	  html  => 'hwab',
      },
      test::maxdeviation => {
          descr	=> 'maximum holt-winters deviation - fail if more deviant',
	  attrs => ['config'],
	  versn => '3.7',
	  html  => 'hwab',
      },

      graphd::gr_nmax_samples => {
	  descr => 'number of sample data points to store in the graph data file',
	  attrs => ['config', 'inherit'],
	  default => 2048,
	  versn => '3.5',
	  html  => 'graphing',
      },
      graphd::gr_nmax_hours => {
	  descr => 'number of hourly summary data points to store in the graph data file',
	  attrs => ['config', 'inherit'],
	  default => 1024,
	  versn => '3.5',
	  html  => 'graphing',
      },
      graphd::gr_nmax_days => {
	  descr => 'number of daily summary data points to store in the graph data file',
	  attrs => ['config', 'inherit'],
	  default => 1024,
	  versn => '3.5',
	  html  => 'graphing',
      },
      graphd::samples_min_time => {
	  descr => 'minimum time bewteen samples',
	  attrs => ['config', 'inherit', 'timespec'],
	  default => 120,
	  versn => '3.7',
	  html  => 'graphing',
      },

      'schedule::schedule testing' => {
          descr => 'schedule specifying when to/not to test',
          attrs => ['config', 'inherit', 'sched'],
          versn => '3.7',
          html  => 'schedule',
      },
      'schedule::schedule checking' => {
          # ignore result + consider up
          descr => 'schedule specifying when to/not to check result',
          attrs => ['config', 'inherit', 'sched'],
          versn => '3.7',
          html  => 'schedule',
      },

      srvc::starts  => {},
      srvc::dones   => {},
      srvc::alsorun => {},
      srvc::result_valid => {},

    },
};

for my $test (qw(minvalue maxvalue eqvalue nevalue expect nexpect maxdeviation)){
    my %d = %{ $doc->{fields}{"test::$test"} };
    $d{versn} = '3.6' if $d{versn} < 3.6;
    for my $sev (qw(critical major minor warning)){
	$doc->{fields}{"test::$test.$sev"} = \%d;
    }
}


sub config {
    my $me = shift;
    my $cf = shift;
    my $more = shift;
    my( $k, $kk, $v, $p, $best, $pa );

    # What services canst thou do?
    #   -- Shakespesare, King Lear
    # probe, find best match
    foreach $p (@probes){
	my $c = $p->( $me->{name} );
	if( $c ){
	    # probe returns undef or [match, \&config]
	    $best = $c if( !$best || $c->[0] > $best->[0] );
	}
    }

    # service specification errors should only abort this service, trap any errors
    eval {
	# config from best matching probe
	if( $best ){
	    $best->[1]->($me, $cf, $more);
	}else{
	    $cf->error( "unknown service '$me->{name}'" );
	}
    };
    if( $@ ){
	print STDERR "$@\n" if $::opt_f && !ref($@);
	return undef;
    }

    $me->init_from_config( $cf, $doc, 'srvc' );
    $me->init_from_config( $cf, $doc, 'graphd' );
    $me->init_from_config( $cf, $doc, 'test' );
    $me->init_from_config( $cf, $doc, 'schedule' );

    # frequency = 0 is not permitted
    $me->{srvc}{frequency}  ||= $ZERO_FREQ;

    # if we have lots of services, spread them around a bit more...
    $me->{srvc}{phi} = int(rand($me->{srvc}{frequency}));

    $me->{uname} ||= $me->{name};
    return undef unless $me->init($cf);  # == MonEl::init

    $me->generic_test_config($cf);
    $me->hwab_config($cf);

    # the default is different for Service, set if not specified in config
    $me->{notify}{sendnotify} = 1 unless defined $me->{notify}{sendnotify};

    # randomize when test runs if looking at elapsed timing
    $me->{srvc}{random_phi} = 1 if ($me->{srvc}{calc} =~ /elapsed/) || ($me->{image}{gr_what} eq 'elapsed');

    $me->warning( "test frequency is less than retrydelay" )
	if $me->{srvc}{retrydelay} && $me->{srvc}{frequency} < $me->{srvc}{retrydelay};

    if( $me->{srvc}{invert_status} ){
	$me->{flags} .= ' status-inverted';
    }

    # initialize summary data
    $me->{ovstatussummary} = { $me->{ovstatus} => 1, total => 1, severity => $me->{currseverity} };

    $n_services ++;
    $me->reschedule();
    $me->configured();

    $me;
}

sub configured {}

sub reschedule {
    my $me  = shift;
    my $dly = shift;

    my $when;
    my $f = $me->{srvc}{frequency};

    # My fellow-scholars, and to keep those statutes
    # That are recorded in this schedule here:
    #   -- Shakespeare, Loves Labors Lost
    if( $dly ){
	$when = $^T + $dly;
    }elsif( $me->{srvc}{tries} && defined($me->{srvc}{retrydelay}) ){
	$when = $^T + $me->{srvc}{retrydelay};
    }else{
        $me->{srvc}{phi} = int(rand( $me->{srvc}{frequency} )) if $me->{srvc}{random_phi};
	my $p = $me->{srvc}{phi};
    	$when = int( ($^T - $p) / $f ) * $f + $f + $p;
        $when += $f if $when <= $^T;
    }

    # if we ran a test early, delay the next one a bit
    if( $me->{srvc}{delaynext} ){
	$when += $f if $when < $^T + $f;
	delete $me->{srvc}{delaynext};
    }

    if( $me->{srvc}{nexttesttime} <= $when ){
	$me->{srvc}{nexttesttime} = $when;
	$me->add_timed_func( time => $when,
			     text => 'service start',
			     func => \&me_start,
			     );
    }else{
	my $c = ref $me;
	::sysproblem( "BUG in module $c - " . $me->unique() . " reschedule failed" );
    }
}

sub me_start {
    my $me = shift;

    # is checknow running?
    return if $me->{srvc}{state} && $me->{srvc}{state} ne 'done';
    $me->pre_start_check();
}

sub monitored_now {
    my $me = shift;

    if( my $s = $me->{schedule}{testing} ){
        unless($s->permit_now()){
            $me->debug("skipping test - testing not currently scheduled");
            return 0;
        }
    }
    return 1;
}

sub pre_start_check {
    my $me = shift;

    return $me->reschedule() if $me->{srvc}{disabled};

    # throttle back if we are going to run out of fds
    my $maxf = ::topconf('max_descriptors');
    if( $maxf && $maxf <= BaseIO::nfds() ){
	$me->debug("file descriptor limit reached - delaying check");
	return $me->reschedule(1);
    }

    return $me->reschedule() unless $me->monitored_now();

    $me->start();
}

sub about_more {
    my $me = shift;
    my $ctl = shift;
    my( $b, $k, $v );

    $me->more_about_whom($ctl, 'srvc', 'test', 'test::calcdata', 'graphd');
    $me->more_about_whom($ctl, 'hwab::expect') if $me->{hwab};

}

sub start {
    my $me = shift;
    my $s  = $me->{srvc};

    # if( $me->{srvc}{dead} ){
    # 	  trace();
    # }

    undef $s->{finished};
    $s->{state} = 'starting';
    $s->{lasttesttime}  = BaseIO::ctime();
    $s->{starttesttime} = 0;
    $s->{tries} = 1 unless $s->{tries};
    $me->debug( 'Service start' );
    $n_tested ++;
    $s->{starts} ++;
}

sub done {
    my $me = shift;
    my $s  = $me->{srvc};

    $me->shutdown();
    $s->{state} = 'done';
    $s->{dones} ++;
    $me->debug( 'Service done' );

    if( $s->{showresult} && $s->{result_valid} && ($s->{result} ne $s->{prevresult}) ){
	# user wants to display result. force web page rebuild.
	$me->{web}{transtime} = $^T;
	$s->{prevresult} = $s->{result};
    }

    if( $s->{finished} ){
	my $c = ref $me;
	::sysproblem( "BUG in module $c - " . $me->unique() . " finished twice" );
    }else{
	$s->{finished} = 1;
	$me->reschedule() unless $s->{dead};
    }
}

sub run_alsoruns {
    my $me = shift;

    if( $me->{srvc}{alsorun} ){
	for my $s ( @{$me->{srvc}{alsorun}} ){
	    $s->_maybe_start_now();
	}
    }
}

sub recycle {
    my $me = shift;

    $n_services --;
    $me->{srvc}{dead} = 1;
    delete $me->{srvc}{alsorun};
    $me->MonEl::recycle();
    $me->BaseIO::recycle();
}

sub isdown_f {	# force it
    my $me = shift;

    $me->{srvc}{tries} = $me->{srvc}{retries} + 1;
    $me->isdown( @_ );
}

sub isdown {
    my $me = shift;
    my $reason = shift;
    my $altval = shift;
    my $sever  = shift;
    my $s  = $me->{srvc};

    return $me->isup('forced') if $s->{__demo_is_force} eq 'up';

    if( my $s = $me->{schedule}{checking} ){
        return $me->isup() unless $s->permit_now();
    }

    $s->{elapsed} = 0;
    $s->{reason}  = $reason;
    $s->{status}  = 'down';
    $s->{result_valid} = 1 if exists $s->{result};

    if( defined($altval) && exists($s->{result}) ){
	# to make %v in notifications more useful
	$s->{result}  = $altval;
	# but don't use it to Compute or graph
	$s->{result_valid} = 0;
    }

    $me->debug( "Service DOWN - $reason" ) if $reason;

    if( ($s->{tries} || 0) <= $s->{retries} ){
	# Sometimes to do me service: nine or ten times
	#   -- Shakespeare, Othello
	$me->debug( 'Service - retrying' );
	$s->{tries} ++;
    }else{
	# For some displeasing service I have done
	#   -- Shakespeare, King Henry IV
	$me->debug( 'Service DOWN' );
	$s->{tries} = 0;
	$me->update( $s->{invert_status} ? 'up' : 'down', $sever );
    }

    $me->graph_add_sample( $s->{result}, $me->{ovstatus} ) if $me->{graph} && $s->{result_valid};
    $me->archive_log_data();
    $me->run_alsoruns();
    $me->done();
}

sub isup {
    my $me = shift;
    my $s  = $me->{srvc};

    return $me->isdown('forced') if $s->{__demo_is_force} eq 'down';

    $me->debug( 'Service - UP' );
    $s->{elapsed} = $::TIME - ($s->{starttesttime} || $s->{lasttesttime});
    $s->{reason} = undef;
    $s->{tries} = 0;
    $s->{status} = 'up';
    $s->{result_valid} = 1;

    $me->update( $s->{invert_status} ? 'down' : 'up' );

    $me->graph_add_sample( $s->{result}, $me->{ovstatus} ) if $me->{graph};
    $me->archive_log_data();
    $me->run_alsoruns();
    $me->done();
}

sub update {
    my $me = shift;
    my $st = shift;
    my $sv = shift;
    my $ov = shift;

    $me->{srvc}{status} = $st;

    $sv ||= $me->{severity};
    $sv = 'clear' if $st eq 'up';

    if( ($st ne $me->{status}) || ($sv ne $me->{currseverity})
          || (($ov || $st) ne $me->{ovstatus}) ){
	$me->transition( $st, $sv, $ov );
    }
}

# override MonEl::transition and jiggle
sub transition {
    my $me = shift;
    my $st = shift;
    my $sv = shift;
    my $ov = shift;

    if( $st eq 'down' && $me->{watch} && $me->{watch}{callback} ){
	$me->{watch}{callback}->( $me );
	return;
    }

    if( $st ){
	my $ps = $me->{status};
	my $po = $me->{ovstatus};
	my $pv = $me->{currseverity};
	$me->{status}    = $st;
	$me->{ovstatus}  = $ov || $st;
	$me->{transtime} = $^T;
	# these may get cleared in t2 if there is an override
	$me->{currseverity} = ($me->{status} eq 'down') ? ($sv || $me->{severity}) : 'clear';
	$me->{alarm}        = $me->alarming_p();

	$me->transition2();

	$me->{prevstatus}   = $ps;
	$me->{prevovstatus} = $po;
	$me->{prevseverity} = $pv;
	my $msg = $me->{ovstatus};
	$msg .= "/$sv" if $me->{ovstatus} eq 'down';	# include severity on down
	$me->loggit( msg => $msg,
		     tag => 'TRANSITION',
		     slp => 1 ) if ($me->{prevovstatus} ne $me->{ovstatus})
	                        || ($me->{prevseverity} ne $me->{currseverity});
    }else{
	$me->{prevovstatus} = $me->{ovstatus};
	$me->{prevseverity} = $me->{currseverity};
	$me->{ovstatus}     = $me->{status};
	$me->{currseverity} = ($me->{status} eq 'down') ? ($sv || $me->{severity}) : 'clear';
	$me->transition2();
    }

    $me->{ovstatussummary} = { $me->{ovstatus} => 1, total => 1, severity => $me->{currseverity} };

    $me->transition_propagate();
}

sub jiggle {
    my $me = shift;

    $me->{currseverity} ||= ($me->{status} eq 'down') ? $me->{severity} : 'clear';

    $me->transition_propagate();
}

sub webpage {
    my $me = shift;
    my $fh = shift;
    my $topp = shift;  # NOT USED
    my( $k, $v, $vv, $kk );

    print $fh "<!-- start of Service::webpage -->\n";

    my $s = $me->{srvc};

    # object data
    print $fh "<TABLE CLASS=SRVCDTA>\n";
    foreach $k (qw(name ovstatus flags info note comment annotation details)){
	$v = $vv = $me->{$k};
	$kk = $k;

	if( $k eq 'ovstatus' ){
            my $c = web_status_color($v, $me->{currseverity}, 'back');
	    $kk = 'status';
	    $vv = qq(<span style="background-color: $c; padding-right: 4em;"><L10N $v></span>);
	}
	if( $k eq 'flags' ){
	    $vv = "<L10N $v>";
	}
	print $fh "<TR><TD><L10N $kk></TD><TD>$vv</TD></TR>\n" if defined($v);
	if( $k eq 'ovstatus' && $v eq 'down' && $s->{showreason} && $s->{reason} ){
	    print $fh "<TR><TD>...<L10N because></TD><TD>$me->{srvc}{reason}</TD></TR>\n";
	}
	if( $k eq 'ovstatus' && $me->{depend}{culprit} ){
	    # QQQ - is this really how I want to do it?
	    my $o = $MonEl::byname{$me->{depend}{culprit}};
	    print $fh "<TR><TD>...<L10N because></TD><TD>";
	    print $fh "<A HREF=\"" . $o->url('func=page') . "\">" if $o;
	    print $fh $me->{depend}{culprit};
	    print $fh "</A>" if $o;
	    print $fh " <L10N is down></TD></TR>\n";
	}
	if( $k eq 'ovstatus' && $s->{showresult} && $s->{result} && $s->{result_valid} ){
	    # display most recent result on page
	    my $txt = $s->{result};
	    $txt =~ s/&/&amp/g;
	    $txt =~ s/</&lt;/g;
	    $txt =~ s/>/&gt;/g;
	    print $fh "<TR><TD><L10N most recent></TD><TD>$txt</TD></TR>\n";
	}
    }

    $me->webpage_more($fh) if $me->can('webpage_more');
    print $fh "</TABLE>\n";

    $me->web_override($fh);

    print $fh "<!-- end of Service::webpage -->\n";
}

sub web_page_row_base {
    my $me = shift;
    my $fh = shift;
    my $label = shift;

    return if $me->{web}{hidden};
    print $fh '<TR><TD><A HREF="', $me->url('func=page'), '">',
        ($label||$me->{label_left}||$me->{name}), '</A></TD>';

    my $st = $me->{ovstatus};
    my $cl = web_status_color($st, $me->{currseverity}, 'back');
    if( $st eq 'up' ){
	print $fh "<TD BGCOLOR=\"$cl\">$st</TD><TD></TD><TD></TD>";
    }elsif( $st eq 'override' ){
	print $fh "<TD></TD><TD></TD><TD BGCOLOR=\"$cl\">$st</TD>";
    }else{
	print $fh "<TD></TD><TD BGCOLOR=\"$cl\">$st</TD><TD></TD>";
    }
    print $fh "</TR>\n";
}

sub web_page_row_top {
    my $me = shift;
    $me->web_page_row_base(@_);
}

sub hwab_config {
    my $me = shift;
    my $cf = shift;

    # configured?
    my $hwab;
    my $maxdelta;
    for my $sev (qw(critical major minor warning)){
        next unless $me->{test}{"maxdeviation.$sev"};
        $hwab = 1;
        $maxdelta = $me->{test}{"maxdeviation.$sev"} if $me->{test}{"maxdeviation.$sev"} > $maxdelta;
    }

    return unless $hwab;

    my $class = ($me->{test}{hwab_model} =~ /^m/i) ? 'Argus::MHWAB' : 'Argus::HWAB';

    $me->{hwab} = $class->new(
        $me->unique(),
        $me->{test}{hwab_period},
        $me->{test}{hwab_alpha},
        $me->{test}{hwab_beta},
        $me->{test}{hwab_gamma},
        $me->{test}{hwab_zeta},
        $maxdelta,
        sub{ $me->debug(@_) },
    );

}

sub generic_test_config {
    my $me = shift;
    my $cf = shift;

    my $sev = $me->{severity} || 'critical';

    foreach my $p (qw/expect nexpect minvalue maxvalue
		   eqvalue nevalue calc pluck unpack scale perlexpr maxdeviation/){
	$me->{test}{testedp} = 1 if defined($me->{test}{$p});
    }

    for my $test (qw(minvalue maxvalue eqvalue nevalue expect nexpect maxdeviation)){
	for my $sev (qw(critical major minor warning)){
	    $me->{test}{testedp} = 1 if defined($me->{test}{"$test.$sev"});
	}

	# compat
	$me->{test}{"$test.$sev"} ||= $me->{test}{$test} if defined $me->{test}{$test};
    }
}

sub generic_test {
    my $me    = shift;
    my $value = shift;
    my $tag   = shift;
    my( $foo, $transient );

    $me->{test}{rawvalue} = $value;

    eval {
	no strict;
	# no warnings;  # XXX - not available in 5.00503

	# 1st pre-process the value into shape
	if( $me->{test}{pluck} ){
	    # pluck a value ($1) from the result with a regex
	    my $p = $me->{test}{pluck};
	    $value =~ /$p/s;
	    $value = $1;
	}

	if( $me->{test}{unpack} ){
	    # do we need to unpack a binary value?
	    $value = unpack( $me->{test}{unpack}, $value );
	}

	if( $me->{test}{scale} ){
	    # scale value (most useful for fixing NTP fixed point values)
	    $value /= $me->{test}{scale};
	}

	if( $me->{test}{calc} =~ /md5/ ){
	    if( $HAVE_MD5 ){
		$value = Digest::MD5::md5_hex($value);
	    }else{
		$value = 'md5 not available';
	    }
	}

	$me->debug( "$tag TEST value $value" );

	# then calculate derived values
	if( $me->{test}{calc} ){

	    if( $me->{test}{calc} =~ /one/ ){
		$value = 1;
	    }
	    if( $me->{test}{calc} =~ /elapsed/ ){
		# srcv::elapsed is calculated after testing...
		$value = $::TIME - ($me->{srvc}{starttesttime} || $me->{srvc}{lasttesttime});
                $me->debug( "$tag TEST elapsed $value" );
	    }

	    if( $me->{test}{calc} =~ /rate|delta/ ){
		my( $dv, $dt );
		$value += 0;
		if( defined($me->{test}{calcdata}{lastv}) ){

		    if( $^T - $me->{test}{calcdata}{lastt} < 1 ){
			# too soon
			$me->debug("$tag TEST too soon to retest. skipping");
			return $me->done();
		    }

		    if( $value < $me->{test}{calcdata}{lastv} ){
			# handle counter issues
			if( $me->{test}{calcdata}{lastv} < 0x7FFFFFFF ){
			    # assume reboot/reset
			    $transient = 1;
			    $me->debug("$tag TEST possible reboot detected");
			}else{
			    # overflow/wrap-around
			    $dv = 0xFFFFFFFF - $me->{test}{calcdata}{lastv};
			    $dv += $value + 1;
			    $me->debug("$tag TEST counter rollover detected");
			}
		    }else{
			$dv = $value - $me->{test}{calcdata}{lastv};
		    }
		}else{
		    $transient = 1;
		    $me->debug( "$tag TEST delta startup" );
		}
		if( $me->{test}{calcdata}{lastdv} && $dv > $me->{test}{calcdata}{lastdv} * 100 ){
		    # unusually large spike, probably a reset/reboot - supress
		    if( $me->{test}{spike_supress} ){
			$transient = 1;
			$me->debug("$tag TEST supressing transient spike ($dv) ");
		    }
		    # NB: since we save this value, if it really is a valid large jump
		    # the right thing happens the next time we test
		}

		$me->{test}{calcdata}{lastv}  = $value;
		$me->{test}{calcdata}{lastdv} = $dv;

		if( $me->{test}{calc} =~ /rate/ && !$transient ){
		    $transient = 1 unless $me->{test}{calcdata}{lastt};
		    if( $transient ){
			$me->debug( "$tag TEST rate startup" );
		    }else{
			$dt = $^T - $me->{test}{calcdata}{lastt};
			$value = $dv / $dt;
		    }
		}else{
		    $value = $dv;
		}

		$me->{test}{calcdata}{lastt} = $^T;

		return $me->done() if $transient;
	    }

	    # Why birds and beasts from quality and kind,
	    # Why old men fool and children calculate,
	    #   -- Shakespeare, Julius Ceasar
	    if( $me->{test}{calc} =~ /ave|jitter/ ){
                my $dt = $^T - $me->{test}{calcdata}{lastt_ave};
                $me->{test}{calcdata}{ave} = $value unless defined $me->{test}{calcdata}{ave};
                $me->{test}{calcdata}{ave} = $value if $dt > 3 * $me->{srvc}{frequency} * $me->{test}{alpha};
                $me->{test}{calcdata}{lastt_ave} = $^T;

		# moving average
		my $iv = $value;
		my $x = $me->{test}{alpha} * $me->{test}{calcdata}{ave};
		$x += $value;
		$x /= $me->{test}{alpha} + 1;
		$me->{test}{calcdata}{ave} = $x;
		$value = $x;

		if( $me->{test}{calc} =~ /jitter/ ){
		    $value = $value - $iv;
		    $value = - $value if $value < 0;
		}
	    }


	    # Oh, Lord, bless this thy hand grenade that with it thou
	    # mayest blow thy enemies to tiny bits, in thy mercy.
	    #   -- Monty Python, Holy Grail
	    if( $me->{test}{calc} =~ /bits/ ){
		# convert Bytes -> bits
		$value *= 8;
	    }

	    if( $me->{test}{calc} =~ /inet/ ){
		# convert -> IP addr (v4)
		$value = ::xxx_inet_ntoa( pack('N',$value) );
	    }else{
		# This is a merry ballad, but a very pretty one.
		#   -- Shakespeare, Winter's Tale
		# keep sigfigs under control. make prettier.
		my $lv = ceil( log10(abs($value)) );
		my $sf = $me->{test}{calc_sigfigs};

		if( $lv < $sf && ($value != int($value)) ){
		    my $n = $sf - $lv;
		    $value = sprintf "%.${n}f", $value;
		}else{
		    $value = int $value;
		}
	    }
	}

	# done last, so user can post-diddle
	if( $me->{test}{perlexpr} ){
	    my $x = $value;
            my $elapsed = $::TIME - ($me->{srvc}{starttesttime} || $me->{srvc}{lasttesttime});

	    $value = eval $me->{test}{perlexpr};
	}

	$me->{test}{currvalue} = $value;	# to simplify debugging
	$me->{srvc}{result}    = $value;	# this is what gets handed to graphing engine, etc.
	$me->debug( "$tag TEST result $value" );

        if( $me->{hwab} ){
            $me->{hwab}->add($value);

            $me->debug("$tag TEST HWAB expect: $me->{hwab}{expect}{y}, delta: $me->{hwab}{expect}{d}")
              if $me->{hwab}{expect};
        }

	# and finally test the value
	for my $sev (qw(critical major minor warning)){

	    if( defined($me->{test}{"expect.$sev"}) ){
		my $e = $me->{test}{"expect.$sev"};
		# Thou sober-suited matron, all in black,
		# And learn me how to lose a winning match,
		#   -- Shakespeare, Romeo+Juliet
		return $me->isdown( "$tag TEST did not match expected regex", undef, $sev )
		    unless $value =~ /$e/;
	    }
	    if( defined($me->{test}{"nexpect.$sev"}) ){
		my $e = $me->{test}{"nexpect.$sev"};
		# He hath indeed better bettered expectation.
		#   -- Shakespeare, Much Ado about Nothing
		return $me->isdown( "$tag TEST matched unexpected regex", undef, $sev )
		    if $value =~ /$e/;
	    }
	    # Lesser than Macbeth, and greater.
	    #   -- Shakespeare, Macbeth
	    if( defined($me->{test}{"minvalue.$sev"}) && $value < $me->{test}{"minvalue.$sev"} ){
		return $me->isdown( "$tag TEST less than min", undef, $sev );
	    }
	    # The greater scorns the lesser
	    #   -- Shakespeare, Timon of Athens
	    if( defined($me->{test}{"maxvalue.$sev"}) && $value > $me->{test}{"maxvalue.$sev"} ){
		return $me->isdown( "$tag TEST more than max", undef, $sev );
	    }
	    # Repugnant to command: unequal match'd
	    #   -- Shakespeare, Hamlet
	    if( defined($me->{test}{"eqvalue.$sev"}) && $value != $me->{test}{"eqvalue.$sev"} ){
		return $me->isdown( "$tag TEST not equal", undef, $sev );
	    }
	    # In equal scale weighing delight and dole
	    #   -- Shakespeare, Hamlet
	    if( defined($me->{test}{"nevalue.$sev"}) && $value == $me->{test}{"nevalue.$sev"} ){
		return $me->isdown( "$tag TEST equal", undef, $sev );
	    }

            # That it descends, and deviates as far
            # From falling of a stone in line direct
            #   -- Dante, Divine Comedy
            if( defined($me->{test}{"maxdeviation.$sev"}) ){
                my $dev = $me->{hwab}->deviation($value);
                my $max = $me->{test}{"maxdeviation.$sev"};
                $me->debug("current deviation = $dev; max $sev: $max");
                if( $dev && $max > 0 && $dev > $max ){
                    return $me->isdown("$tag TEST outside of predicted range", undef, $sev);
                }
            }

	}
	if( !$me->{test}{testedp} ){
	    # if no tests are specified, result is whether we recvd data or not
	    if( length($value) ){
		return $me->isup();
	    }else{
		return $me->isdown( "$tag TEST no data rcvd" );
	    }
	}
	return $me->isup();
    };
    if($@){
	return $me->isdown( "$tag TEST failure - $@" );
    }
}

################################################################

sub graphlist {
    my $me = shift;

    return () unless $me->{graph};

    return ( {
        obj	=> $me,
        file	=> $me->pathname(),
        label	=> '',
        link	=> encode($me->unique()),
    } );
}

# instead of the scheduled time
sub _maybe_start_now {
    my $me = shift;

    return if $me->{srvc}{state} && $me->{srvc}{state} ne 'done';

    $me->clear_timed_funcs($me->{srvc}{nexttesttime});
    $me->{srvc}{nexttesttime} = undef;
    $me->me_start();
}

sub check_now {
    my $me = shift;
    $me->_maybe_start_now();
}

################################################################
sub cmd_update {
    my $ctl = shift;
    my $param = shift;

    my $x = $MonEl::byname{ $param->{object} };
    if( $x ){
	my $s = $param->{status};
	my $v = $param->{severity};

	if( $s ne 'up' && $s ne 'down' ){
	    $ctl->bummer( 500, 'invalid status' );
	}elsif( $x->can('update') ){
	    $x->update( $s, $v );
	    $ctl->ok_n();
	}else{
	    $ctl->bummer( 500, 'object not a service' );
	}
    }else{
	$ctl->bummer(404, 'Object Not Found');
    }
}

sub cmd_hwab_reset {
    my $ctl   = shift;
    my $param = shift;

    my $x = $MonEl::byname{ $param->{object} };

    unless( $x ){
        $ctl->bummer(404, 'Object Not Found');
        return;
    }

    unless( $x->{hwab} ){
        $ctl->bummer(500, 'HWAB not enabled here');
        return;
    }

    $x->{hwab}->reset();
    $ctl->ok_n();
}

################################################################
Doc::register( $doc );
Control::command_install( 'update',  \&cmd_update, 'set service status', 'object status severity' );
Control::command_install( 'hwab_reset', \&cmd_hwab_reset, 'reset hwab data', 'object');

1;

