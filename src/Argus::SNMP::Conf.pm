# -*- perl -*-

# Copyright (c) 2012
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2012-Oct-06 12:53 (EDT)
# Function: add snmp oids from config file
#
# $Id: Argus::SNMP::Conf.pm,v 1.3 2012/10/27 03:12:18 jaw Exp $

package Argus::SNMP::Conf;
@ISA = qw(Configable);
use vars qw(@ISA);
use strict;


sub config {
    my $me   = shift;
    my $cf   = shift;
    my $more = shift;

    $me->{config}{oid} = $more if $more;

    Argus::SNMP::add_mib_def( $cf, $me->{name}, $me->{config} );
    1;
}


sub gen_confs {

    my $r;

    for my $o (Argus::SNMP::get_user_conf()){
        $r .= "snmpoid $o->{_name} {\n";
        for my $k (keys %$o){
            next if $k =~ /^_/;
            $r .= "\t$k:\t$o->{$k}\n" if defined $o->{$k};
        }
        $r .= "}\n";
    }

    $r = "\n$r" if $r;
    return $r;
}

# for create_object
sub resolve_depends {}
sub jiggle {}


1;
