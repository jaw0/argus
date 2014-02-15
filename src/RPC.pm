# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Sep-24 12:22 (EDT)
# Function: quick RPC test example code
#
# $Id: RPC.pm,v 1.4 2002/10/22 20:48:08 jaw Exp $

# example code - turn RPC test into Prog test - run rpcinfo

# Service RPC/UDP/100000 {
# 	hostname: foo.example.com
# }

package RPC;
@ISA = qw(Prog);

sub probe {
    my $name = shift;

    return ( $name =~ /^RPC/ ) ? [ 3, \&config ] : undef;
}

sub config {
    my $me = shift;
    my $cf = shift;
    my( $name, $prog, $proto, $host );

    bless $me;
    $name = $me->{name};
    ($proto, $prog) = $name =~ m,RPC/(.*)/(.*),;
    $host = $me->{srvc}{hostname};
    $proto = lc($proto);
    
    $me->{prog}{command} = "rpcinfo -T $proto $host $prog";
    
    return $cf->error( "invalid RPC spec" )
	unless $prog && $proto && $host;

    $me->{label_right_maybe} ||= $prog;

    $me->SUPER::config($cf);
    $me->{uname} = "RPC_${host}_$prog";
    $me;
}

push @Service::probes, \&probe;

1;
