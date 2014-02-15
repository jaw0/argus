# -*- perl -*-

# Copyright (c) 2012
# Author: Jeff Weisberg <jaw @ tcp4me.com>
# Created: 2012-Sep-15 14:51 (EDT)
# Function: 
#
# $Id: Argus::Dashboard::Status.pm,v 1.2 2012/09/16 18:52:49 jaw Exp $

package Argus::Dashboard::Status;
@ISA = qw(Argus::Dashboard::Widget);
use vars qw(@ISA);
use strict;

# status [top] "GROUP"
# status { OBJECT ... }


sub cf_widget {
    my $me = shift;
    my $cf = shift;
    my $line = shift;

    my($group) = $line =~ /"(.*)"/;

    if( $line =~ /status\s+(top|numbers)\s/ ){
        $me->{mode} = 'top';
    }else{
        $me->{mode} = 'base';
    }

    # make sure objects exist
    if( $group ){
        $me->{list} = $group;
        $cf->nonfatal("no such object '$group'") unless MonEl::find($group);
    }else{
        for my $c (@{$me->{list}}){
            $cf->nonfatal("no such object '$c'") unless MonEl::find($c);
        }
    }

    $me;
}

sub web_make_widget {
    my $me = shift;
    my $fh = shift;

    my $top = $me->{mode} eq 'top';

    if( !ref $me->{list} ){
        my $obj = MonEl::find( $me->{list} );
        if( $obj ){
            $obj->web_page_group_status( $fh, $top );
        }else{
            print $fh "ERROR: invalid object '$me->{list}'";
        }
    }else{
        print $fh "<table>\n";
        if( $top ){
            print $fh "<TR><TH><L10N Name></TH><TH><L10N Up></TH><TH><L10N Down></TH><TH>",
              "<L10N Override></TH></TR>\n";
        }else{
            print $fh "<TR><TH><L10N Name></TH><TH COLSPAN=3><L10N Status></TH></TR>\n";
        }

        for my $c (@{$me->{list}}){
            my $obj = MonEl::find( $c );

            unless( $obj ){
                print $fh "<tr><td colspan=4>ERROR: invalid object '$c'</td></tr>";
                next;
            }

            if( $top ){
                $obj->web_page_row_top($fh);
            }else{
                $obj->web_page_row_base($fh);
            }
        }
        print $fh "</table>\n";
    }

}

1;
