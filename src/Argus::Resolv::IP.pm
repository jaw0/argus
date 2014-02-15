# -*- perl -*-

# Copyright (c) 2012
# Author: Jeff Weisberg <jaw @ tcp4me.com>
# Created: 2012-Sep-21 19:24 (EDT)
# Function: 
#
# $Id: Argus::Resolv::IP.pm,v 1.6 2012/12/02 22:21:40 jaw Exp $

package Argus::Resolv::IP;
use Socket;
use strict;

my $TOOLONG = 300;
my $AUTOCONF = 1;

sub autoconf {
    my $v = shift;

    $AUTOCONF = ::ckbool($v);
}

sub new {
    my $class = shift;
    my $name  = shift;
    my $vers  = shift;
    my $cf    = shift;

    if( ! $Argus::Resolv::enable_p && $AUTOCONF ){
        # enable resolver
        # might fail if there is no resolv.conf
        eval { create_resolver($cf); };
        $AUTOCONF = 0 if $@;
    }

    my $me = bless {
        created => $^T,
        names	=> _names_opts( $name ),
        vers	=> [ split /\s+/, $vers ],
        curidx  => 0,
    }, $class;

    if( $Argus::Resolv::enable_p ){
        for my $n (@{$me->{names}}){
            Argus::Resolv::resolv_add( $cf, $n->{name} );
        }

    }else{
        for my $n (@{$me->{names}}){
            my $ip = ::resolve( $n );
            push @{$me->{addr}}, $ip if $ip;
        }
        unless( $me->{addr} ){
	    return $cf->error( "cannot resolve host '$name'" );
	}
    }

    return $me;
}

# hostname: foo1.example.com foo2.example.com
# hostname: foo1.example.com._ipv4

sub _names_opts {
    my $name = shift;

    my @names;

    if( $Argus::Resolv::enable_p ){
        for my $n (split /\s+/, $name){
            $n = _normalize($n);

            if( $n =~ /(\S+)\._ipv(\d)/ ){
                $n = $1;
                my $opt = ($2 == 6) ? 'AAAA' : 'A';
                push @names, {name => $1, opts => $opt };
            }else{
                push @names, {name => $n};
            }
        }

    }else{
        @names = map { _normalize($_) } split /\s+/, $name;
    }

    return \@names;
}

sub _normalize {
    my $name = shift;

    $name = lc($name);
    # ...
    $name;
}

sub refresh {
    my $me  = shift;
    my $obj = shift;


    if( $Argus::Resolv::enable_p ){

        return if $me->{expire} > $^T;

        my @a;
        my @aaaa;
        my $expire;

        for my $n (@{$me->{names}}){
            $obj->debug("checking resolver: $n->{name}");
            my $res = Argus::Resolv::resolv_results($n->{name}, $n->{opts});
            next unless $res;

            for my $a (@{$res->{addr}}){
                push @a, $a    if length($a) == 4;
                push @aaaa, $a if length($a) != 4;

                $obj->debug("resolved " . ::xxx_inet_ntoa($a));
            }

            $expire = $res->{expire} if $res->{expire} && (!$expire || $res->{expire} < $expire);
            $obj->debug("resolv expire $res->{expire} - $expire");
        }

        my @res;
        for my $p ( @{$me->{vers}} ){
            push @res, @a if $p == 4;
            push @res, @aaaa if $p == 6;
        }

        $me->{addr}   = \@res;
        $me->{expire} = $expire;
    }
}

sub next_needed {
    my $me = shift;
    my $t  = shift;

    return if $me->{expire} > $t;

    if( $Argus::Resolv::enable_p ){
        for my $n (@{$me->{names}}){
            Argus::Resolv::resolve_next_needed($n->{name}, $t);
        }
    }
}


# are these the same server?
sub is_same {
    my $me = shift;
    my $as = shift;

    # is there an address in common?
    for my $a ( @{$me->{addr}} ){
        return 1 if grep { $_ eq $a } @{$as->{addr}};
    }

    undef;
}

sub addr {
    my $me = shift;

    $me->{_addr} = $me->{addr}[ $me->{curidx} % @{$me->{addr}} ];
    return $me->{_addr};
}

sub ipver {
    my $me = shift;

    return unless $me->{_addr};
    return (length($me->{_addr}) == 4) ? 4 : 6;
}

sub try_another {
    my $me = shift;

    $me->{curidx} = ($me->{curidx} + 1) % @{$me->{addr}};
}

sub is_valid {
    my $me = shift;

    return ($me->{addr} && @{$me->{addr}}) ? 1 : 0;
}

sub is_timed_out {
    my $me = shift;

    return 0 if $me->is_valid();

    my $to = ::topconf('resolv_timeout') || $TOOLONG;
    $to += $me->{created};

    return ($to < $^T) ? 1 : 0;
}

sub create_resolver {
    my $cf = shift;

    my $resolv = Service->new(
        type	=> 'Service',
	name	=> 'Resolv',
	parents	=> [ $::Top ],
	notypos => 1,
        autoconf => 1,
        config => {
            frequency	=> 2,
        },
    );

    $resolv->config($cf);
    $resolv->{parents} = []; # orphan
}

sub about {
    my $me = shift;

    unless( $me->is_valid() ){
        if( $me->is_timed_out() ){
            return "[cannot resolve]";
        }else{
            return "[resolving in progress]";
        }
    }

    return join(' ', map { ::xxx_inet_ntoa($_) } @{$me->{addr}});
}

1;
