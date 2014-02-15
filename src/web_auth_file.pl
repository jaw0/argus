# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Sep-17 18:40 (EDT)
# Function: auth info from from a file
#
# $Id: web_auth_file.pl,v 1.5 2003/03/04 20:32:12 jaw Exp $

# file format:
#  username encrypted_passwd home_object groups...

# returns (home_obj, groups) on success
#         undef on failure

my $userfile = "$datadir/users";
sub auth_user {
    my $user = shift;
    my $pass = shift;
    
    open(UF, $userfile) || return;
    while(<UF>){
	chop;
	s/#.$//;
	
	my($cuser, $cpass, $chome, @cgroups) = split;
	next unless $cuser;
	
	if( $user eq $cuser ){
	    close UF;

	    if( ($cpass eq crypt($pass, $cpass)) || ($cpass eq "any") ){
		return ($chome, @cgroups);
	    }

	    return;
	}
    }

    close UF;
    return;
}

1;
