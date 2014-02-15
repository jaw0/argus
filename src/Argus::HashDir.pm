# -*- perl -*-

# Copyright (c) 2008 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2008-Jan-21 12:18 (EST)
# Function: directory name hashing
#
# $Id: Argus::HashDir.pm,v 1.2 2008/07/20 22:01:12 jaw Exp $

package Argus::HashDir;
use strict;

# quickly pick a 2 level directory for the file
sub hashed_directory {
    my $file = shift;

    my $h = 5381;
    for my $c (split '', $file){
	$h = (33*$h) + ord($c);
	$h &= 0xFFFFFF;
    }

    my $a = ($h % 26) + 65;
    $h >>= 5;
    my $b = ($h % 26) + 65;
    
    sprintf '%c/%c', $a, $b;
}

sub import {
    my $pkg = shift;
    my $caller = caller;

    no strict;
    *{$caller . '::hashed_directory'} = \&hashed_directory;
}
    
1;
