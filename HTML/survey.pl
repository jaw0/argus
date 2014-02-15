#!/usr/local/bin/perl
# -*- perl -*-

# Copyright (c) 2003 by Jeff Weisberg
# Author: Jeff Weisberg <jaw @ tcp4me.com>
# Date: 2003-Feb-12 18:28 (EST)
# Function: argus survey
#
# $Id: survey.pl,v 1.1 2007/02/19 04:20:57 jaw Exp $

$HTML = "/home/penelope/www/htdocs/argusdocs";
use CGI qw(:standard);
use Fcntl;

my $q = new CGI;

if( param('os') ){
    
    


    print $q->header();
    print "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\">\n";
    print "<HTML><HEAD><TITLE>Redirecting...</TITLE>\n";
    print "<META HTTP-EQUIV=\"REFRESH\" CONTENT=\"0; URL=http://argus.tcp4me.com\">\n";
    print "</HEAD><BODY BGCOLOR=\"#FFFFFF\">\n";
    print "</BODY></HTML>\n";
    exit;

}


print $q->header();
print <<EOH;
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
<HTML>
<HEAD>
<TITLE>Argus - System and Network Monitoring Software - Survey</TITLE>
EOH
    ;

open H, "$HTML/top.shtml";
while(<H>){
    s,style.css,/argusdocs/style.css,g;
    print;
}
close H;

print "<H2>Please Tell us about yourself</H2>\n";

print start_form(), "<TABLE>\n";
print Tr( td('Company Name'), td(textfield('company', '', 32))), "\n";
print Tr( td('Company Type'), td(popup_menu('ctype',
					    ['ISP/NSP', 'Large Company', 'Small Business', 'Health Care',
					     'K-12', 'College/University',
					     'Government', 'Military', 'Law Enforcement',
					     'Web Developer', 'Programmer', 'Consultant', 'Other']))), "\n";

print Tr( td('Company URL'),  td(textfield('url', '', 32))), "\n";
print Tr( td('Number of Services<BR>Monitored'), td(textfield('nsrvc', '', 32)));
print Tr( td('Operating System'), td(popup_menu('os',
						['SunOS 4.*', 'Solaris', 'NetBSD', 'FreeBSD', 'OpenBSD',
						 'Linux - RedHat', 'Linux - Debian', 'Linux - Other',
						 'Mac OS X', 'Windows', 'Other - UNIX', 'Other']))), "\n";

print Tr( td('Favorite Features'), td(textfield('favof', '', 32))), "\n";
print Tr( td('Desired Features'),  td(textfield('wantf', '', 32))), "\n";
print Tr( td('Comments / <BR>Suggestions'), td(textarea('comments', '', 10, 32))), "\n";



print Tr(td(), td( submit())), "\n";
print "</TABLE>\n", end_form(), "\n";

open H, "$HTML/bottom.shtml";
while(<H>){
    next if /Last modified/;
    print;
}
close H;
print "</HTML>\n";

