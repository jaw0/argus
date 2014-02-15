# -*- perl -*-

# Copyright (c) 2007 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2007-Jan-27 10:28 (EST)
# Function: expand % sequences
#
# $Id: Argus::MonEl::Expand.pm,v 1.4 2012/10/12 02:17:31 jaw Exp $

package MonEl;
use POSIX ('strftime', 'tzset');
use strict;

sub no_encode { $_[0] }

sub expand {
    my $me  = shift;
    my $fmt = shift;
    my %p   = @_;

    my $data = $p{data}   || {};	# additional 'letter => value' mappings
    my $enc  = $p{encode} || \&no_encode;
    my $time = $p{time}   || $::TIME;


    while( $fmt =~ /%[zt]/ ){
	my $tz = $ENV{TZ};
	my( $t, $z, $f, @l );

	if( $fmt =~ /%t{([^\}]+)}/ ){
	    $f = $1;
	}else{
	    $f = $p{dtformat};
	}
	if( $f ){
	    if( $p{localtime} ){
		if( $me->{timezone} ){
		    $ENV{TZ} = $me->{timezone};
		    tzset();
		}
		@l = localtime($time);
	    }else{
		@l = gmtime($time);
	    }
	    $t = strftime $f, @l;
	    $z = strftime "%z", @l;

	    if( $p{localtime} && $me->{timezone} ){
		$ENV{TZ} = $tz;
		delete $ENV{TZ} unless defined $tz;
		tzset();
	    }

	}else{
	    # timet
	    $t = $time;
	    $z = 'Z';
	}

	$fmt =~ s/%z/$enc->($z)/es;
	$fmt =~ s/%t({[^\}]+})?/$enc->($t)/es;
    }

    # any object param via %o{param}
    while( $fmt =~ /%o/ ){
    	my( $param, $value );

	if( $fmt =~ /%o{([^\}]+)}/ ){
	    $param = $1;
	    $param =~ s/^\s+//;
	    $param =~ s/\s+$//;

	    eval {
		$value = $me->getparam($param);
	    };
	    if( $@ ){
		$value = 'Param Not Found';
            }
	}else{
	    $value = $data->{o} || $me->unique();
	}
        $fmt =~ s/%o({[^\}]+})?/$enc->($value)/es;
    }

    # specified mappings before standard ones, so they can override
    my $l = join('', keys %$data);
    $fmt =~ s/%([$l])/$enc->($data->{$1})/ges if $l;

    $fmt =~ s/%d/$enc->($DARP::info->{tag})/ges if defined $DARP::info;
    $fmt =~ s/%r/$enc->($me->{srvc}{reason})/ges;
    $fmt =~ s/%s/uc($enc->($me->{ovstatus}))/ges;
    $fmt =~ s/%v/$enc->($me->{srvc}{result})/ges;

    $fmt = ::expand_conditionals( $fmt );

    $fmt;
}


1;
