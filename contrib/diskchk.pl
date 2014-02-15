#!/usr/local/bin/perl
#
# Copyright (c) 2003 by Jeremy Kister
# Author: Jeremy Kister <argus-devel at jeremykister.com>
# Date: 2003-Jul-14 19:13 (EDT)
# Function: let argus talk to df via SNMP
#
# take a look at http://www.jeremykister.com
# for hosting/colo/Internet stuff, check out http://www.nntx.net
#
#install, use, and love Net-SNMP (UCD-SNMP should be fine)
#echo 'exec .1.3.6.1.4.1.4502.1.78 diskstats /usr/bin/df -F ufs -k' >>/usr/local/share/snmp/snmpd.conf
#restart snmpd
# note the above df is Solaris' recipie;  yours may differ.
#
#add to argus config:
#	Service Prog {
#		frequency:	300
#		label:  disk usage
#		command:        /usr/local/script/diskchk.pl <hostname>
#		nexpect:        ^WARN:
#		messagedn:      %v
#		messageup:	slices look ok on <hostname>
#	}

die "give me a hostname\n" unless($hostname=shift);
$community = 'public' unless($community=shift);

foreach $line (`snmpwalk -v 1 -c $community $hostname .1.3.6.1.4.1.4502.1.78.101 2>&1`){
        if($line =~ /(\d+)%\s+(\/.*)\"/){
                $percent=$1; $mount=$2;
                if($percent > 95){
                        print "WARN: $mount is at $percent" . "% on $hostname\n";
                }
                $gotdata=1;
        }elsif($line =~ /^Timeout:/){
		print "WARN: SNMP get timed out on $hostname. snmpd running and using the right community?\n";
		exit 1;
	}
}

print "WARN: OID not configured on $hostname\n" unless(defined($gotdata));
