# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Apr-11 23:06 (EDT)
# Function: example service test
#
# $Id: Example.pm,v 1.5 2007/01/08 05:30:05 jaw Exp $

package Example;
@ISA = qw(Service BaseIO MonEl);

$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [@ISA],
    methods => {
	# ...
    },
    fields => {
	# ...
    },
};

# used to determine if a service should be handled by us
sub probe {
    my $name = shift;

    # should return [match_size, config]
    return [7, \&config] if $name =~ /^Example/;
}

# initial configuration
sub config {
    my $me = shift;
    my $cf = shift;

    $me->init_from_config( $cf, $doc, 'example' );

    # ...
    
    bless $me, 'Example';
    $me;
}

# start the test running
sub start {
    my $me = shift;
    my( $fh, $i, $to );

    $me->debug( "Example Start: ..." );

    $me->{fd} = $fh = BaseIO::anon_fh();

    # open( $fh, ...
    $me->baseio_init();
    $me->Service::start();

    # ...

    $me->wantread(0);
    $me->wantwrit(1);
    $me->settimeout( $me->{srvc}{timeout} );
}

# test has timed out
sub timeout {
    my $me = shift;

    $me->debug( "timeout" );
    
    $me->isdown( "Example timeout" );
}

# our filehandle is writable
sub writable {
    my $me = shift;

    # ...
}

# our filehandle is readable
sub readable {
    my $me = shift;

    # ...

    if( ){
	$me->isup();
    }else{
	$me->isdown();
    }
}

################################################################
# optional methods
################################################################

# done the test
sub done {
    my $me = shift;

    $me->debug( "done" );
    $me->Service::done();	# call Service done
}


################################################################
# global config
################################################################
Doc::register( $doc );
push @Service::probes, \&probe;

1;
