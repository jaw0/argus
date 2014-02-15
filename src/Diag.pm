# -*- perl -*-

# Copyright (c) 2004 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2004-Feb-01 13:41 (EST)
# Function: enable (some) warnings, for debugging
#
# $Id: Diag.pm,v 1.3 2007/01/05 04:01:50 jaw Exp $


$^W = 1 unless defined &DB::DB;

$SIG{__WARN__} = sub {
    my $msg = shift;
    
    return if $msg =~ /Use of uninitialized value/;
    return if $msg =~ /Argument.*isn\'t numeric/;
    return if $msg =~ /Useless use of a variable in void context/;
    return if $msg =~ /Maybe you meant system/;
    return if $msg =~ /Can\'t locate package.*for \@Control::ISA/;
    return if $msg =~ /splice\(\) offset past end of array at/;
    
    warn( $msg );
    
};

1;

