# -*- perl -*-

# Copyright (c) 2010 by Jeff Weisberg
# Author: Jeff Weisberg <jaw+argus @ tcp4me.com>
# Created: 2010-Jan-09 11:08 (EST)
# Function: scheduling
#
# $Id: Argus::Schedule.pm,v 1.3 2012/10/13 18:36:12 jaw Exp $

package Argus::Schedule;
@ISA = qw(Configable);
use vars qw(@ISA);
use strict;

my %DAYNO = (
    sun => 0, mon => 1, tue => 2, wed => 3,
    thu => 4, fri => 5, sat => 6,
   );

# The stars are not wanted now; put out every one:
# Pack up the moon and dismantle the sun;
# Pour away the ocean and sweep up the woods:
# For nothing now can ever come to any good.
#   -- W.H. Auden
sub permit_now {
    my $me = shift;
    
    my $res = $me->result_now();
    $res = 'yes' unless defined $res;	#default permit
    
    return ::ckbool($res);
}

sub result_now {
    my $me = shift;

    my @t    = localtime($^T);
    my $day  = $t[6];
    my $time = sprintf '%d%02d', $t[2], $t[1];

    # first match wins
    for my $s (@{$me->{schedule}}){
        # My fellow-scholars, and to keep those statutes
        # That are recorded in this schedule here:
        #   -- Shakespeare, Loves Labor Lost
        next unless $s->{dayno} eq 'all' || $s->{dayno} == $day;
        next if $time < $s->{start};
        next if $time > $s->{end};
        return $s->{res};
    }

    return ;
}


sub readconfig {
    my $class = shift;
    my $cf    = shift;
    my $mom   = shift;

    my $line = $cf->nextline();
    my($type, $name) = $line =~ /^\s*([^:\s]+):?\s+([^\{\s]+)/;

    my $me = $class->new();
    $me->cfinit($cf, $name, "\u\L$type");

    unless( $name ){
        $cf->nonfatal( "invalid entry in config file: '$_'" );
	$cf->eat_block() if $line =~ /\{\s*$/;
	return ;
    }

    # What's here? the portrait of a blinking idiot,
    # Presenting me a schedule! I will read it.
    #   -- Shakespeare, Merchant of Venice
    my @sched;
    while( defined($_ = $cf->nextline()) ){
        if( /^\s*\}/ ){
            last;
        }

        # parse: day, start, end, result
        eval {
            push @sched, _parse($cf, $_);
        };
        if(my $e = $@){
            chomp $e;
            $cf->nonfatal("invalid schedule: $e");
            $cf->eat_block();
            return;
        }
    }

    $me->{schedule} = \@sched;
    $me->config($cf, $mom);
    return $me;
}

sub unserialize {
    my $class = shift;
    my $cf    = shift;
    my $mom   = shift;
    my $name  = shift;
    my $line  = shift;

    my $me = $class->new();
    $me->cfinit($cf, $name, 'Schedule');

    my @sched;
    for my $l (split /\n/, $line){
        eval {
            push @sched, _parse($cf, $l);
        };
    }

    $me->{schedule} = \@sched;
    $me->config($cf, $mom);
    return $me;
}

sub _parse {
    my $cf = shift;
    my $l  = shift;

    my($day, $times, $res) = $l =~ /^\s*(\S+)\s+(.*)\s+=>\s*(\S+)/;
    $times =~ s/://g;
    my($start, $end) = $times =~ /(\d+)\s*-\s*(\d+)/;
    $start ||= '0000';
    $end   ||= '2400';
    $day = 'all' if $day eq '*';
    $day = lc $day;

    die "invalid day spec '$day'\n" unless grep {$day eq $_} qw(all mon tue wed thu fri sat sun);
    die "invalid start time '$start'n" unless $start =~ /^[0-9]{3,4}/;
    die "invalid end time '$end'n" unless $end =~ /^[0-9]{3,4}/;

    my $dayno = exists($DAYNO{$day}) ? $DAYNO{$day} : $day;

    return { day => $day, dayno => $dayno, start => $start, end => $end, res => $res };
}

sub config {
    my $me  = shift;
    my $cf  = shift;
    my $mom = shift;

    my $name = $me->{name};

    if( $mom->{config}{"schedule $name"} ){
        $cf->warning( "redefinition of schedule '$name'", $mom->{_config_location}{"schedule $name"} )
    }
    if( $mom->{config}{$name} ){
        $cf->warning( "redefinition of '$name'", $mom->{_config_location}{$name} )
    }

    $mom->{config}{"schedule $name"} = $me;
    $me;
}

sub _gen_spec {
    my $s = shift;

    "$s->{day} $s->{start} - $s->{end} => $s->{res}";
}

sub gen_conf {
    my $me = shift;

    my $r = "Schedule $me->{name} {\n";
    for my $s ( @{$me->{schedule}} ){
        $r .= "\t" . _gen_spec($s) . "\n";
    }
    $r .= "}\n";
    return $r;
}

sub get_config_data {
    my $me = shift;

    my $r;
    for my $s ( @{$me->{schedule}} ){
        $r .= _gen_spec($s) . "\n";
    }
    return $r;
}


1;
