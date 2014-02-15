# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Nov-04 14:55 (EST)
# Function: encode/decode text
#
# $Id: Argus::Encode.pm,v 1.8 2007/01/27 17:14:43 jaw Exp $

package Argus::Encode;
use strict;

# modification of quoted-printable encoding
# encode chars that will cause problems with webpages, etc
sub encode {
    my $txt = shift;

    $txt =~ s/([ \r\n%\#\+\\\;=\"\'\`\?\&~<>\/\000-\037\177-\377])/sprintf("~x%02X",ord($1))/ges;
    $txt;
}

sub url_encode {
    my $txt = shift;

    $txt =~ s/([\x3b-\x3f\x5b-\x5e\x60\x7b-\xff\x00-\x2b\x2f])/sprintf('%%%02X',ord($1))/ges;
    $txt;
}


# And so of these. Which is the natural man,
# And which the spirit? who deciphers them?
#  -- Shakespeare, Comedy of Errors
sub decode {
    my $txt = shift;

    $txt =~ s/~x(..)/chr(hex($1))/ge;
    $txt;
}

sub import {
    my $pkg = shift;
    my $caller = caller;

    for my $f (qw(encode decode url_encode)){
	no strict;
	*{$caller . '::' . $f} = $pkg->can($f);
    }
}
    
1;
