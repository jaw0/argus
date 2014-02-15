# -*- perl -*-

# Copyright (c) 2012
# Author: Jeff Weisberg <jaw @ tcp4me.com>
# Created: 2012-Sep-15 14:51 (EDT)
# Function: 
#
# $Id: Argus::Dashboard::Graph.pm,v 1.5 2012/10/13 18:36:12 jaw Exp $

package Argus::Dashboard::Graph;
@ISA = qw(Argus::Dashboard::Widget);
use vars qw(@ISA);

use Argus::Encode;
use strict;

my %byname = ();
my $NAME = 'aaaaaa';

# graph samples|hours|days  large|thumb  "OBJECT"
# graph samples|hours|days  large|thumb { SERVICE ... }

sub cf_widget {
    my $me = shift;
    my $cf = shift;
    my $line = shift;

    # give graph a unique name
    $me->{name} = $NAME ++;
    $byname{ $me->{name} } = $me;

    $me->init_from_config( $cf, $MonEl::doc, 'image' );
    $me->init_from_config( $cf, $MonEl::doc, 'web' );

    $line =~ s/\s+\{\s*$//;
    my(undef, $which, $size, $obj) = split /\s+/, $line, 4;

    if( !grep { $which eq $_ } qw(samples hours days) ){
        $cf->nonfatal( "invalid graph widget in config file: '$_' try [samples hours days]" );
        $me->{conferrs} ++;
        return;
    }

    if( $size ne 'thumb' && $size ne 'large' && $size !~ /\d+x\d+/ ){
        $cf->nonfatal( "invalid graph widget in config file: '$_' try [thumb large]" );
        $me->{conferrs} ++;
        return;
    }

    $me->{graph} = 1;
    $me->{which} = $which;
    $me->{size}  = $size;

    if( $obj ){
        $obj =~ s/"(.*)"/$1/;
        $me->{list} = $obj;
        $cf->nonfatal("no such object '$obj'") unless MonEl::find($obj);
    }else{
        for my $c (@{$me->{list}}){
            $cf->nonfatal("no such object '$c'") unless MonEl::find($c);
        }
    }


    $me;

}

sub find {
    my $name = shift;

    $name =~ s/^Dash:Graph://i;
    my $obj = $byname{ $name };

    if( ! ref $obj->{list} ){
        # return the underlying object directly
        # so we use its graph params
        return MonEl::find($obj->{list});
    }

    return $obj;
}

sub url {
    my $me = shift;
    my @param = @_;

    my $f = encode('Dash:Graph:' . $me->{name});

    return "__BASEURL__?object=$f" . join(';', '', @param);
}

sub graphlist {
    my $me = shift;

    my @g;
    for my $c (@{$me->{list}}){
        my $obj = $MonEl::byname{$c};
        my @x = $obj->graphlist();

	foreach my $x (@x){
            my $pl = $obj->{label_right} || $obj->{label} || $obj->{name};

            if( $x->{label} ){
                $x->{label} = "$pl:$x->{label}";
            }else{
                $x->{label} = $pl;
            }
        }

	push @g, @x;
    }
    return @g;
}

sub web_make_widget {
    my $me = shift;
    my $fh = shift;

    my $which = $me->{which};

    my $url = $me->url('func=graph', "which=$me->{which}", "size=$me->{size}", 'ext=.png');
    my $big = $me->url('func=graphpage', "which=$me->{which}", 'size=full' );

    my $attr;
    $attr .= " class=\"$me->{width}\""  if $me->{width};
    $attr .= " class=\"$me->{height}\"" if $me->{height};
    my $caption = $me->expand( $me->{caption} );

    print $fh "\t<A HREF=\"$big\"><IMG BORDER=0 $attr SRC=\"$url\" ALT=\"graph\"></A>";
    print $fh "<BR><center><A class=graphlabel HREF=\"$big\">$caption</A></center>" if $me->{caption};

}

1;
