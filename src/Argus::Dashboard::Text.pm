# -*- perl -*-

# Copyright (c) 2012
# Author: Jeff Weisberg <jaw @ tcp4me.com>
# Created: 2012-Sep-15 14:51 (EDT)
# Function: 
#
# $Id: Argus::Dashboard::Text.pm,v 1.2 2012/10/13 18:36:12 jaw Exp $

package Argus::Dashboard::Text;
@ISA = qw(Argus::Dashboard::Widget);
use vars qw(@ISA);
use strict;

# text { }

sub cf_widget {
    my $me = shift;
    my $cf = shift;
    my $line = shift;

    $me;
}

sub web_make_widget {
    my $me = shift;
    my $fh = shift;

    for my $l (@{$me->{list}}){
        print $fh $me->expand( $l ), "\n";
    }
}

1;
