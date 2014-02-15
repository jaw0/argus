# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Apr-02 13:23 (EST)
# Function: the control channel
#
# $Id: Control.pm,v 1.33 2007/09/01 16:51:36 jaw Exp $

package Control;
use Argus::Encode;
use NullCtl;
@ISA = qw(BaseIO Server);

# Automedon son of Diores answered, "Alcimedon, there is no one else
# who can control and guide the immortal steeds so well as you can,
# save only Patroclus- while he was alive- peer of gods in counsel.
#   -- Homer, Iliad

$PROTOVER = "2.0";		# protocol version
$IDWORD = "ARGUS/$PROTOVER";	# id field used in protocol
$CTL_TO = 120;

@consoles = ();			# list of all consoles

$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [@ISA],
    methods => {
    },
    fields => {
      control::srcaddr => { descr => 'source address of connection', },
      control::wbuffer => { descr => 'write buffer' },
      control::rbuffer => { descr => 'read buffer'  },
      control::closeme => { descr => 'connection is being closed' },
      control::curseq  => { descr => 'current sequence number' },
      control::authok  => { descr => 'connection is permitted' },
      control::timeout => { descr => 'timeout' },
    },
};

# command    => \&func,
%cmd_table = ();
%cmd_docs  = ();  # {descr, param}


# Grammar, which knows how to control even kings.
#        -- Les Femmes savantes. Act ii. Sc. 6.
#           Jean Baptiste Poquelin Moliere.

# protocol is looks roughly like http
#
# Protocol:
#    connect
#    client - send request
#    server - send response
#    repeat...
#
# request:
#    request type and version...: GET REQUEST Argus/2.0
#    param: value\n
#    param: value\n
#    ...
#    blank line\n
#
#    value is xxx_encoded
#    currently request is only GET; type is unused
#
#    example:
#	GET / ARGUS/2.0
#	func: echo
#	foobar: 123
#	<blank line>

# response:
#    word number text\n
#    optional data\n
#    ...
#    blank line\n
#
# status numbers:
# 2?? - OK
# anything else - error
#
#    example:
#	ARGUS/2.0 200 OK
#	foobar: 123
#	<blank line>


sub new {
    my $class = shift;
    my $fh    = shift;
    my $addr  = shift;
    my $me = {};
    bless $me, $class;

    $me->{fd} = $fh;
    $me->{control}{srcaddr} = $addr;
    $me->{type} = "Control";
    $me->{control}{timeout} = $CTL_TO;
    if( $me->can('connection_policy') ){
	$me->{control}{authok} = $me->connection_policy( $addr );
    }else{
	$me->{control}{authok} = 1;
    }
    
    $me->debug( "new connection" );
    
    $me->wantread(1);
    $me->wantwrit(0);
    $me->settimeout(0);
    $me->baseio_init();

    $me; 
}

sub unique {
    my $me = shift;

    "Connection from ". $me->{control}{srcaddr};
}

sub readable {
    my $me = shift;
    my $fh = $me->{fd};
    my( $i, $l );
    
    $i = sysread $fh, $l, 8192;
    if( $i ){
	$me->debug( "read $i bytes" );
	$l =~ tr/\r//d;
	$me->{control}{rbuffer} .= $l;

	while( $me->{control}{rbuffer} =~ /\n\n/s ){
	    my($a, $b) = $me->{control}{rbuffer} =~ /^(.*?)\n\n(.*)$/s;
	    $me->{control}{rbuffer} = $b;
	    if( $a =~ /^GET\s/i ){
		$me->command( $a );
	    }elsif( $me->can('response') ){
		$me->response( $a );
	    }else{
		$me->{control}{closeme} = 1;
		$me->bummer(405, 'Invalid Request');
	    }
	}
    }else{
	if( defined($i) ){
	    $me->debug( "read eof" );
	}else{
	    $me->debug( "read failed: $!" );
	}
	if( $me->{wantwrit} ){
	    $me->{control}{closeme} = 1;
	}else{
	    $me->done();
	}
    }
}

sub writable {
    my $me = shift;
    my $fh = $me->{fd};
    
    if( $me->{control}{wbuffer} ){
	my( $i, $l );
	
	$l = length($me->{control}{wbuffer});
	$i = syswrite $fh, $me->{control}{wbuffer}, $l;
	if( ! $i ){
	    if( defined($i) ){
		$me->debug( "write 0 bytes?" );
	    }else{
		$me->debug( "write failed: $!" );
	    }
	    $me->done();
	    return;
	}else{
	    $me->{control}{wbuffer} = substr($me->{control}{wbuffer}, $i, $l );
	    $me->debug( "wrote $i bytes" );
	}
    }

    if( $me->{control}{wbuffer} ){
	$me->settimeout( $me->{control}{timeout} || $CTL_TO );
	$me->wantwrit(1);
    }else{
	# Stop close their mouths, let them not speak a word.
	#   -- Shakespeare, Titus Andronicus
	$me->settimeout(0);
	$me->wantwrit(0);
	$me->wantread(1);
	if( $me->{control}{closeme} ){
	    $me->debug( "closeme" );
	    $me->done();
	}
    }
}

sub timeout {
    my $me = shift;

    $me->debug( "timeout" );
    $me->done();
}

sub write {
    my $me = shift;
    my $msg = shift;
    
    $me->{control}{wbuffer} .= $msg;
    $me->wantwrit(1);
    # $me->wantread(0);
    $me->settimeout( $me->{control}{timeout} || $CTL_TO );
}

sub done {
    my $me = shift;

    $me->debug( "done" );
    @consoles = grep { $_ != $me } @consoles;
    $me->shutdown();
}

sub command {
    my $me = shift;
    my $msg = shift;
    my( $k, $v, $f, $authok, @lines, %data );

    @lines = split /\n/, $msg;
    if( $lines[0] =~ /^[^:\s]+\s/ ){
	$k = shift @lines;
	if( $k !~ /$PROTOVER/ ){
	    return $me->bummer( 505, 'version not supported' );
	}
    }
    foreach (@lines){
	s/\s*$//;
	s/^\s*//;
	($k, $v) = split /\s*:\s+/, $_, 2;
	$data{lc($k)} = decode($v) if $k;
    }
    $me->{control}{curseq} = $data{seqno};
    $authok = $me->authrzd_func( \%data );
    
    if( $me->can( 'function_policy' ) ){
	$authok &&= $me->function_policy( \%data );
    }else{
	$authok &&= 1;
    }
    
    if( $authok && ($me->{control}{authok} || $data{func} eq 'auth') ){
	$f = $cmd_table{ $data{func} };
	$me->debug( "command $data{func}" );
	if( $f ){
	    $f->( $me, \%data );
	}else{
	    $me->debug( "invalid command" );
	    $me->bummer(404, 'Not Found');
	}
    }else{
	$me->{control}{closeme} = 1;
	$me->bummer(401, 'Unauthorized');
	::loggit( "Unauthorized command attempted from $me->{control}{srcaddr} '$data{func}'" );
	# foreach my $k (keys %data){
	#     print STDERR " x $k => $data{$k}\n";
	# }
    }
}

sub authrzd_func { 1 }
    
# end user friendly interface
sub func {
    my $func  = shift;
    my %param = @_;

    my $ctl = NullCtl->new();
    my $f = $cmd_table{ $func };

    # print STDERR "func: $func; @_\n";
    
    if( $f ){
	$f->( $ctl, \%param );

	if( $ctl->{error} ){
	    ::loggit( "control function '$func': $ctl->{error}", 1 );
	}
    }else{
	::loggit( "invalid control function '$func'", 1 );
    }
}

sub send_answer {
    my $me = shift;
    my $code = shift;
    my $msg = shift;

    $me->write("$IDWORD $code $msg\n");
    $me->write("seqno: $me->{control}{curseq}\n") if $me->{control}{curseq};
}

sub ok {
    my $me = shift;
    $me->send_answer( 200, 'OK' );
}

sub ok_n {
    my $me = shift;

    $me->ok();
    $me->final();
}

sub final {
    my $me = shift;

    $me->write("\n");
}

sub bummer {
    my $me = shift;
    my $code = shift;
    my $msg = shift;

    $me->send_answer($code, $msg);
    $me->final();
}

sub command_install {
    my $cmd = shift;
    my $fnc = shift;
    my $descr = shift;
    my $param = shift;

    $cmd_table{$cmd} = $fnc;
    $cmd_docs{$cmd} = {
	descr => $descr,
	param => $param,
    };
}

# used by logging code--send messages to clients that have requested them
# eg. use argusctl -k console
sub console {
    my $msg = shift;
    my( $x );

    foreach $x (@consoles){
	$x->write( "$msg\n" ) if $x;
    }
}

sub debug {
    my $me = shift;
    my $msg = shift;
    my( $n, $f );

    $f = fileno( $me->{fd} );
    $n = $me->{name} || $me->{type};
    
    return unless $me->{debug} || ::topconf('debug') || ::topconf('_ctl_debug');
    ::loggit( "DEBUG - $n [$f] $msg" );

}

################################################################
# class global init
################################################################
Doc::register( $doc );

1;


