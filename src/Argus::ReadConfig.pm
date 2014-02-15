# -*- perl -*-

# Copyright (c) 2010 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2010-Jan-06 19:19 (EST)
# Function: read+parse config file
#
# $Id: Argus::ReadConfig.pm,v 1.5 2012/10/12 02:17:31 jaw Exp $

package Argus::ReadConfig;
use strict;

my %TYPE = (
    notme			=> 'method',
    'usercron'			=> 'cron',
    'darp::conf'  		=> 'slave',
    'argus::dashboard'  	=> 'dashboard',
    'argus::dashboard::row'  	=> 'row',
    'argus::dashboard::col'  	=> 'col',
    'argus::dashboard::widget'  => 'widget',
    'argus::snmp::conf'		=> 'snmpoid',
    );

my @WIDGET = qw(status graph overview iframe text);

my %READ = (
    top		=> { mknext(qw(group host resolv method snmpoid darp dashboard)) },
    group	=> { quot => 1, onel => 0, level => 2, func => \&read_group,   mknext(qw(group host service alias cron schedule)) },
    host	=> { quot => 1, onel => 0, level => 2, func => \&read_host,    mknext(qw(group host service alias cron schedule)) },
    alias	=> { quot => 2, onel => 1, level => 2, func => \&read_alias,   mknext(qw(group host service alias cron)) },
    service	=> { quot => 0, onel => 1, level => 2, func => \&read_service, mknext(qw(cron schedule)) },
    cron	=> { quot => 1, onel => 1, level => 2, func => \&read_cron },
    method	=> { quot => 1, onel => 1, level => 1, func => \&read_meth,    mknext(qw(schedule)) },
    resolv	=> { quot => 0, onel => 1, level => 1, func => \&read_resolv },
    schedule	=> { quot => 0, onel => 0, level => 1, func => \&read_sched },
    snmpoid	=> { quot => 0, onel => 1, level => 1, func => \&read_mib },

    # DARP
    darp	=> { quot => 1, onel => 0, level => 1, func => \&read_darp,    mknext(qw(master slave)) },
    master	=> { quot => 1, onel => 0, level => 1, func => \&read_master },
    slave	=> { quot => 1, onel => 0, level => 1, func => \&read_slave },

    # Dashboard
    dashboard	=> { quot => 1, onel => 0,  level => 2, func => \&read_dash,    mknext(qw(row col)) },
    row		=> { quot => 0, noname => 1, onel => 0, level => 1, func => \&read_dashrow, mknext(qw(col), @WIDGET) },
    col		=> { quot => 0, noname => 1, onel => 0, level => 1, func => \&read_dashcol, mknext(@WIDGET) },
    status	=> { func => \&read_dashstatus },
    overview	=> { func => \&read_dashoverview },
    graph	=> { func => \&read_dashgraph },
    iframe	=> { func => \&read_dashiframe },
    text	=> { func => \&read_dashtext },

   );

# Reading maketh a full man
#   -- Francis Bacon

sub readconfig {
    my $class = shift;
    my $cf    = shift;
    my $mom   = shift;
    my $more  = shift;

    my $me  = $class->new();
    my $opt = $READ{ $TYPE{lc($class)} || lc($class) };

    $me->{parents} = [ $mom ] if $mom;

    my $line = $cf->nextline();

    my($type, $name, $extra);
    if( $opt->{quot} == 2 ){
        # type "name" "name"
        ($type, $name, $extra) = $line =~ /^\s*([^:\s]+)\s+\"([^\"]+)\"\s+\"([^\"]+)\"/;
        $more = $extra;
    }elsif( $opt->{quot} ){
        ($type, $name) = $line =~ /^\s*([^:\s]+)\s+\"(.+)\"/;		# type "name"
    }else{
        # type name [name]
        (my $l = $line) =~ s/\s*{\s*$//;
        ($type, $name, $extra) = split /\s+/, $l;
        $type =~ s/:$//;
        $more = $extra if $extra;
    }
    unless( $type ){
        ($type) = $line =~ m|^\s*([^\s:/]+)|;
    }


    $me->cfinit($cf, $name, "\u\L$type");

    if( !$name && !$opt->{noname} ){
        $cf->nonfatal( "invalid entry in config file, param expected: '$_'" );
	$cf->eat_block() if $line =~ /\{\s*$/;
	return ;
    }

    if( $line =~ /\{\s*$/ ){
        readblock( $me, $cf, $class, 1 );
    }else{
        unless( $opt->{onel} ){
            eval{ $cf->error( "invalid entry in config file, block expected: '$_'" ); };
            return ;
        }
    }

    $me->config($cf, $more);
    return $me;
}

# The bookful blockhead, ignorantly read,
# With loads of learned lumber in his head.
#   -- Alexander Pope, Essay on Criticism

sub readblock {
    my $me    = shift;
    my $cf    = shift;
    my $class = shift;
    my $open  = shift;
    my $doc   = shift;

    my $opt = $READ{ $TYPE{lc($class)} || lc($class) };
    my $balanced = ! $open;
    my $level    = 0;
    my $nhost    = 0;

    while( defined($_ = $cf->nextline()) ){
        if( /^\s*\}/ ){
            $balanced = 1;
            last;
        }

        my($what) = m|^\s*([^\s:/]+)|i;
        $what = lc $what;

        if( $opt->{next}{$what} && $READ{$what} ){
            $cf->ungetline($_);

            my $nl = $READ{$what}{level};
            if( $nl < $level ){
                $cf->error("$what block must appear before any Groups or Services") if $nl == 2;
                $cf->error("$what block must appear after any Groups or Services")  if $nl == 3;
            }
            $level = $nl;

            $READ{$what}{func}->($cf, $me);
        }
        elsif( /:/ ){
            my($k, $v) = split /:[ \t]*/, $_, 2;
            # data must be before Service|Group|Alias
            if( $level ){
                $cf->warning( "additional data not permitted here (ignored)" );
                next;
            }

            my $warn;
            $warn = 1 if defined $me->{config}{$k};

            if( $k eq 'hostname' && $me->{type} eq 'Host' ){
                # allow Host to redefine hostname without a warning
                $warn = 0 unless $nhost++ > 0;
            }

            if( $doc && Configable::has_attr($k, $doc, 'multi') ){
                push @{$me->{config}{$k}}, $v;	# QQQ
            }else{
                $cf->warning( "redefinition of parameter '$k'" )
                  if $warn;

                $me->{config}{$k} = $v;
                $me->{_config_location}{$k} = $cf->currpos();
            }

            if( $doc ){
                $me->{confck}{$k} = 1 if Configable::has_attr($k, $doc, 'top');
                if( my $c = $doc->{fields}{$k}{callback} ){
                    $c->($v, $cf) unless $::opt_t;
                }
            }
        }
        else{
            # Reading what they never wrote
            #   -- William Cowper, The Task
            $cf->nonfatal( "invalid entry in config file, $what not permitted in $class: '$_'" );
            $cf->eat_block() if /\{\s*$/;
            $me->{conferrs} ++;
            # attempt to continue
        }
    }

    unless( $balanced ){
        $cf->error( "end of file reached looking for closing }");
        return;
    }

    return;
}

sub read_group {
    my $cf = shift;
    my $me = shift;

    my $x = Group->readconfig($cf, $me);
    push @{$me->{children}}, $x if $x;
    $x;
}

sub read_host {
    my $cf = shift;
    my $me = shift;

    my $x = Group->readconfig($cf, $me);
    push @{$me->{children}}, $x if $x;
    $x;
}

sub read_alias {
    my $cf = shift;
    my $me = shift;

    my $x = Alias->readconfig($cf, $me);
    push @{$me->{children}}, $x if $x;
    $x;
}

sub read_service {
    my $cf = shift;
    my $me = shift;

    my $x = Service->readconfig($cf, $me);
    push @{$me->{children}}, $x if $x;
    $x;
}

sub read_cron {
    my $cf = shift;
    my $me = shift;

    my $x = UserCron->readconfig($cf, $me);
    push @{$me->{cronjobs}}, $x if $x;
    $x;
}

sub read_meth {
    my $cf = shift;
    my $me = shift;

    my $x = NotMe->readconfig($cf, $me);
    $x;
}

sub read_resolv {
    my $cf = shift;
    my $me = shift;

    $cf->nextline();
    $cf->ungetline( "Service $_" ); # magic!

    my $x = Service->readconfig($cf, $me);
    $x;
}

sub read_sched {
    my $cf = shift;
    my $me = shift;

    my $x = Argus::Schedule->readconfig($cf, $me);
    $x;
}

sub read_mib {
    my $cf = shift;
    my $me = shift;

    my $x = Argus::SNMP::Conf->readconfig($cf, $me);
    $x;
}

sub read_darp {
    my $cf = shift;
    my $me = shift;

    if( $::HAVE_DARP ){
        my $x = DARP->readconfig($cf, $me);
        return $x;
    }
    $cf->nonfatal( "DARP not available on this system" );
    $cf->nextline();
    $cf->eat_block();
    undef;
}

sub read_master {
    my $cf = shift;
    my $me = shift;

    my $l = $cf->nextline();
    $cf->ungetline( "DARP_Slave __DARP {" );

    my($master) = $l =~ /"(.*)"/;

    my $x = Service->readconfig($cf, $me, { darp => 1, tag => $me->{name}, master => $master });
    if( $x ){
        push @{$me->{masters}},  $x;
        push @{$me->{children}}, $x;
    }
    $x;
}

sub read_slave {
    my $cf = shift;
    my $me = shift;

    my $x = DARP::Conf->readconfig($cf, $me);
    if( $x ){
        push @{$me->{slaves}},   $x;
        push @{$me->{children}}, $x;
    }
    $x;
}

################################################################

sub read_dash {
    my $cf = shift;
    my $me = shift;

    my $x = Argus::Dashboard->readconfig($cf, $me);
    $x;
}

sub read_dashrow {
    my $cf = shift;
    my $me = shift;

    my $x = Argus::Dashboard::Row->readconfig($cf, $me);
    push @{$me->{children}}, $x if $x;
    $x;
}

sub read_dashcol {
    my $cf = shift;
    my $me = shift;

    my $x = Argus::Dashboard::Col->readconfig($cf, $me);
    push @{$me->{children}}, $x if $x;
    $x;
}

sub read_dashstatus {
    my $cf = shift;
    my $me = shift;

    my $x = Argus::Dashboard::Status->readconfig($cf, $me);
    push @{$me->{children}}, $x if $x;
    $x;
}
sub read_dashoverview {
    my $cf = shift;
    my $me = shift;

    my $x = Argus::Dashboard::Overview->readconfig($cf, $me);
    push @{$me->{children}}, $x if $x;
    $x;
}
sub read_dashgraph {
    my $cf = shift;
    my $me = shift;

    my $x = Argus::Dashboard::Graph->readconfig($cf, $me);
    push @{$me->{children}}, $x if $x;
    $x;
}
sub read_dashtext {
    my $cf = shift;
    my $me = shift;

    my $x = Argus::Dashboard::Text->readconfig($cf, $me);
    push @{$me->{children}}, $x if $x;
    $x;
}
sub read_dashiframe {
    my $cf = shift;
    my $me = shift;

    my $x = Argus::Dashboard::Iframe->readconfig($cf, $me);
    push @{$me->{children}}, $x if $x;
    $x;
}


################################################################

sub mknext {
    my %n;
    @n{@_} = @_;
    return (next => \%n);
}

sub import {
    my $pkg = shift;
    my $caller = caller;

    for my $f (qw(readconfig readblock)){
        no strict;
        *{$caller . '::' . $f} = $pkg->can($f);
    }
}

1;
