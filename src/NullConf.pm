# -*- perl -*-

# Copyright (c) 2003 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2003-Jan-13 18:30 (EST)
# Function: null config object - for error capturing
#
# $Id: NullConf.pm,v 1.4 2003/03/19 18:48:27 jaw Exp $

# The forms of things unknown, the poet's pen
# Turns them to shapes, and gives to airy nothing
# A local habitation and a name.
#   -- Shakespeare, A Midsummer Night's Dream

package NullConf;
@ISA = qw(Conf);

sub new {
    bless {};
}

sub error {
    my $me = shift;
    my $msg = shift;
    my( $m );

    $me->{error} = $msg;
    $m = "ERROR: $msg";
    ::loggit( $m, 1 );	# QQQ - should it go to log file or not?

    die $me;
    undef;
}

sub warning {
    my $me = shift;
    my $msg = shift;
    my( $m );

    $me->{warning} = $msg;
    $m = "WARNING: $msg";
    ::loggit( $m, 1 );
    undef;
}

sub nextfile { undef }
sub nextline { undef }

1;
