# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Apr-02 15:03 (EST)
# Function: implement some of the control channel commands
#
# $Id: Commands.pm,v 1.30 2010/03/25 23:33:38 jaw Exp $

package Control;
use strict;
use vars qw(%cmd_docs @consoles);

# And a fair, saintly Lady called to me
# In such wise, I besought her to command me.
#   -- Dante, Divine Comedy

sub cmd_echo {
    my $ctl = shift;
    my $param = shift;
    my ($k, $v );

    $ctl->ok();
    foreach $k (keys %$param ){
	$ctl->write( "$k: $param->{$k}\n" );
    }
    $ctl->final();
}

sub cmd_status {
    my $ctl = shift;
    my $param = shift;

    # Thy wish to know me shall in sooth be granted
    #   -- Dante, Divine Comedy
    $ctl->ok();
    $ctl->write("status:    running\n");
    $ctl->write("version:   $::VERSION\n");
    $ctl->write("perlver:   " . perl_version() . "\n");
    $ctl->write("osinfo:    $::OSINFO\n")   if $::OSINFO;
    $ctl->write("darpmode:  $DARP::mode\n") if $::HAVE_DARP;

    # NB: most of this data is also available via 'Service Self/*'
    $ctl->write("objects:   ". scalar(@MonEl::all). "\n");
    $ctl->write("services:  $Service::n_services\n");
    $ctl->write("notifies:  ". Notify::number_of_notifies() . "\n");

    # either machine readable or human readable
    if( $param->{raw} ){
	$ctl->write("timenow:   $^T\n");
	$ctl->write("start:     $::starttime\n" );
	$ctl->write("idletime:  $::idletime\n");
	$ctl->write("tested:    $Service::n_tested\n");
	$ctl->write("loopcount: $::loopcount\n");
    }else{
	$ctl->write("uptime:    " . MonEl::elapsed($^T - $::starttime) . "\n" );

	if( $MonEl::statuses[1][0] ){
	    # 1 min ave, 5 min ave, 15 min ave
	    $ctl->write("idle:      ".
		      MonEl::percent($::idletime - $MonEl::statuses[1][1],
				     $::TIME - $MonEl::statuses[1][0]) . "% ".
		      MonEl::percent($::idletime - $MonEl::statuses[5][1],
				     $::TIME - $MonEl::statuses[5][0]) . "% ".
		      MonEl::percent($::idletime - $MonEl::statuses[15][1],
				     $::TIME - $MonEl::statuses[15][0]) . "%\n" );
	    $ctl->write("monrate:   " .
			sprintf("%.2f ", ($Service::n_tested - $MonEl::statuses[1][2])
				/ ($::TIME - $MonEl::statuses[1][0])) .
			sprintf("%.2f ", ($Service::n_tested - $MonEl::statuses[5][2])
				/ ($::TIME - $MonEl::statuses[5][0])) .
			sprintf("%.2f per second\n", ($Service::n_tested - $MonEl::statuses[15][2])
				/ ($::TIME - $MonEl::statuses[15][0])) );
	    $ctl->write("looprate:  " .
			sprintf("%.2f ", ($::loopcount - $MonEl::statuses[1][3])
				/ ($::TIME - $MonEl::statuses[1][0])) .
			sprintf("%.2f ", ($::loopcount - $MonEl::statuses[5][3])
				/ ($::TIME - $MonEl::statuses[5][0])) .
			sprintf("%.2f per second\n", ($::loopcount - $MonEl::statuses[15][3])
				/ ($::TIME - $MonEl::statuses[15][0])) ) if $param->{more};

	}else{
	    # haven't been running for long, ave since start
	    $ctl->write("idle:      ". MonEl::percent($::idletime, $::TIME - $::starttime). "%\n");
	    $ctl->write("monrate:   ". sprintf("%.2f tests per second\n", $Service::n_tested
				      / ($::TIME - $::starttime)));
	    $ctl->write("looprate:  ". sprintf("%.2f loops per second\n", $::loopcount
					       / ($::TIME - $::starttime))) if $param->{more};
	}
    }
    # ...

    $ctl->final();
}

sub perl_version {

    # before 5.6
    return $] unless $^V;

    my $v = $^V;

    # 5.6 - 5.8
    if( length($v) == 3 ){
        return join('.', unpack('c*', $v));
    }

    # 5.10 -
    $v =~ s/^v//;
    return $v;
}

sub cmd_byebye {
    my $ctl = shift;

    $ctl->ok_n();
    $ctl->writable();	# attempt to flush before disconnecting
    $ctl->done();
}

sub cmd_help {
    my $ctl = shift;

    $ctl->ok();
    foreach my $cmd (sort keys %cmd_docs){
	my $descr = $cmd_docs{$cmd}{descr} || 'undocumented';
	$ctl->write("$cmd\t$descr\n");
    }
    $ctl->final();
}

sub cmd_console {
    my $ctl = shift;
    my $param = shift;

    $ctl->ok_n();
    push @consoles, $ctl
	unless( $ctl->{type} =~ /console/ );
    $ctl->{type} = "Cconsole";
}

sub cmd_hup {
    my $ctl = shift;

    $ctl->ok_n();
    $ctl->writable();	# attempt to flush before dying
    ::loggit( 'restart requested - HUPing', 1 );
    kill 'HUP', $$;
}

sub cmd_shutdown {
    my $ctl = shift;
    my $param = shift;

    $ctl->ok_n();
    $ctl->writable();	# attempt to flush before dying
    ::loggit( "shutting down - $param->{reason}", 1 )
	if $param->{reason};

    if( $$ == $::mainpid ){
	# keep things happy
	::loggit( 'shutdown requested - exiting', 1 );
	$::exitinprogress = 1;
	exit(0);
    }
    kill 'TERM', $::mainpid;
}

################################################################

command_install( 'echo',     \&cmd_echo,     "returns its input", "*" );
command_install( 'status',   \&cmd_status,   "returns server status" );
command_install( 'bye',      \&cmd_byebye,   "disconnect" );
command_install( 'help',     \&cmd_help,     "no help at all" );
command_install( 'console',  \&cmd_console,  "turn on console mode--session will get copies of log msgs" );
command_install( 'hup',      \&cmd_hup,      "restart the server" );
command_install( 'shutdown', \&cmd_shutdown, "shutdown the server" );

1;


