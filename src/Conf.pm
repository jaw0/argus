# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Apr-03 09:13 (EST)
# Function: config file reading
#
# $Id: Conf.pm,v 1.74 2012/12/02 04:32:57 jaw Exp $

# some bozo put a Config.pm in the standard perl dist
package Conf;
use Argus::ReadConfig;
use strict;
use vars qw($doc $has_errors);

$has_errors = 0;	# if we found errors, the web page will indicate such (global)
my @allfiles = ();	# all of the config files
my $timestamp = 0;	# time we last read the config files


$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [ ],
    methods => {},
    conf    => {},
    fields  =>  {

	chmod_control => {
	    descr => 'control socket permissions (in octal)',
	    attrs => ['config', 'top'],
	    exmpl => '777',
	    versn => '3.1.3',
	},
	syslog => {
	    descr => 'syslog facility to use for sysloging if desired',
	    attrs => ['config', 'top'],
	    exmpl => 'daemon',
	    html  => 'troubleshooting',
	    callback => \&::try_openlog,
	},
	runatstartup => {
	    descr => 'external program to run at startup',
	    attrs => ['config', 'top'],
	    versn => '3.2',
	    html  => 'interfacing',
	},
	load_modules => {
	    descr => 'list of additional perl modules to load',
	    attrs => ['config', 'top'],
	    versn => '3.3',
	    html  => 'interfacing',
	},
	lang => {
	    descr => 'override default language',
	    attrs => ['config', 'top'],
	    versn => '3.3',
	    html  => 'l10n',
	},
	test_port => {
	    descr => 'run a test server on the specified TCP port',
	    attrs => ['config', 'top'],
	    versn => '3.3',
	    exmpl => '3074',
	    html  => 'testport',
	    callback => sub { TestPort->Server::new_inet(shift) },
	},
	graphd_prog => {
	    descr => 'pathname of graphd program',
	    attrs => ['config', 'top'],
	    versn => '3.3',
	},
	picasso_prog => {
	    descr => 'pathname of picasso program',
	    attrs => ['config', 'top'],
	    versn => '3.3',
	},
        darp_graph_location => {
            descr => 'where is graph data kept?',
            attrs => ['config', 'top'],
            versn => '3.7',
            vals  => ['master', 'slave'],
            default => 'slave',
        },

	archive_prog => {
	    descr => 'pathname of archive program',
	    attrs => ['config', 'top'],
	    versn => '3.5',
	    html  => 'interfacing',
	},

	mibfile => {
	    descr => 'pathname of SNMP MIB translation file (MIB2SCHEMA format)',
	    attrs => ['config', 'top', 'multi'],
	    versn => '3.5',
	    callback => \&Argus::SNMP::load_mibfile,
	},

        resolv_autoconf => {
            descr => 'autoconfigure resolver',
	    attrs => ['config', 'top', 'bool'],
            versn => '3.7',
            default => 'yes',	# NB: informational, default not used
            callback => \&Argus::Resolv::IP::autoconf,
        },
	resolv_timeout => {
	    descr => 'timeout for resolver lookups',
	    attrs => ['config', 'top', 'timespec'],
	    versn => '3.5',
	},
	snmp_helper_frequency => {
	    descr => 'how often the should the snmp helper be started, if needed',
	    attrs => ['config', 'top', 'timespec'],
	    versn => '3.6',
	},
	snmp_helper_timeout => {
	    descr => 'how long to wait for an snmp helper response before giving up',
	    attrs => ['config', 'top', 'timespec'],
	    versn => '3.6',
	},

	max_descriptors => {
	    descr => 'maximum number of file descriptors available for use (see: ulimit)',
	    attrs => ['config', 'top'],
	    default => ($^O eq 'solaris' ? 240 : undef),
	    versn => '3.6',
	},

        # QQQ - do we need to support per-object ticket systems?
        tkt_view_url => {
            descr => 'URL to view a trouble ticket',
	    attrs => ['config', 'top'],
            exmpl => 'http://trouble.example.com/view?t=TICKET',
            versn => '3.7',
            html  => 'tktsys',
        },
        tkt_check_url => {
            descr => 'URL to check the status of a trouble ticket',
	    attrs => ['config', 'top'],
            exmpl => 'http://trouble.example.com/view?t=TICKET',
            versn => '3.7',
            html  => 'tktsys',
        },
        tkt_check_expect => {
            descr => 'expected value if ticket is open',
	    attrs => ['config', 'top'],
            exmpl => 'status: active',
            versn => '3.7',
            html  => 'tktsys',
        },

################################################################
# experimental, undocumented features - for author's use only
################################################################
	_no_addtnl => { attrs => ['config', 'top'] },	# suppress additional data on Top/about
	_save_less => { attrs => ['config', 'top'] },	# delay commit of Stats files
	_ctl_debug => { attrs => ['config', 'top'] },	# control channel debugging
	_hide_expr => { attrs => ['config', 'top'] },	# supress experimental items from display config
	_hide_comm => { attrs => ['config', 'top'] },	# supress community from display config
	_dont_ntfy => { attrs => ['config', 'top'] },	# notifications are not sent
	_no_images => { attrs => ['config', 'top'] },	# do not display graph images
	_test_mode => { attrs => ['config', 'top'] },	# do not access datadir
    }
};


# read the config file(s)
sub readconfigfiles {
    my $file = shift;
    my $me = {};
    my( @files );

    bless $me;
    $timestamp = $^T;
    $Service::n_services = 0;		      # this really doesn't belong here, but...
    # one file or directory of files?
    if( -d $file && -r _ && -x _ ){
	$me->{basedir} = $file;		      # includes will be relative to config dir
	opendir D, $file;
	@files =
	  grep { ! /^CVS/ }		      # skip CVS
	  grep { !/^[\.\#]/ }		      # skip .file and #file
	  grep { !/(\.bkp|~)$/ } readdir D;   # and file.bkp and file~
	closedir D;
    }else{
	@files = ($file);
    }

    $me->{files} = [sort @files];
    $me->{openfiles} = [];

    $me->configure();

}

sub configure {
    my $me = shift;
    my( $top, $o, $nomoredata, $nomorespec, @kids );

    $::Top = $top = Group->new();
    $top->{i_am_top} = 1;	# used only to pretty print the config
    $top->cfinit($me, 'Top', 'Group');
    $top->{cfdepth} = 0;
    # $top->{notypos} = 1;
    $top->{_test_mode} = 1 if $::opt_t || $::datadir eq '__' . 'DATADIR' . '__';

    eval {
        readblock( $top, $me, 'top', 0, $doc );
        $top->config($me);
    };
    if( $@ ){
        # QQQ
        die $@ if $@ != $me;
    }

    return if $::opt_t;
    $top->clearcache();        # reclaim memory used by hasattr cache
    eval {
	$top->resolve_alii($me);
    };
    eval {
	$top->resolve_depends($me);
    };
    $top->jiggle_lightly();	# update object statuses
    $top->{sort} = 0;     	# top is not sorted
    $top->{overridable} = 0;
    $top->sort_children();

    $top;
}

sub eat_block {
    my $me = shift;
    my $n  = shift;

    while( defined( $_ = $me->nextline() ) ){
	print STDERR "  ignoring $n: $_\n" if $::opt_d;
	last if /^\s*\}/;
	$me->eat_block($n+1) if /\{\s*$/;
    }
}

sub nonfatal {
    my $me = shift;
    my $msg = shift;
    my( $m );

    $has_errors ++;
    $m = "ERROR: ";
    if( $me->{file} ){
	$m .= "in file '$me->{file}' on line $me->{line} - ";
    }
    $m .= $msg;
    ::loggit( $m, 1 );

    undef;
}

sub error {
    my $me = shift;
    my $msg = shift;

    $me->nonfatal($msg);
    die $me;
}

sub warning {
    my $me  = shift;
    my $msg = shift;
    my $pos = shift;
    my( $m );

    $has_errors ++ if ::topconf('_test_mode');

    $m = "WARNING: ";

    if( $pos && $pos->{file} ){
	$m .= "in file '$pos->{file}' on line $pos->{line} - ";
    }
    elsif( $me->{file} ){
	$m .= "in file '$me->{file}' on line $me->{line} - ";
    }
    $m .= $msg;
    ::loggit( $m, 1 );
    undef;
}

sub currpos {
    my $me = shift;

    return {
        file	=> $me->{file},
        line	=> $me->{line},
    };
}

sub openfile {
    my $me = shift;
    my $f  = shift;
    my( $ff, $fh );

    $me->{fd} = $fh = BaseIO::anon_fh();
    $me->{file} = undef;
    $me->{line} = undef;

    print STDERR "reading config file: $f\n" if $::opt_d;
    eval {
	if( $me->{basedir} && $f !~ m,^/, ){
	    $ff = "$me->{basedir}/$f";
	}else{
	    $ff = $f;
	}
	open( $fh, $ff ) ||
	    $me->error( "'$ff' is stubborn and refuses to open: $!" );
    };
    return undef if $@;

    # handle #!
    my $l = <$fh>;
    chop $l;
    if( $l =~ /^\#!\s*(.*)/ ){
	my $prog = $1;
	close $fh;

	print STDERR "reading config program: $prog $ff\n" if $::opt_d;
	eval {
	    open( $fh, "$prog $ff |" ) ||
		$me->error( "'$prog $ff' is stubborn and refuses to run: $!" );
	};
	return undef if $@;
	$me->{line} = 0;
    }else{
	$me->ungetline($l);
	$me->{line} = 1;
    }

    push @allfiles, $ff;
    $me->{file} = $f;

    1;
}

sub includefile {
    my $me = shift;
    my $file = shift;

    push @{$me->{openfiles}}, [$me->{fd}, $me->{file}, $me->{line}];
    $me->openfile( $file ) || $me->nextfile();
}

sub nextfile {
    my $me = shift;
    my( $f, $fh );
    $fh = $me->{fd};

    close $fh if $fh;
    delete $me->{fd};

    if( @{$me->{openfiles}} ){
	($me->{fd}, $me->{file}, $me->{line}) = @{ pop @{$me->{openfiles}} };
	return 1;
    }

    while(1){
	$f = shift @{$me->{files}};
	return undef unless $f;
	print STDERR "next file: $f\n" if $::opt_d;
	next unless $me->openfile( $f );
	return 1;
    }
}

sub nextline {
    my $me = shift;
    my( $fh, $a );

    $a = '';
    while(1){

	while( 1 ){
	    $fh = $me->{fd};
	    if( defined($_ = $me->{prevline}) ){
		delete $me->{prevline};
	    }elsif( $fh ){
		$_ = <$fh>;
		$me->{line} ++;
	    }else{
		$_ = undef;
	    }
	    last unless defined $_;

	    chomp;
	    # need to be able to include a literal # in the config
	    # by saying \# and below convert \# -> #
	    s/\s*(?<!\\)\#.*$//;
	    s/^\s+//;
	    s/\s+$//;
	    next if /^\s*$/;
	    s/\\&//g;
	    s/\\n/\n/g;
	    s/\\r/\r/g;
	    s/\\x([0-9a-fA-F]{2})/chr(hex($1))/eg;
	    s/\\\#/\#/g;
	    # no, I don't want to s/\\(.)/$1/
	    # it will mess up regexes

	    # handle include files
	    if( /^include \"(.*)\"/i ){
		$me->includefile( $1 );
		$fh = $me->{fd};
		next;
	    }

	    $a .= $_;
	    if( $a =~ /\\$/ ){
		chop $a;
		next;
	    }
	    return $a;
	}
	$me->nextfile() || return undef;
    }
}

sub ungetline {
    my $me = shift;
    my $line = shift;

    $me->{prevline} = $line;
}

sub check_config_files {
    foreach my $f (@allfiles){
	my $t = (stat($f))[9];
	if( $t > $timestamp ){
	    # the file changed--restart
	    ::loggit( "config file '$f' changed - restarting", 1 );
	    kill 'HUP', $$;
	    last;
	}
    }
}

sub deconfigure {
    $::Top = undef;
}

################################################################

sub cmd_clrerrs {
    my $ctl   = shift;
    my $param = shift;

    $has_errors = 0;
    $ctl->ok_n();
}

################################################################
# for testing - config from filehandle

sub testconfig {
    my $fd = shift;

    my $cf = bless {};
    $cf->{openfiles} = [ [ $fd, 'data', 1 ] ];

    $cf->configure();
}

################################################################
Doc::register( $doc );
################################################################
Control::command_install( 'clear_error_flag',   \&cmd_clrerrs,   "clear errors flag" );
################################################################

# check for changes in config files every 5 minutes
Cron->new(
	  freq => 300,
	  text => 'check config files',
	  func => \&check_config_files,
	  );

1;

