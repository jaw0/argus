# -*- perl -*-

# Copyright (c) 2003 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2003-Sep-12 17:17 (EDT)
# Function: null control channel
#
# $Id: NullCtl.pm,v 1.1 2003/09/14 21:20:22 jaw Exp $

package NullCtl;
@ISA = qw(Control);

sub new {
    bless {};
}

sub write {
    # nothing
}

sub bummer {
    my $me = shift;
    my $code = shift;
    my $msg = shift;

    $me->{error} = "$code $msg";
}

1;
