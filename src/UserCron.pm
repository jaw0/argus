# -*- perl -*-

# Copyright (c) 2003 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2003-Sep-12 18:30 (EDT)
# Function: run things at a specified time
#
# $Id: UserCron.pm,v 1.10 2010/01/10 22:23:21 jaw Exp $

# replacement for using a system cronjob to run argusctl

package UserCron;
@ISA = qw(BaseIO Configable);

use strict;
use vars qw(@ISA $doc);

$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [ ],
    methods => {},
    versn   => '3.3',
    html    => 'cron',
    conf => {
	quotp => 1,
	bodyp => 1,
	notypos => 1,
    },
    fields  =>  {

    },
};

sub config {
    my $me = shift;

    # $me->init_from_config($cf, $doc, '');

    Cron->new( spec => $me->{name},
	       text => 'user cron job',
	       func => \&cronjob,
	       args => $me,
	       );

    $me->cfcleanup();
    $me;
}


# And the LORD said unto Satan, Hast thou considered my servant Job
#   -- Job 1:8
sub cronjob {
    my $me = shift;

    # run argusctl function
    Control::func( $me->{config}{func},
		   ($me->{parents} ? (object => $me->{parents}[0]->unique()) : ()),
		   user => '*internal-cronjob*',
		   %{$me->{config}} );
}


################################################################
Doc::register( $doc );

1;
