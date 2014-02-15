# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Apr-02 12:30 (EST)
# Function: crontab class
#
# $Id: Cron.pm,v 1.18 2012/09/23 15:44:53 jaw Exp $

package Cron;
@ISA = qw(BaseIO);

use strict qw(refs vars);
use vars qw($doc @ISA);

# Time travels in divers paces with divers persons.
# I 'll tell you who Time ambles withal, who Time trots withal,
# who Time gallops withal, and who he stands still withal.
#        -- Shakespeare, As You Like It

$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [@ISA],
    methods => {
    },
    fields  => {
	cron::time => {
	    descr => 'time at which the job should run',
	    attrs => ['internal'],
	},
	cron::freq => {
	    descr => 'how often should the cronjob run',
	    attrs => ['internal'],
	},
	cron::spec => {
	    descr => 'unix crontab format specification',
	    attrs => ['internal'],
	},
	cron::func => {
	    descr => 'ref to func to run',
	    attrs => ['internal'],
	},
	cron::args => {
	    descr => 'arg to pass to func',
	    attrs => ['internal'],
	},
	cron::text => {
	    descr => 'description of job, used for debugging',
	    attrs => ['internal'],
	},
	cron::queue => {
	    descr => 'which queue should job be placed on',
	    attrs => ['internal'],
	    vals  => ['general', 'service'],
	},
      },
};


sub new {
    my $class = shift;
    my %param = @_;
    my( $me, $k );

    $me = {};
    bless $me, $class;

    foreach $k (qw(time freq func args text queue)){
	$me->{cron}{$k} = $param{$k};
    }

    if( $param{spec} ){
	$me->parse_spec( $param{spec} );
	$me->{cron}{time} = $me->next_spec_time();
    }

    if( !$me->{cron}{time} && !$me->{cron}{freq}  ){
	::warning( "Invalid crontab spec - IGNORING - $param{text}" );
	return;
    }

    $me->{cron}{queue} ||= 'general';

    if( $me->{cron}{freq} || $me->{cron}{spec} ){
	$me->{type} = 'Cronjob';
    }else{
	$me->{type} = 'Atjob';
    }

    # randomly perturb start time if not specified
    # prevents everything running all at once at eg. *:00
    $me->{cron}{time} ||=
	$^T + (($me->{cron}{freq} < 3600) ?
	       $me->{cron}{freq} + int(rand($me->{cron}{freq}/2)) :
	       $me->{cron}{freq}/2 + int(rand($me->{cron}{freq}/2)));

    $me->add_timed_func( time => $me->{cron}{time},
			 func => \&cronjob,
			 text => "cron" );
    $me;
}

# parse crontab(5) style spec
#   min hr dom mon dow
sub parse_spec {
    my $me = shift;
    my $spec = shift;

    my @s = split /\s+/, $spec;

    $me->{cron}{spec}{min} = spec_s2a( $s[0] ) || [ (1) x 60 ];
    $me->{cron}{spec}{hrs} = spec_s2a( $s[1] ) || [ (1) x 24 ];
    $me->{cron}{spec}{dom} = spec_s2a( $s[2] );
    $me->{cron}{spec}{mon} = spec_s2a( $s[3] ) || [ (1) x 13 ];
    $me->{cron}{spec}{dow} = spec_s2a( $s[4] );

    $me->{cron}{spec}{spec} = $spec;

}

# a,b,c-d/e
sub spec_s2a {
    my $s = shift;
    my @a;

    return undef unless defined $s;
    return undef if $s eq '*';

    $s =~ s/\*/0-100/;
    my @p = split /,/, $s;
    foreach my $pp (@p){ # a or a-b or a-b/c
	my($range, undef, $step) = $pp =~ m,([^/]+)(/(.+))?,;
	$step ||= 1;
	my($start, $stop) = $range =~ /([^-]+)-([^-]+)/;
	$start = $range unless defined $start;
	$stop  = $start unless defined $stop;

	# print STDERR "p: $start, $stop, $step\n";
	for(my $i=$start; $i<=$stop; $i+=$step){
	    $a[$i] = 1;
	}
    }
    # print STDERR "parse $s => @a\n";
    [ @a ];
}

# return next time from crontab(5) spec
# only checks hrs and mins
sub next_spec_time {
    my $me = shift;
    my( $t0, $cm, $ch, @lt );

    $t0 = $^T + 60;
    @lt = localtime($t0);	# start search 1 min from now
    (undef, $cm, $ch) = @lt;

    # next time is either: this hour, min > now.min
    #                  or: hr later than now.hr, min = earliest

    # try 1st case
    if( $me->{cron}{spec}{hrs}[ $ch ] ){
	# look for next matching min

	while( !$me->{cron}{spec}{min}[ $cm ] && $cm < 60 ){
	    $cm++;
	}

	if( $me->{cron}{spec}{min}[ $cm ] && $cm < 60 ){
	    # found
	    #print STDERR "fnt1: $cm, $ch\n";
	    return $t0 + ( $cm - $lt[1] ) * 60;
	}
    }

    # 2nd case, 1st find hr
    $ch ++;
    my $tom = 0;
    while( !$me->{cron}{spec}{hrs}[ $ch ] && $ch < 24 ){
	$ch ++;
    }
    #print STDERR "fnt2a: $cm, $ch\n";

    if( !$me->{cron}{spec}{hrs}[ $ch ] || $ch >= 24 ){
	$ch = 0;
	while( !$me->{cron}{spec}{hrs}[ $ch ] && $ch < 24 ){
	    $ch ++;
	}

	# same time, next day
	$tom = 24 * 60 * 60 if $ch <= $lt[2];

	#print STDERR "fnt2b: $cm, $ch, $tom [@lt]\n";
    }

    # now find earliest minute
    $cm = 0;
    while( !$me->{cron}{spec}{min}[ $cm ] && $cm < 60 ){
	$cm++;
    }

    # QQQ - check for no matching hour/min found?

    #print STDERR "fnt2: $cm, $ch, $tom\n";
    return $t0 + ( $cm - $lt[1] ) * 60 + ( $ch - $lt[2] ) * 3600 + $tom;

}

# check all but minutes, to permit sloppy scheduling
sub spec_match_now {
    my $me = shift;
    my( @t ) = localtime($^T);

    return 0 unless $me->{cron}{spec}{hrs}[ $t[2] ];
    return 0 unless $me->{cron}{spec}{mon}[ $t[4] ];

    # both * => match
    return 1 if !$me->{cron}{spec}{dom} && !$me->{cron}{spec}{dow};

    # one or both specified, only one needs to match
    if( $me->{cron}{spec}{dom} ){
	return 1 if $me->{cron}{spec}{dom}[ $t[3] ];
    }
    if( $me->{cron}{spec}{dow} ){
	return 1 if $me->{cron}{spec}{dow}[ $t[6] ];
	# permit 0 and 7 for Sun.
	return 1 if $me->{cron}{spec}{dow}[ $t[6] + 7 ];
    }

    0;
}

################################################################
# object methods
################################################################
# Take thy fair hour, Laertes; time be thine,
# And thy best graces spend it at thy will!
#     -- Shakepeare, Hamlet

# job dispatch function
sub cronjob {
    my $me = shift;

    if( !$me->{cron}{spec} || $me->spec_match_now() ){
	$me->{cron}{func}->( $me->{cron}{args} );
    }

    if( $me->{cron}{freq} || $me->{cron}{spec} ){
	# reschedule cronjob

	if( $me->{cron}{spec} ){
	    $me->{cron}{time} = $me->next_spec_time();
	    ::warning( "Cron next_spec_time error: t = $me->{cron}{time}, now = $^T" )
		if( $me->{cron}{time} <= $^T );
	}else{
	    $me->{cron}{time} += $me->{cron}{freq};
	    if( $me->{cron}{time} <= $^T ){
		$me->{cron}{time} =
		    (int(($^T - $me->{cron}{time}) / $me->{cron}{freq}) + 1)
			* $me->{cron}{freq} + $me->{cron}{time};
	    }
	}

	$me->add_timed_func( time => $me->{cron}{time},
			     func => \&cronjob,
			     text => "cron" );
    }
}

################################################################
# class global init
################################################################
Doc::register( $doc );

# this cannot be done in BaseIO.pm...
Cron->new( freq => 4*3600,
	   text => 'BaseIO cleanup',
	   func => \&BaseIO::janitor,
	   );

1;
