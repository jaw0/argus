# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Apr-03 08:56 (EST)
# Function: the group class
#
# $Id: Group.pm,v 1.53 2012/10/12 02:17:31 jaw Exp $


package Group;
use Argus::Color;
@ISA = qw(MonEl);

use strict;
use vars qw(@ISA $doc);

# And then, perchance because his breath was failing,
# He grouped himself together with a bush.
#   -- Dante, Divine Comedy

$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [@ISA],
    conf => {
	quotp => 1,
	bodyp => 1,
	subtypes => qr/Group|Host|Service|Alias|Cron/i,
    },
    methods => {
    },
    fields => {
    },
};


sub Host::new {
    shift;
    Group->new(@_);
}

sub config {
    my $me = shift;
    my $cf = shift;

    $me->init_from_config( $me, $Conf::doc, '')
      if $me->unique() eq 'Top';	# to pick up defaults for Top

    $me->init_from_config( $cf, $doc, 'group' );
    return undef unless $me->init( $cf );
}

sub cfinit {
    my $me = shift;

    $me->SUPER::cfinit(@_);
    $me->{cftype} = 'Group';
}

sub gen_conf {
    my $me = shift;
    my( $k, $c, $r, $rc, $t );

    if( $me->{i_am_top} ){
	$r .= "# various config errors were detected" .
	    ($me->{conferrs} ? ", but are not shown here" : '') . "\n"
	    if $Conf::has_errors;

	foreach my $k (sort keys %{$me->{config}}){
	    my $v = $me->{config}{$k};
	    next if ($k =~ /^_/) && ::topconf('_hide_expr');
	    $v =~ s/\#/\\\#/g;
	    $v =~ s/\n/\\n\\\n/g;
	    $r .= "$k:\t$v\n";
	}

        $r .= Argus::SNMP::Conf::gen_confs();
	$r .= Argus::Resolv::gen_confs();
        $r .= NotMe::gen_confs();
	$r .= DARP::gen_confs() if $::HAVE_DARP;
	foreach $c (@{$me->{cronjobs}}, @{$me->{children}}){
	    $r .= "\n";
	    $r .= $c->gen_conf();
	}
        $r .= Argus::Dashboard::gen_confs();
	return $r;
    }

    $r .= $me->SUPER::gen_conf();
    $r;
}

################################################################
# override MonEl virtual methods
################################################################
sub webpage {
    my $me = shift;
    my $fh = shift;
    my $topp = shift;
    my( $k, $v, $kk, $vv, %cs );

    print $fh "<!-- start of Group::webpage -->\n";

    # object data
    unless( $topp ){
	print $fh "<TABLE CELLSPACING=1 CLASS=GROUPDATA>\n";
	foreach $k (qw(name ovstatus flags info note comment annotation details)){
	    $v = $vv = $me->{$k};
	    $kk = $k;
	    if( $k eq 'ovstatus' ){
                my $c = web_status_color($v, $me->{currseverity}, 'back');
	        $kk = 'status';
	        $vv = qq(<span style="background-color: $c; padding-right: 4em;"><L10N $v></span>);
	    }
	    if( $k eq 'flags' ){
		$vv = "<L10N $v>";
	    }
	    print $fh "<TR><TD><L10N $kk></TD><TD>$vv</TD></TR>\n" if defined($v);
	    if( $k eq 'ovstatus' && $me->{depend}{culprit} ){
		# QQQ - is this really how I want to do it?
		print $fh "<TR><TD>...<L10N because></TD><TD>$me->{depend}{culprit} ",
		"<L10N is down></TD></TR>\n";
	    }

	}
	print $fh "</TABLE>\n";

	$me->web_override($fh);
	print $fh "<HR>\n";
    }

    # children status
    if( @{$me->{children}} ){
        $me->web_page_group_status( $fh, $topp );
    }
    else{
	print $fh "<!-- no children -->\n";
    }

    print $fh "<!-- end of Group::webpage -->\n";
}

sub web_page_group_status {
    my $me = shift;
    my $fh = shift;
    my $topp = shift;

    print $fh "<TABLE CLASS=GROUPCHILD>\n";
    if( $topp ){
        print $fh "<TR><TH><L10N Name></TH><TH><L10N Up></TH><TH><L10N Down></TH><TH>",
          "<L10N Override></TH></TR>\n";
        for my $c (@{$me->{children}}){
            $c->web_page_row_top($fh);
        }
    }else{
        print $fh "<TR><TH><L10N Name></TH><TH COLSPAN=3><L10N Status></TH></TR>\n";
        for my $c (@{$me->{children}}){
            $c->web_page_row_base($fh);
        }
    }
    print $fh "</TABLE>\n";
}

sub web_page_row_base {
    my $me = shift;
    my $fh = shift;
    my $label = shift;
    my( $kov, $color, $c, $s, %cs, $csv );

    return if $me->{web}{hidden};
    foreach $c (@{$me->{children}}){
	my $cc = $c->aliaslookup();
	$kov = 1 if $c->{override};
	next if $cc->{web}{hidden};

	my $st = $cc->{ovstatus};
	my $xx = '';
	if( $st !~ /^(up|down|override)$/ ){
	    $st = 'down';
	    $xx = ' <B>*</B>';
	}

	# what severity are down items?
	$csv = $cc->{currseverity} if $cc->{ovstatus} eq 'down' &&
	    $MonEl::severity_sort{$cc->{currseverity}} > $MonEl::severity_sort{$csv};

        # ... or is it too fruit salad?
        my $bkg = web_status_color($cc->{ovstatus}, $cc->{currseverity}, 'back');
	push @{$cs{ $st }},
          qq{<A HREF="} . $c->url('func=page') . qq{" style="color: #000; background-color: $bkg;">}
            . ($c->{label_right}||$c->{name}). qq{$xx</A>\n};
    }

    if( $me->{override} ){
	$color = ' BGCOLOR=' . web_status_color('override', undef, 'back');
    }
    print $fh "<TR><TD$color><A HREF=\"", $me->url('func=page'), "\">",
        ($label||$me->{label_left}||$me->{name}), "</A></TD>";

    foreach $s ('up', 'down', 'override'){
	$cs{$s} ||= [];
	my $cx = join( " &nbsp; ", @{$cs{$s}});
	if( $cx ){
	    print $fh "<TD BGCOLOR=\"", web_status_color($s, $csv, 'back'), "\">$cx</TD>\n";
	}else{
	    print $fh "<TD></TD>";
	}
    }
    print $fh "</TR>\n";
}

################################################################

Doc::register( $doc );
1;
