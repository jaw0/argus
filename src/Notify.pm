# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Apr-12 20:06 (EDT)
# Function: Tell someone what happened
#
# $Id: Notify.pm,v 1.81 2012/10/12 02:17:32 jaw Exp $

package Notify;
use NotMe;
use Argus::Encode;
use POSIX ('_exit', 'strftime', 'tzset');

use strict;

my $lastupd;		# time of last notification or ack
my %byid     = ();
my %lastsent = ();	# by dest
my %queue    = ();	# by dest => {not, tag}
my %unacked  = ();	# by id
my %dstparam = ();	# probably a bad idea...
# RSN - persist dstparams in file

# only send so often, otherwise queue
# can be overridden in user-defined notification methods via 'qtime: 1234'
my $QUEUETIME = 120;

# if older than this, and no longer active, throw them away
my $OLD_AGE = 3600 * 24 * 10;

# delay escalation, if no longer down for this long
my $DELAY_ESCALATE = 600;

# fields which get saved in save file (and then re-loaded)
my @SAVE_FIELDS = qw(created msg sentcnt state objstate objovstate
		     priority autoack ackonup period ackedby ackedat
		     escalated lastsent audit detail severity reason
		     ackonbetter ackonworse msg_abbr);

sub new {
    my $obj   = shift;
    my %param = @_;
    my( $me, $msg, $fmt, $aa, $dst, @t );

    # do not notify if notifies are not wanted
    return unless value_at_severity('sendnotify', $obj);

    if( $obj->{status} eq 'down' ){
	$msg = $obj->{notify}{messagedn};
	$fmt = $obj->{notify}{message_fmtdn};
	$aa  = value_at_severity('autoack', $obj);
    }else{
	$msg = $obj->{notify}{messageup};
	$fmt = $obj->{notify}{message_fmtup};
	$aa  = 1;	# up messages never need to be acked
    }

    $fmt ||= $obj->{notify}{message_fmt};

    if( $param{audit} ){
	# notify is an audit channel
	$msg = 'audit: %A';
	$aa = 1;
    }

    # do not notify if user specified an empty msg
    return unless $msg;

    $me = {
	obj         => $obj,
	created     => $^T,
	idno        => newid(),
	sentcnt     => 0,
	escalated   => 0,
	state       => 'active',		# active, supressed, acked
	objstate    => $obj->{status},
	objovstate  => $obj->{ovstatus},
	priority    => value_at_severity('priority', $obj),
	autoack     => $aa,
	period      => value_at_severity('renotify', $obj),
	ackonup     => value_at_severity('ackonup',  $obj),
	ackonbetter => value_at_severity('ack_on_better', $obj),
	ackonworse  => value_at_severity('ack_on_worse',  $obj),
	status      => {},
	sendto      => [],
	log         => [],
	audit       => $param{audit},	# bool
	detail      => $param{detail},
	severity    => $obj->{currseverity},
	reason      => $obj->{srvc}{reason},
	truncval    => $obj->{notify}{truncval},
    };
    bless $me; # gesundheit

    $me->{msg} = $me->expand($fmt, $msg, $obj);
    $me->{msg_abbr} = $me->expand('%m', $msg, $obj);	# for web page list

    if( $me->can('notify_policy') ){
	return unless $me->notify_policy();
    }

    return unless $me->init($obj);

    $me->loggit( 'system', 'created' );
    $me->notify();
}

# return notify::field.severity // notify::field
sub value_at_severity {
    my $fld = shift;
    my $obj = shift;
    my $sev = shift;

    $sev ||= $obj->{currseverity};

    my $v = $obj->current_value('notify', "$fld.$sev");
    return $v if defined $v;
    return $obj->current_value('notify',$fld);
}

sub init {
    my $me  = shift;
    my $obj = shift;
    my( $notify );

    # use notifyup, notifydn, (...), or notify?
    if( $me->{audit} ){
	$notify = $obj->{notify}{notifyaudit};
    }else{
	# notify.severity // notify(up|dn) // notify
	if( $me->{objstate} eq 'down' ){
	    $notify = value_at_severity('notify', $obj, $me->{severity});
	    $notify = $obj->current_value('notify', 'notifydn') unless defined $notify;
	}else{
	    $notify = $obj->current_value('notify', 'notify.clear');
	    $notify = $obj->current_value('notify', 'notifyup') unless defined $notify;
	}

	$notify = $obj->current_value('notify', 'notify') unless defined $notify;
	$notify .= ' ' . $obj->{notify}{notifyalso} if $obj->{notify}{notifyalso};
    }

    {
	my $n;
	foreach my $dst ( split /\s+/, $notify ){
	    # QQQ - is this really a good idea?
	    $dst = $dstparam{$dst}{redirect} if $dstparam{$dst} && $dstparam{$dst}{redirect};
	    $n .=  ($n ? ' ' : '') . $dst;
	}
	$notify = $n;
    }

    # set status of each rcpt
    $me->{sendto} = [ { n => 0, start => 0, who => [] } ];
    foreach my $dst ( split /\s+/, $notify ){
	next if $dst eq 'none';
	next unless $dst;
        next unless $me->{state} eq 'active';
	$me->{status}{$dst} ||= 'created';
	push @{$me->{sendto}[0]{who}}, $dst;
    }

    # He that sendeth a message by the hand of a fool cutteth off the feet, and drinketh damage.
    #   -- proverbs 26:6
    # no recipients? abort
    unless( @{$me->{sendto}[0]{who}} ){
	# QQQ this is too noisy, maybe re-enable later
	# $me->loggit( 'system', 'no recipient' );
    	return undef;
    }

    # pre-build escalation table
    # A wicked messenger falleth into mischief: but a faithful ambassador is health.
    #   -- proverbs 13:17
    unless( $me->{autoack} ){
	my $n = 1;
	my $esc = value_at_severity('escalate', $obj, $me->{severity});
	if( $esc ){
	    foreach my $esc ( split /\;\s+/, $esc ){
		# each is of form N dest dest dest ...
		# previously, N was number of pages to escalate
		# then, it was elapsed-time in minutes
		# currently, a timespec, defaulting to minutes if no units are specified.
		# QQQ - is there a preference?
		my @a = split /\s+/, $esc;
		next unless @a;
		my $nt = shift @a;
		eval { $nt = ::timespec($nt, 60); };
		if($@){
		    ::loggit( "invalid timespec ($nt) for escalation.", 1 );
		}
		next unless $nt;

		$me->{sendto}[$n] = { n => $n, start => $nt, who => [@a] };
		$n ++;
	    }
	}
    }

    push @{$obj->{notify}{list}}, $me
	unless $me->{audit};		# do not list audit msgs in object notify list

    $byid{$me->{idno}} = $me;
    $lastupd = $^T;

    if( $me->{state} eq 'active' ){
	$unacked{$me->{idno}} = $me;
    }

    # for easy access
    $me->{acl_ntfyack}    = $obj->{acl_ntfyack};
    $me->{acl_ntfydetail} = $obj->{acl_ntfydetail};
    $me->{timezone}       = $obj->{notify}{timezone};
    $me->{mailfrom}       = $obj->{notify}{mail_from};
    $me->{unack_to}       = $obj->{notify}{unack_timeout};

    1;
}

# flush out queued pending messages
END {
    flushqueue();
    foreach my $p (values %byid){
	$p->save();
    }
}

# return a unique id number
sub newid {
    my( $id, $n );

    if( ::topconf('_test_mode') ){
	$id = 1;
	while( exists $byid{$id} ){ $id ++ };
    }else{
	if( open(F, "+< $::datadir/notno") ){
	    chop( $id = <F> );
	    $id ++;
	    while( exists $byid{$id} ){ $id = int(rand( 65535 << (++$n/1000) )); }

	    seek F, 0, 0;
	    print F "$id\n";
	    close F;
	}else{
	    ::loggit( "cannot open $::datadir/notno: $!", 1 );
	    $id = $$;
	    while( exists $byid{$id} ){ $id = int(rand( 65535 << (++$n/1000) )); }
	}
    }

    $id;
}

sub save {
    my $me = shift;
    my $f = "$::datadir/notify/$me->{idno}";

    return if ::topconf('_test_mode');
    open( N, "> $f" ) || return $me->loggit( 'system', "cannot open save file: $!", 1 );

    print N "idno: $me->{idno}\n";
    print N "object: ", encode( $me->{obj}->unique() ), "\n";
    foreach my $k (@SAVE_FIELDS){
	my $v = $me->{$k};
	next unless defined $v;

	$v = encode( $v );
	print N "$k: $v\n";
    }

    foreach my $dst (keys %{$me->{status}}){
	print N "status: ", encode($dst), " ", encode($me->{status}{$dst}), "\n";
    }

    foreach my $s (@{$me->{sendto}}){
	print N "sendto: $s->{start}";
	foreach my $dst (@{$s->{who}}){
	    print N " ", encode($dst);
	}
	print N "\n";
    }

    foreach my $l (@{$me->{log}}){
	print N "log: $l->{time} ", (encode($l->{who}) || '_') , " ", encode($l->{msg}), "\n";
    }

    close N;
}

sub load {
    my $obj = shift;
    my $id  = shift;
    my $f = "$::datadir/notify/$id";
    my $me = { obj => $obj };

    open( N, $f ) || return ::loggit( "cannot open save file '$f': $!", 1 );
    while( <N> ){
	chop;

	next if( /^sendto/ );
	if( /^status:\s+([^\s]+) ([^\s]+)/ ){
	    my($dst, $st) = ($1, $2);
	    $me->{status}{ decode($dst) } = decode($st);
	}
	elsif( /^log:\s+([^\s]+) ([^\s]+) ([^\s]+)/ ){
	    my($t, $w, $m) = ($1, $2, $3);
	    push @{$me->{log}}, { time => $t,
				  who  => (($w eq '_') ? '' : decode($w)),
				  msg  => decode($m)
				  };
	}
	else{
	    my( $k, $v ) = split /:\s*/, $_, 2;
	    $me->{$k} = decode($v);
	}
    }
    close N;

    # too old and not still active? toss
    if( $me->{state} ne 'active' && $^T - $me->{created} > $OLD_AGE ){
	unlink $f;
	return;
    }

    bless $me;
    $me->init($obj);
}

################################################################

sub notify {
    my $me  = shift;
    my( $l );

    foreach my $dst ( @{$me->{sendto}[0]{who}} ){
	$me->sendorqueue($dst);
    }

    $me->{sentcnt} ++;
    $me->{lastsent} = $^T;
    $me->ack() if $me->{autoack};
}

# I say again! repeated the Pigeon
#   -- Alice in Wonderland
sub renotify {
    my $me = shift;
    my( $l );

    # auto-ack if aa and it has already been sent
    return $me->ack() if $me->{autoack};

    for ($l=0; $l<=$me->{escalated}; $l++){
	if( $^T - $me->{created} - $me->{sendto}[$l]{start} < $me->{period} ){
	    # too early to resend the escalation
	    last;
	}

        foreach my $dst ( @{$me->{sendto}[$l]{who}} ){
            $me->sendorqueue($dst, 'RESENT');
        }
    }

    $me->{sentcnt} ++;
    $me->{lastsent} = $^T;
}

sub escalate {
    my $me = shift;
    my( $n );

    # auto-ack if aa and it has already been sent
    return $me->ack() if $me->{autoack};

    # postpone if no longer down for X minutes
    if( $me->{obj}->{status} ne 'down'
	&& $^T - $me->{obj}->{transtime} > $DELAY_ESCALATE ){
	$me->loggit('system', 'delaying escalation');
	return;
    }

    $me->{escalated} ++;
    return if $me->{escalated} >= @{$me->{sendto}};

    foreach my $dst ( @{$me->{sendto}[$me->{escalated}]{who}} ){
	$me->sendorqueue($dst );  # 'ESCALATED' will be tagged automatically
    }
}

sub sendorqueue {
    my $me  = shift;
    my $dst = shift;
    my $tag = shift;
    my( $qt );

    $qt = NotMe::qtime($dst);
    $qt = ::topconf('qtime') unless defined $qt;
    $qt = $QUEUETIME unless defined $qt;

    if( $lastsent{$dst} && ($lastsent{$dst} + $qt > $^T) ){
	$me->queue($dst, $tag);
    }else{
	$me->transmit($dst, $tag);
    }
}

sub queue {
    my $me  = shift;
    my $dst = shift;
    my $tag = shift;

    push @{$queue{$dst}}, {not => $me, tag => $tag};

    $me->{status}{$dst} = 'queued';
    $me->loggit( $dst, 'queued' );
    $me->save();
}

# And Hezekiah received the letter from the hand of the messengers, and read it
#   -- isaiah 37:14
sub ack {
    my $me = shift;
    my $who = shift;
    my( $dst, $aap );

    return undef if $me->{state} ne 'active';
    unless($who){
	$who = 'auto-ack';
	$aap = 1;
	# we do it this way, and not by looking at me->autoack
	# as in some cases autoack = 1, but the ack is from an
	# override or timeout in which case we want to de-queue
    }

    $me->{state}   = 'acked';
    $me->{ackedat} = $^T;
    $me->{ackedby} = $who;
    $me->loggit( $who, 'acked' );

    # remove from queue unless it is an auto-ack
    unless( $aap ){
	foreach $dst (keys %queue){
	    @{$queue{$dst}} = grep { $_->{not}{idno} != $me->{idno} } @{$queue{$dst}};
	    delete $queue{$dst} unless @{$queue{$dst}};
	}
	foreach $dst (keys %{$me->{status}}){
	    $me->{status}{$dst} = "acked by $who";
	}
    }

    # remove from unacked
    delete $unacked{ $me->{idno} };
    $lastupd = $^T;

    # stats, ...


    $me->save();

    1;
}



sub supress {
    my $me = shift;

    # RSN - supress...
}

sub loggit {
    my $me = shift;
    my $who = shift;
    my $msg = shift;
    my $loudly = shift;

    push @{$me->{log}}, { time => $^T, who => $who, msg => $msg };
    $msg  = "<$me->{priority}> $msg" if $me->{priority};
    $msg .= " - $who" if $who;
    $me->{obj}->loggit( msg => $msg,
			tag => "NOTIFY-$me->{idno}",
			lpf => $loudly );
}

sub flushqueue {

    foreach my $dst (keys %queue){
	my @p = map { $_->{not} } @{$queue{$dst}};
	my $p = shift @p;
	next unless $p;
	$p->transmit($dst, undef, @p);
	delete $queue{$dst};
    }
}

# This side is Hiems, Winter, this Ver, the Spring;
# the one maintained by the owl, the other by the
# cuckoo. Ver, begin.
#   -- Shakespeare, Loves Labours Lost

# run by cron every minute
sub maintenance {

    # what should I do with outstanding notifs?
    foreach my $p (values %unacked){

	# auto-ack if in override
	if( $p->{obj}->{ovstatus} eq 'override' ){
	    $p->ack('override');
	    next;
	}
	# auto-ack if no longer down and TO
	if( $p->{obj}->{status} ne 'down' && $p->{unack_to} && $^T - $p->{obj}->{transtime} > $p->{unack_to} ){
	    $p->ack('timeout');
	    next;
	}
	# auto-ack if not down and ackonup is set
	if( $p->{objstate} eq 'down' && $p->{obj}->{status} ne 'down' && $p->{ackonup} ){
	    $p->ack('ackonup');
	}
	# auto-ack on severity changes
	if( $p->{severity} ne $p->{obj}->{currseverity} ){
	    my $old = $MonEl::severity_sort{ $p->{severity} };
	    my $new = $MonEl::severity_sort{ $p->{obj}->{currseverity} };

	    if( $old > $new && $p->{ackonbetter} ){
		$p->ack('ack_on_better');
	    }
	    if( $old < $new && $p->{ackonworse} ){
		# hopefully, the user has configured a new notification at this severity
		$p->ack('ack_on_worse');
	    }
	}
	if( $p->{period} && ($p->{lastsent} + $p->{period} <= $^T) ){
	    # time to resend
	    $p->renotify();
	}

	if( defined($p->{sendto}[ $p->{escalated}+1 ]) &&
	    $^T - $p->{created} >= $p->{sendto}[ $p->{escalated}+1 ]{start} ){
	    # time to escalate
	    $p->escalate();
	}
    }

    # run queue
    foreach my $dst (keys %queue){
	# print STDERR "sendq? $dst\n";
	# time to send?
	my $qt = NotMe::qtime($dst);
	$qt = ::topconf('qtime') unless defined $qt;
	$qt = $QUEUETIME unless defined $qt;

	if( $lastsent{$dst} + $qt <= $^T ){
	    # print STDERR "sending q $dst\n";
	    my $p = shift @{$queue{$dst}};
	    my @p = map { $_->{not} } @{$queue{$dst}};
	    # send all queued
	    $p->{not}->transmit($dst, $p->{tag}, @p) if $p;
	    delete $queue{$dst};
	}
    }

}

# And may she speed your footsteps in all good,
# Again began the courteous janitor;
# Come forward then unto these stairs of ours.
#   -- Dante, Divine Comedy

# perform occasional cleanup, etc
sub janitor {

    my( %n_byid, %n_unacked );

    foreach my $n (values %byid){
	# if no longer active, and old, => toss
	if( $n->{state} ne 'active' && $^T - $n->{created} > $OLD_AGE ){
	    my $f = "$::datadir/notify/$n->{idno}";
	    unlink $f;
	    $n->{obj}{notify}{list} = [ grep { $_ != $n }
					@{$n->{obj}{notify}{list}} ];
	    $n->{log} = $n->{sendto} = $n->{status} = $n->{obj} = undef
	}else{
	    $n_byid{ $n->{idno} } = $n;
	}
    }
    %byid = (); %byid = %n_byid;

    foreach my $n (values %unacked){
	$n_unacked{ $n->{idno} } = $n;
    }
    %unacked = (); %unacked = %n_unacked;

    # delete old orphaned files
    my $dir = "$::datadir/notify";
    opendir(ND, $dir);
    foreach my $f (readdir(ND)){
	next if $f =~ /^\./;
	next if $byid{$f};
	next if $^T - (stat("$dir/$f"))[9] < $OLD_AGE;
	unlink "$dir/$f";
    }
    closedir ND;

}

# On this Iris, fleet as the wind, sped forth to deliver her message.
#   -- Homer, The Iliad
sub transmit {
    my $me  = shift;
    my $dst = shift;
    my $tag = shift;
    my @more = @_;
    my( $msg, $extra );

    # is dst disabled?
    if( $dstparam{$dst} && $dstparam{$dst}{disabled} ){
	# $me->loggit( $dst, 'not sent' );
	$me->{status}{$dst} = 'disabled';

	return;
    }

    # is dst off schedule
    unless( NotMe::permit_now($dst, $me->{severity}) ){
        $me->{status}{$dst} = 'off-schedule';
        return;
    }

    # if many, summarize
    if( @more ){

	my $nolots = NotMe::nolots( $dst );
	$nolots ||= ::topconf('nolotsmsgs');

	if( $nolots ){
	    # list all messages, don't summarize into Lots UP/DOWN

	    my $j;
	    if( grep { /\n/s } $msg, @more ){
		$j = "\n\n";
	    }else{
		$j = "\n";
	    }

	    $msg = join($j, map { $_->{msg} } $msg, @more);
	}else{
	    my $d;
	    foreach my $p (@more){
		$d = 1 if $p->{objstate} eq 'down';
	    }
	    if( $d ){
		$msg = ::topconf('message_lotsdn') || 'Lots of stuff just went DOWN!';
	    }else{
		$msg = ::topconf('message_lotsup') || 'Lots of stuff just came UP!';
	    }
	}
    }else{
	$msg = $me->{msg};
    }

    $extra .= " $tag" if $tag;
    $extra .= " ESCALATED" if $me->{escalated};	# RSN - from $who...

    my $err = ::topconf('_dont_ntfy') ? 0 :
      NotMe::transmit($me, $dst, $msg, $extra, @more);

    if( $err ){
	foreach my $p ( $me, @more ){
	    $p->loggit( $dst, 'transmit-failed' );
	}
	return;
    }

    $lastsent{$dst} = $^T;
    foreach my $p ( $me, @more ){
	$p->loggit( $dst, 'transmit' );
	$p->{status}{$dst} = 'sent';
	if( $p->{autoack} ){
	    $p->ack();
	}else{
	    $p->save();
	}
    }
}

sub expand {
    my $me  = shift;
    my $fmt = shift;
    my $msg = shift;
    my $obj = shift;

    # interpolate message 1st, it may contain additional % sequences...
    $fmt =~ s/%m/$msg/g;

    # pretify value
    my $v = $obj->{srvc} ? $obj->{srvc}{result} : undef;
    if( length($v) > 40 && $me->{truncval} eq 'yes' ){
	$v = substr($v,0,40);
	$v .= ' [...]';
    }
    $v =~ s/\r/\\r/gs;
    $v =~ s/\n/\\n/gs;

    my $res = $obj->expand($fmt,
	localtime	=> 1,
	dtformat	=> "%d/%b %R",	# dd/Mon hh:mm
	time		=> $me->{created},
	data		=> {
	    i	=> $me->{idno},
	    o 	=> $obj->{uname},
	    p	=> $me->{priority},
	    s	=> uc($me->{objstate}),
	    v   => $v,
	    y	=> $me->{severity},
	},
    );

    $res;
}

################################################################

sub number_of_notifies { scalar keys %byid }
sub byid { my $id = shift; $byid{$id} }
sub unacked { \%unacked }
sub num_unacked { scalar keys %unacked }
sub lastupd { $lastupd }

################################################################

sub cmd_list_line {
    my $me = shift;
    my $ctl = shift;

    $ctl->write("$me->{idno} $me->{state} $me->{objstate} $me->{created} " .
		encode($me->{obj}->filename()) . " " .
		encode($me->{msg_abbr} || $me->{msg} || '_') . ' ' .
		encode($me->{priority} || '_') . ' '. encode($me->{severity} || '_') .
		"\n");
}

sub cmd_list {
    my $ctl = shift;
    my $param = shift;

    $ctl->ok();

    if( $param->{which} eq 'unacked' ){
	# oldest first
	foreach my $p (sort {$a->{created} <=> $b->{created}} values %unacked){
	    $p->cmd_list_line($ctl);
	}
    }
    elsif( $param->{which} eq 'queued' ){
	foreach my $dst (sort keys %queue){
	    # print STDERR "list q $dst\n";
	    foreach my $p (@{$queue{$dst}}){
		$p->{not}->cmd_list_line($ctl);
	    }
	}
    }
    else{
	# newest first
	foreach my $p (sort {$b->{created} <=> $a->{created}} values %byid){
	    $p->cmd_list_line($ctl)
		unless $p->{audit} && !$param->{showaudit};
	}
    }
    $ctl->final();
}

sub cmd_detail {
    my $ctl = shift;
    my $param = shift;

    my $idno = $param->{idno};
    unless( exists $byid{$idno} ){
	$ctl->bummer(404, 'Notification Not Found');
	return;
    }

    my $p = $byid{$idno};
    my $o = $p->{obj};

    $ctl->ok();
    foreach my $k (sort keys %$p){
	my $v = $p->{$k};
	if( ref($v) ){
	    $v = "#<REF>";
	}else{
	    $v = encode( $v );
	}
	$ctl->write( "$k:\t$v\n" );
    }
    $ctl->write( "object: " . encode( $p->{obj}->unique() ) . "\n" );

    for my $e (qw(style_sheet javascript bkgimage icon icon_up icon_down)){
	my $v = $o->{web}{$e};
	next unless $v;
	$ctl->write("web $e: " . encode($v) . "\n");
    }

    $ctl->write( "web branding: " .   encode($o->{web}{header_branding}) . "\n");
    $ctl->write( "web header: ".      encode("$o->{web}{header_all} $o->{web}{header}") . "\n");
    $ctl->write( "web footer: ".      encode("<div class=footer>$o->{web}{footer} $o->{web}{footer_all}</div>" .
                                           "<div class=footerargus>$o->{web}{footer_argus}</div>") . "\n");

    my $ww;
    foreach my $w (sort keys %{$p->{status}}){
	my $we = encode($w);
	$ww .= " $we";
	$ctl->write("status $we: " . $p->{status}{$w} . "\n" );
    }
    $ctl->write("statuswho: $ww\n");

    my $n = 0;
    foreach my $l (@{$p->{log}}){
	$ctl->write( "log $n: $l->{time} " . ($l->{who}? encode($l->{who}) : '_') .
		     ' ' . encode($l->{msg}) . "\n" );
	$n++;
    }
    $ctl->write( "loglines: $n\n");
    $ctl->final();
}

sub cmd_ack {
    my $ctl = shift;
    my $param = shift;
    my( $p, $u );

    $p = $param->{idno};
    $u = $param->{user} || 'anonymous';

    if( defined &notify_ack_policy ){
	unless( notify_ack_policy($param) ){
	    $ctl->bummer(401, 'Not Permitted');
	}
    }

    if( $p eq 'all' ){
	$ctl->ok_n();
	foreach $p (values %unacked){
	    $p->ack( $u );
	}
    }
    elsif( exists $byid{$p} ){
	$ctl->ok_n();
	$byid{$p}->ack( $u );
    }else{
	$ctl->bummer(404, 'Notification Not Found');
    }
}

sub cmd_set_dst {
    my $ctl = shift;
    my $param = shift;

    my $dst = $param->{dst};
    my $p   = $param->{param};
    my $v   = $param->{value};

    if( defined($dst) && defined($p) ){
	if( $p eq 'disable' || $p eq 'redirect' ){
	    if( $v ){
		$dstparam{$dst}{$p} = $v;
	    }else{
		delete $dstparam{$dst}{$p};
	    }
	    $ctl->ok_n();
	}else{
	    $ctl->bummer(404, 'Unknown param' );
	}
    }else{
	$ctl->bummer(500, 'Missing Param');
    }
}

sub cmd_get_dst {
    my $ctl = shift;
    my $param = shift;

    my $dst = $param->{dst};
    my $p   = $param->{param};

    if( defined($dst) && defined($p) ){
	my $v;
	if( exists $dstparam{$dst} && exists $dstparam{$dst}{$p} ){
	    $v = $dstparam{$dst}{$p};
	}
	$ctl->ok();
	$ctl->write( "value: " . encode($v) . "\n\n" );
    }else{
	$ctl->bummer(500, 'Missing Param');
    }
}

################################################################

Control::command_install( 'notify_list',   \&cmd_list,
			  'list notifications', 'which' );
Control::command_install( 'notify_detail', \&cmd_detail,
			  'tell about notification', 'idno' );
Control::command_install( 'notify_ack',    \&cmd_ack,
			  'ack a notification', 'idno user' );
Control::command_install( 'notify_setparam', \&cmd_set_dst,
			  'modify per dst params', 'dst param value' );
Control::command_install( 'notify_getparam', \&cmd_get_dst,
			  'get per dst param', 'dst param' );

Cron->new( freq => 60,
	   text => 'Notification maintenance',
	   func => \&maintenance );

Cron->new( freq => 6*3600,
	   text => 'Notification cleanup',
	   func => \&janitor );

1;
