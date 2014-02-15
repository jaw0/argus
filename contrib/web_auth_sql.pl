# -*- perl -*-
#
# Copyright (c) 2003-2005 by Jeremy Kister
# Author: Jeremy Kister <argus-devel at jeremykister.com>
# Date: 2005/02/21 08:18 (EDT)
# Function:  authenticate via sql server
#
# take a look at http://jeremy.kister.net/
# for hosting/colo/Internet stuff, check out http://www.nntx.net

# returns (home_obj, groups) on success
#         undef on failure

# Table structure for table `argus`
#
# CREATE TABLE `argus` (
#   `username` varchar(16) NOT NULL default '',
#   `crypt` char(13) NOT NULL default '',
#   `chome` varchar(255) NOT NULL default '',
#   `cgroups` varchar(255) NOT NULL default '',
#   PRIMARY KEY (`username`)
# ) TYPE=MyISAM COMMENT='argus.example.net authentication' AUTO_INCREMENT=17 ;
#
#  INSERT INTO argus VALUES ('anonymous', 'any', 'Top', 'user');


use DBI;

my $dbun = 'db_username';
my $dbpw = 'db_password';
my $dsn = 'DBI:mysql:host=mysql.example.net;database=example';


sub auth_user {
	my $user = shift;
	my $pass = shift;
   
	my ($dbh,$timeout);
	eval {
		local $SIG{ALRM} = sub { $timeout = 1; };
		alarm(10);
		$dbh = DBI->connect($dsn, $dbun, $dbpw);
		alarm(0);
	};
	alarm(0);
	if($timeout){
		warn "timed out connecting to database: allowing user [${user}] from [$ENV{'REMOTE_ADDR'}] to log in as root.\n";
		return('Top','root'); # you dont want to be blind just because your db is off-line
	}
	my $sql = 'SELECT crypt,chome,cgroups FROM argus WHERE username = ' . $dbh->quote($user);
	my $sth = $dbh->prepare($sql);
	$sth->execute;
  
	my $row=$sth->fetchrow_arrayref;
	my $crypt = $row->[0];
	my $chome = $row->[1];
	my @cgroups = split /\s+/, $row->[2];

	$sth->finish;
	$dbh->disconnect();
  
	if( (($crypt eq crypt($pass, $crypt)) && defined($crypt)) || ($crypt eq 'any') ){
		return ($chome, @cgroups);
	}
	return;
}
