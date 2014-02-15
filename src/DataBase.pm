# -*- perl -*-

# Copyright (c) 2003 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2003-Jan-30 15:27 (EST)
# Function: database testing
#
# $Id: DataBase.pm,v 1.19 2007/12/22 21:47:10 jaw Exp $

package DataBase;
@ISA = qw(Service);
use Argus::Encode;
use Socket;
use Fcntl;
use POSIX '_exit';
BEGIN{ eval{ require DBI; import DBI; $HAVE_DBI = 1; }}

use strict qw(refs vars);
use vars qw($doc @ISA $HAVE_DBI);

# And mark how well the sequel hangs together
#   -- Shakespeare, King Richard III

$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [qw(Service MonEl BaseIO)],
    methods => {},
    versn => '3.2',
    html  => 'database',
    fields => {
      db::dsn => {
	  descr => 'database dsn in DBI syntax',
	  exmpl => 'dbi:Pg:dbname=mydb;host=dbhost.example.com',
	  attrs => ['config', 'inherit'],
      },
      db::sql => {
	  descr => 'a select statement',
	  attrs => ['config', 'inherit'],
	  exmpl => "select COUNT(*) from mytable where myfield = 'value'",
      },
      db::rowfmt => {
	  descr => 'row format spec',
	  attrs => ['config', 'inherit'],
	  exmpl => '%{name} %{status} -> %{balance}',
	  versn => '3.4',
      },
      db::user => {
	  descr => 'database username',
	  attrs => ['config', 'inherit'],
      },
      db::pass => {
	  descr => 'database password',
	  attrs => ['config', 'inherit'],
      },
      db::pid => {
	  descr => 'pid of child program',
      },
      db::rbuffer => {
	  descr => 'read buffer',
      },
	
    },
};

sub probe {
    my $name = shift;

    return undef unless $HAVE_DBI;
    return [3, \&config] if $name =~ /^DB/;
}

sub config {
    my $me = shift;
    my $cf = shift;
    
    $me->init_from_config( $cf, $doc, 'db' );
    $me->{uname} = "DB_$me->{db}{dsn}";	# QQQ ?

    return $cf->error( 'dsn not specified' )
	unless $me->{db}{dsn};
    return $cf->error( 'sql select not specified' )
	unless $me->{db}{sql};
    
    bless $me if( ref($me) eq 'Service' );
    $me;
}

sub start {
    my $me = shift;
    my( $pid, $fh );
    
    $me->debug( 'start database' );
    $me->SUPER::start();
    
    $me->{fd} = $fh = BaseIO::anon_fh();
    unless( socketpair($fh, DB, AF_UNIX, SOCK_STREAM, PF_UNSPEC) ){
	my $m = "pipe failed: $!";
	::sysproblem( "DB $m" );
	$me->debug( $m );
	$me->done();
	return;
    }
    $me->baseio_init();

    $pid = fork();

    if( !defined($pid) ){
	# fork failed
	my $m = "fork failed: $!";
	::sysproblem( "DB $m" );
	$me->debug( $m );
	return $me->done();
    }
    
    unless( $pid ){
	# child
	$0 = "larry ellison";
        BaseIO::closeall();
	close STDIN;  open( STDIN,  "<&DB" );
	close STDOUT; open( STDOUT, ">&DB" );
	# let stderr go where ever argus's stderr goes
	close $fh;
	close DB;
	$| = 1;

	set_alarm( $me->{srvc}{timeout} );

        # connect to db, select, output result
	my( $db, $r );
	eval {
	    $db = DBI->connect($me->{db}{dsn}, $me->{db}{user}, $me->{db}{pass});
	};
	if( $@ ){
	    print "DBERROR: could not connect to database: $@\n";
	}elsif( ! $db ){
	    print "DBERROR: could not connect to database: $DBI::errstr\n";
	}else{
	    my $fmt = $me->{db}{rowfmt};
	    my $buf = '';
	    my $s;
	    eval {
		$s = $db->prepare($me->{db}{sql});
		$s->execute();
	    };
	    if( $@ ){
		print "DBERROR: execute failed: $@\n";
	    }elsif( ! defined $s ){
		print "DBERROR: prepare failed: $DBI::errstr\n";
	    }else{
		eval {
		    if( $fmt ){
			while( my $r = $s->fetchrow_hashref() ){
			    my $row = $fmt;
			    $row =~ s/%\{([^\}]+)\}/$r->{$1}/ge;
			    $buf .= "$row\n";
			}
		    }else{
			while( my $r = $s->fetchrow_arrayref() ){
			    $buf .= "@$r\n";
			}
		    }
		};
		if( $@ ){
		    print "DBERROR: select failed: $@\n";
		}else{
		    print $buf;
		}
	    }
	    
	    $db->disconnect;
	}
	
	_exit(-1);
    }
    close DB;
    
    Prog::register( undef, $pid );
    $me->{db}{pid} = $pid;
    $me->{db}{rbuffer} = '';
    $me->wantread(1);
    $me->wantwrit(0);
    $me->settimeout( $me->{srvc}{timeout} );
}

sub timeout {
    my $me = shift;

    $me->debug( 'timeout' );
    kill 9, $me->{db}{pid} if $me->{db}{pid};
    $me->finish();
}

sub readable {
    my $me = shift;
    my( $fh, $i, $l );

    $fh = $me->{fd};
    $i = sysread $fh, $l, 8192;
    if( $i ){
	$me->debug( "DB - read data ($l)" );
	$me->{db}{rbuffer} .= $l;
    }else{
	$me->finish();
    }
}

sub finish {
    my $me = shift;

    my $r = $me->{db}{rbuffer};
    
    if( $r =~ /^DBERROR:\s*([^:]*):/ ){
	$r = $1;
	return $me->isdown( $r, 'db error' );
    }else{
	return $me->generic_test( $r, 'DB' );
    }
}

sub set_alarm {
    my $to = shift;

    # RSN - sigaction?
    alarm($to);
}

################################################################
sub about_more {
    my $me = shift;
    my $ctl = shift;
    my( $k, $v );

    $me->SUPER::about_more($ctl);
    $me->more_about_whom($ctl, 'db');
}

sub webpage_more {
    my $me = shift;
    my $fh = shift;
    my( $k, $v );
    
    foreach $k (qw(dsn sql)){
	$v = $me->{db}{$k};
	print $fh "<TR><TD>$k</TD><TD>$v</TD></TR>\n" if defined($v);
    }
}

################################################################
Doc::register( $doc );
push @Service::probes, \&probe;

1;

