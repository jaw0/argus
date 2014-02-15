
sub xequire;
sub oequire;

require 'conf.pl';
require 'misc.pl';
require 'common.pl';
xequire 'Doc';
xequire 'Argus::Encode';
xequire 'Argus::HashDir';
xequire	'Control';
xequire 'Encoding::BER';
xequire 'Encoding::BER::SNMP';
xequire 'Argus::IP';
xequire 'DNS::UDP';
xequire 'DNS::TCP';
xequire 'Argus::SIP';
xequire 'Argus::SIP::TCP';
xequire 'Argus::SIP::UDP';
xequire 'Argus::RPC';
xequire 'Argus::RPC::TCP';
xequire 'Argus::RPC::UDP';
xequire 'Argus::SNMP::Helper';
xequire 'Argus::SNMP::Conf';
xequire 'Argus::SNMP';
xequire 'Argus::Interpolate';
xequire 'Argus::Compute';
xequire	'BaseIO';
xequire	'Cron';
xequire	'Server';
xequire	'Commands';
xequire 'Argus::ReadConfig';
xequire	'Conf';
xequire	'Configable';
xequire 'Argus::Resolv::IP';
xequire 'Argus::Resolv';
xequire 'Argus::Archivist';
xequire 'Argus::Archive';
xequire 'Argus::Color';
xequire 'Argus::MonEl::Expand';
xequire 'Argus::MonEl::Noise';
xequire 'Argus::MonEl::Trans';
xequire 'Argus::Web::Overview';
xequire 'Argus::Agent';
xequire 'Argus::Asterisk';
xequire 'Argus::Freeswitch';
xequire 'Argus::HWAB';
xequire 'Argus::MHWAB';
xequire	'MonEl';
xequire	'Group';
xequire	'Alias';
xequire	'Service';
xequire	'Error';
xequire	'Notify';
xequire	'Graph';
xequire	'NullConf';
xequire	'UserCron';
xequire	'TestPort';

oequire 'DARP::Slave';
oequire 'DARP::Master';
oequire 'DARP::Conf';
oequire 'DARP::Service';
oequire 'DARP::Watch';
oequire 'DARP::Misc';
oequire 'DARP::MonEl';
xequire 'DARP';

my $t = 1;
sub t {
    my $s = shift;

    print (($s ? '' : 'not '), "ok $t\n");
    $t++;
}

# fake require, for uninstalled modules
sub xequire {
    my $m = shift;
    my $f = "$m.pm";
    require $f;
    $m->import();
    $f =~ s,::,/,g;
    $INC{$f} = 1;
}

# optionally require
sub oequire {
    eval {
	xequire( @_ );
    };
}
