# -*- perl -*-

# Copyright (c) 2007 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2007-Jan-27 00:44 (EST)
# Function: archive data
#
# $Id: Argus::Archive.pm,v 1.5 2007/09/01 16:51:34 jaw Exp $

package Argus::Archive;
@ISA = qw(Argus::Archivist);

use Argus::Archivist;
use Argus::Encode;
use Socket;
use POSIX ('_exit');
use strict qw(refs vars);
use vars qw($doc @ISA);

my $DEFAULT_FMT = '%t %o %s';
my $archive;

sub new {

    # no archive unless configured
    return unless ::topconf('archive_prog');
    
    $archive = __PACKAGE__->SUPER::new(
				       name => 'Archive',
				       prog => ::topconf('archive_prog'),
				       );
}


sub write {
    my $msg = shift;

    unless( $archive ){
	new() || return;
    }

    $archive->SUPER::write( $msg );
}


# Well done is better than well said.
#   -- Benjamin Franklin 
sub done {
    my $me = shift;
    
    $me->SUPER::done();
    $archive = undef if $archive == $me;
}


################################################################

# the Power above
# With ease can save each object of his love;
#   -- Alexander Pope, The Odyssey of Homer

sub Service::archive_log_data {
    my $me  = shift;
    my $val = shift;
    my $st  = shift;

    # no archive unless configured
    return unless ::topconf('archive_prog');

    my $fmt = $me->{archive_fmt} || $DEFAULT_FMT;

    my $txt = $me->expand($fmt,
	localtime => 1,
	encode	  => \&url_encode,
    );

    Argus::Archive::write( $txt . "\n" );
}

1;

