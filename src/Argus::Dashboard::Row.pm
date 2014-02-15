# -*- perl -*-

# Copyright (c) 2012
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2012-Sep-15 12:45 (EDT)
# Function: custom dashboards
#
# $Id: Argus::Dashboard::Row.pm,v 1.2 2012/09/16 18:52:49 jaw Exp $

package Argus::Dashboard::Row;
@ISA = qw(Configable Argus::Dashboard);
use vars qw(@ISA $doc);
use strict;


my @param = qw(colspan width height style align cssid cssclass);
$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [],
    versn => '3.7',
    html  => 'dashboard',
    methods => {},
    conf => {
	quotp => 0,
	bodyp => 1,
    },
    fields => {
        map {
            ($_ => {
                descr => 'dashboard layout parameter',
                attrs => ['config'],
            })
        } @param,
    },
};

sub config {
    my $me = shift;
    my $cf = shift;
    my $more = shift;

    $me->init_from_config( $cf, $doc, '' );
    $me->check($cf);
    $me;
}

sub width {
    my $me = shift;

    my $w;
    for my $c (@{$me->{children}}){
        $w += $c->{colspan} || 1;
    }
    return $me->{colspan} || $w;
}

sub web_make {
    my $me = shift;
    my $fh = shift;

    print $fh "<!-- row -->\n";
    my $attr  = $me->attr(qw(width height));
    my $style = $me->{style} ? qq{ style="$me->{style}"} : '';
    $style .= qq{ align="$me->{align}"} if $me->{align};

    # if we have TD, put the style there, otherwise on the TR
    $attr .= $style unless $me->{colspan};
    print $fh "<TR$attr>";

    if( $me->{colspan} ){
        print $fh "<TD colspan=$me->{colspan} valign=top $style><TABLE cellspacing=0 cellpadding=2><TR>\n";
    }

    for my $c (@{$me->{children}}){
        $c->web_make($fh);
    }

    if( $me->{colspan} ){
        print $fh "</TR></TABLE></TD>\n";
    }

    print $fh "</TR>\n";
    print $fh "<!-- /row -->\n";
}


################################################################
Doc::register( $doc );

1;
