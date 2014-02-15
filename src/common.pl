#!/usr/local/bin/perl
# -*- perl -*-

# Copyright (c) 2012
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2012-Sep-29 13:18 (EDT)
# Function: 
#
# $Id: common.pl,v 1.1 2012/09/29 21:23:01 jaw Exp $


BEGIN {
    eval {
	require Digest::MD5;
	require Digest::HMAC;
        Digest::MD5->import('md5');
        Digest::HMAC->import('hmac_hex');
    };
}


use strict;

sub random_cookie {
    my $len = shift;

    my @set = ('A'..'Z', 'a'..'z', '0'..'9', '_', '.');

    my $pool = time() ^ $$;

    if( open( DEVRND, "/dev/urandom" ) ){
        my($c, $buf);
	foreach (1..$len){
	    sysread( DEVRND, $buf, 1 );
	    my $v = ord($buf);
	    $pool ^= ($v & ~63) >> (rand(5)+1);
	    $c .= $set[ ($pool ^ $v) & 63 ];
	}
	close DEVRND;
        return $c;
    }else{
        my $c;
	foreach (1..$len){
            my $v = random(0xFFFFFFFF);
            $pool ^= ($v & ~63) >> (rand(5)+1);
            $c .= $set[ ($pool ^ $v) & 63 ];
        }
        return $c;
    }
}

sub calc_hmac {
    my $key = shift;
    my %p   = @_;

    my $t = '';
    foreach my $k (sort keys %p){
	next unless defined $p{$k};
	next if $k eq 'hmac';
	$t .= "$k: $p{$k}; ";
    }

    hmac_hex($t, md5($key), \&md5);
}


1;
