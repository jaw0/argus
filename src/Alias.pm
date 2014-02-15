# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Apr-03 08:56 (EST)
# Function: the alias pseudo-object
#
# $Id: Alias.pm,v 1.22 2012/09/30 18:27:57 jaw Exp $

# this file is for Sydney Bristow

# config: Alias "new_name" "object"

package Alias;
use Argus::Color;
@ISA = qw(MonEl);

#    And if his name be George, I'll call him Peter;
#        -- Shakespeare, King John

use strict qw(refs vars);
use vars qw(@ISA $doc);

$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [@ISA],

    methods => {
	aliaslookup => {
	    descr => 'resolve an alias',
	},
    },

    fields => {
      alias::target => {
	  attrs => ['config'],
	  descr => 'target of alias (name)',
      },
      alias::object =>{
	  descr => 'target of alias (object)',
      },
    },
};


sub config {
    my $me = shift;
    my $cf = shift;
    my $targ = shift;

    $me->{config}{target} = $targ if $targ;
    $me->init_from_config( $cf, $doc, 'alias' );

    $targ = $me->{alias}{target};

    if( !$me->{name} || !$targ ){
        $cf->nonfatal( "invalid alias spec: '$targ'" );
	return undef;
    }

    return undef unless $me->init($cf);
}


sub gen_conf {
    my $me = shift;
    my $in = shift;

    qq(Alias "$me->{name}" "$me->{alias}{target}"\n);
}

sub aliaslookup {
    my $me = shift;
    my $cf = shift;
    my( $x );

    return $me->{alias}{object} if $me->{alias}{object};
    $x = $me->{alias}{object} = $MonEl::byname{ $me->{alias}{target} };

    if( $x ){
	# short ckt straight to my parents
	push @{$x->{parents}}, $me->{parents}[0];
	return $x;
    }

    # QQQ - remove from parent? + recycle?

    if( $cf ){
	$cf->{file} = $me->{definedinfile};
	$cf->{line} = $me->{definedonline};
	$cf->error( "Cannot resolve alias: $me->{name} -> $me->{alias}{target}" );
    }else{
	# normally, the initial lookup is during the readconfig phase
	# and so will always have $cf set.
	# you are wondering, how could we ever reach here?
	# Ahhh! future feature....
    }
    undef;
}

################################################################
# override various MonEl methods
################################################################
sub web_page_row_base {
    my $me = shift;
    my $fh = shift;
    my( $x );

    $x = $me->aliaslookup();
    return $x->web_page_row_base($fh, $me->{name}) if $x;
    print $fh "<TR><TD>$me->{name}</TD><TD COLSPAN=3 BGCOLOR=\"", web_status_color('down', undef, 'back'),
    	"\"><L10N Broken Alias></TD></TR>\n";
    undef;
}

sub web_page_row_top {
    my $me = shift;
    my $fh = shift;
    my( $x );

    $x = $me->aliaslookup();
    return $x->web_page_row_top($fh, $me->{name}) if $x;
    print $fh "<TR><TD>$me->{name}</TD><TD COLSPAN=3 BGCOLOR=\"", web_status_color('down', undef, 'back'),
    	"\"><L10N Broken Alias></TD></TR>\n";
    undef;
}

sub url {
    my $me = shift;
    my $x = $me->aliaslookup();

    return $x->url(@_) if $x;
    undef;
}

sub graphlist {
    my $me = shift;

    my $x = $me->aliaslookup();
    return $x->graphlist(@_);
}

################################################################
# override various methods to do nothing
################################################################

sub loggit {}
sub webpage {}
sub jiggle {}

################################################################
Doc::register( $doc );

1;
