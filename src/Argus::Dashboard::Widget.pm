# -*- perl -*-

# Copyright (c) 2012
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2012-Sep-15 12:45 (EDT)
# Function: custom dashboards
#
# $Id: Argus::Dashboard::Widget.pm,v 1.4 2012/10/13 18:36:12 jaw Exp $

package Argus::Dashboard::Widget;
@ISA = qw(Configable Argus::Dashboard);
use vars qw(@ISA $doc);
use Argus::Dashboard::Status;
use Argus::Dashboard::Overview;
use Argus::Dashboard::Graph;
use Argus::Dashboard::Iframe;
use Argus::Dashboard::Text;
use strict;

my @param = qw(colspan rowspan heading caption width height style cssid cssclass);
$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [],
    versn => '3.7',
    html  => 'dashboard',
    methods => {},
    conf => {
	quotp => 1,
	bodyp => 1,
    },
    fields => {
        map {
            ($_ => {
                descr => 'dashboard layout parameter',
                attrs => ['config'],
            })
        } @param,
    },
};

# overview down|unacked|override [topN]
# status [top] "GROUP"
# status { OBJECT ... }
# graph samples|hours|days  large|thumb  "OBJECT"
# graph samples|hours|days  large|thumb { SERVICE ... }
# iframe "url"
# text "html"
# text { html }

sub readconfig {
    my $class = shift;
    my $cf    = shift;
    my $mom   = shift;

    my $line = $cf->nextline();

    my($type) = $line =~ /\s*(\S+)\s+/;

    my $me = $class->new();
    $me->{parents} = [ $mom ] if $mom;
    $me->cfinit($cf, '', "\u\L$type");

    my @kids;

    if( $line =~ /{\s*$/ ){
        while( defined($_ = $cf->nextline()) ){
            if( /^\s*\}/ ){
                last;
            }

            if( /^\s*\+\s+(.*)/ ){
                push @kids, $1;
            }
            elsif( /:/ ){
                my($k, $v) = split /:[ \t]*/, $_, 2;

                if( $doc && Configable::has_attr($k, $doc, 'multi') ){
                    push @{$me->{config}{$k}}, $v;	# QQQ
                }else{
                    $cf->warning( "redefinition of parameter '$k'" )
                      if $me->{config}{$k};
                    $me->{config}{$k} = $v;
                    $me->{_config_location}{$k} = $cf->currpos();
                }
            }
            else{
                # Reading what they never wrote
                #   -- William Cowper, The Task
                $cf->nonfatal( "invalid entry in config file: '$_'" );
                $me->{conferrs} ++;
            }
        }
    }

    $me->{list} = \@kids;
    $me->cf_widget($cf, $line);
    $me->config($cf, $mom);

    $line =~ s/\s*\{\s*//;
    $line =~ s/\s*".*"\s*//;
    $me->{confline} = $line;

    return $me;
}



sub config {
    my $me = shift;
    my $cf = shift;
    my $more = shift;

    $me->init_from_config( $cf, $doc, '' );
    $me->check($cf);
    $me;
}

sub web_make {
    my $me = shift;
    my $fh = shift;

    my $attr = $me->attr(qw(rowspan colspan width height style));
    my $heading = $me->expand( $me->{heading} );

    print $fh "<TD$attr valign=top>";
    print $fh "<center><b class=dashtitle>$heading</b></center>\n" if $me->{heading};

    $me->web_make_widget($fh);

    print $fh "</TD>\n";
}

sub web_make_widget {
    my $me = shift;
    my $fh = shift;

    print $fh "$me->{type}\n";

}

sub gen_conf {
    my $me = shift;

    my $r = $me->{confline};
    $r .= qq{ "$me->{list}"} if $me->{list} && !ref $me->{list};
    $r .= " {\n";

    $r .= "\t# this object contained config errors\n" if $me->{conferrs};
    for my $k (sort keys %{$me->{config}}){
        my $v = $me->{config}{$k};
        next if ($k =~ /^_/) && ::topconf('_hide_expr');
        next if $k =~ / /;
        $v =~ s/\#/\\\#/g;
        $v =~ s/\n/\\n/g;
        $v =~ s/\r/\\r/g;
        $r .= "\t$k:\t$v";
        $r .= "\t# unused parameter - typo?"
          unless $me->{confck}{$k};
        $r .= "\n";
    }

    if( $me->{list} && ref $me->{list} ){
        for my $c (@{$me->{list}}){
            $r .= "\t+ $c\n";
        }
    }

    $r .= "}\n";
}

################################################################
Doc::register( $doc );

1;
