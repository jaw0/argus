# -*- perl -*-

# Copyright (c) 2012
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2012-Sep-15 12:45 (EDT)
# Function: custom dashboards
#
# $Id: Argus::Dashboard::Col.pm,v 1.2 2012/09/16 18:52:49 jaw Exp $

package Argus::Dashboard::Col;
@ISA = qw(Configable Argus::Dashboard);
use vars qw(@ISA $doc);
use strict;

my @param = qw(rowspan colspan width height style cssid cssclass);
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

sub web_make {
    my $me = shift;
    my $fh = shift;

    my $attr = $me->attr(qw(rowspan colspan width height style));
    print $fh "<!-- col -->\n";
    print $fh "<TD$attr valign=top><table cellpadding=0 cellspacing=0>";

    for my $c (@{$me->{children}}){
        print $fh "<tr>";
        $c->web_make($fh);
        print $fh "</tr>";
    }

    print $fh "</table></TD>\n";
    print $fh "<!-- /col -->\n";
}



################################################################
Doc::register( $doc );

1;
