# -*- perl -*-
# Function: test TCP, Server, and Control

#$opt_f = 1;

print "1..2\n";
require "t/libs.pl";

my $top = Conf::testconfig( \*DATA );
Control->Server::new_inet( 54321 );
Banner ->Server::new_inet( 54322 );

my $o = $MonEl::byname{'Top:G1:S1'};
$o->start();
while( ! $o->{srvc}{finished} ){
    BaseIO::oneloop( maxperiod => 10 );
}
t( $o->{status} eq 'up' );

$o = $MonEl::byname{'Top:G1:S2'};
$o->start();
while( ! $o->{srvc}{finished} ){
    BaseIO::oneloop( maxperiod => 10 );
}
t( $o->{status} eq 'up' );


exit 0;

################################################################
package Banner;

sub new {
    my $class = shift;
    my $fh    = shift;

    syswrite $fh, "Banner 200 OK\n";
    undef;
}


################################################################

__END__
    
    _test_mode: 1
    retries: 	0
    debug: yes
    
    Group "G1" {
        hostname: 127.0.0.1
	Service TCP {
	    uname: S1
	    port:  54321
	    send:  GET / ARGUS/2.0\nfunc: echo\nfoo: bar\n\n
	    readhow: banner
	    expect:  200 OK
	}
        Service TCP {
	    uname: S2
	    port:  54322
	    expect: Banner 200 OK
	    readhow: banner
	}
	      
    }

