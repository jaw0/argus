# -*- perl -*-

# Copyright (c) 2012
# Author: Jeff Weisberg <jaw @ tcp4me.com>
# Created: 2012-Sep-15 14:51 (EDT)
# Function: 
#
# $Id: Argus::Dashboard::Iframe.pm,v 1.2 2012/09/16 18:52:49 jaw Exp $

package Argus::Dashboard::Iframe;
@ISA = qw(Argus::Dashboard::Widget);
use vars qw(@ISA);
use strict;



sub cf_widget {
    my $me = shift;
    my $cf = shift;
    my $line = shift;

    $line =~ s/\s*{$//;
    my(undef, $url) = split /\s+/, $line, 2;
    $url =~ s/^"(.*)"$/$1/;

    $me->{iframesrc} = $url;
    $me;
}

sub web_make_widget {
    my $me = shift;
    my $fh = shift;

    my $attr;
    $attr .= " class=\"$me->{width}\""  if $me->{width};
    $attr .= " class=\"$me->{height}\"" if $me->{height};

    print $fh qq{<iframe $attr src="$me->{iframesrc}" frameborder=0 scrolling=no></iframe>\n};

}

1;
