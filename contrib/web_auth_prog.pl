# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Sep-17 18:40 (EDT)
# Function: auth info from from a program
#
# $Id: web_auth_prog.pl,v 1.1 2011/10/29 15:36:13 jaw Exp $

# returns (home_obj, groups) on success
#         undef on failure

# program should take user\n pass\n on stdin
# and return: home_obj groups...\n on stdout
# or, on failure, \n

require "open2.pl";

$COMMAND = "command";
sub auth_user {
    my $user = shift;
    my $pass = shift;


    open2(RC, WC, $COMMAND) || return;
    print WC "$user\n$pass\n";
    close WC;

    my $line = <RC>;
    chop $line;
    close RC;
    
    return unless $line;
    return (split /\s+/, $line);

}

