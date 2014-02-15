# -*- perl -*-

# Copyright (c) 2004 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2004-Dec-26 13:41 (EST)
# Function: sun remote procedure call - RFC 1057
#
# $Id: Argus::RPC.pm,v 1.5 2008/07/20 22:01:12 jaw Exp $

package Argus::RPC;

use strict qw(refs vars);
use vars qw($doc @ISA $HAVE_S6);

$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [],
    methods => {},
    versn => '3.4',
    html  => 'services',
    fields => {
      rpc::prognum => {
	  descr => 'RPC program number',
	  attrs => ['config'],
	  exmpl => '100003',
      },
      rpc::version => {
	  descr => 'RPC program version number',
	  attrs => ['config'],
	  exmpl => '2',
      },
      rpc::portmap_port => {
	  descr => 'RPC portmapper port number',
	  attrs => ['config', 'inherit'],
	  default => 111,
      },
      rpc::portmap_version => {
	  descr => 'RPC portmapper version number',
	  attrs => ['config', 'inherit'],
	  default => 2,
      },
      rpc::state => { descr => 'internal rpc state' },
	
    },
};

my %rpc =
qw(
portmapper      100000
rstatd          100001
rusersd         100002
nfs             100003
ypserv          100004
mountd          100005
remote_dbx	100006
ypbind          100007
walld           100008
yppasswdd       100009
etherstatd      100010
rquotad         100011
sprayd          100012
3270_mapper     100013
rje_mapper      100014
selection_svc   100015
database_svc    100016
rexd            100017
alis            100018
sched           100019
llockmgr        100020
nlockmgr        100021
x25             100022
statmon         100023
status          100024
select_lib      100025
bootparam       100026
mazewars        100027
ypupdated       100028
keyserv         100029
securelogin     100030
nfs_fwdlnit     100031
nfs_fwdtrns     100032
sunlink_mapper	100033
net_monitor	100034
database	100035
passwd_auth	100036
tfsd            100037 
nsed            100038
nsemntd         100039
pfs_mountd	100040
pcnfsd          150001
amd             300019
);

sub config {
    my $me = shift;
    my $cf = shift;
    my( $name, $t, $n, $z );

    $name = $me->{name};
    my @n = split /\//, $name;
    shift @n;
    shift @n;
    $me->{rpc}{prognum} = shift @n;
    $me->{rpc}{version} = shift @n;

    $me->init_from_config( $cf, $doc, 'rpc' );

    $me->{label_right_maybe} = $me->{rpc}{prognum};
    
    if( $me->{rpc}{prognum} !~ /^\d+$/ ){
	$me->{rpc}{prognum} = $rpc{$me->{rpc}{prognum}};
    }

    $cf->error("invalid RPC prognum") unless $me->{rpc}{prognum};
    
    $me;
}

################################################################
Doc::register( $doc );

1;
