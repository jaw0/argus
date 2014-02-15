# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Dec-30 23:29 (EST)
# Function: configurable objects
#
# $Id: Configable.pm,v 1.31 2012/10/12 02:17:31 jaw Exp $

package Configable;

use Argus::ReadConfig;
use strict;
use vars qw($doc);

$doc = {
    package => __PACKAGE__,
    file    => __FILE__,
    isa     => [ ],
    methods => {},
    versn   => '3.2',
    fields  =>  {
	name  => {},
	type  => {},
	quotp => {},
	subtypes => {},
	confck   => {},
	conferr  => {},
	notypos  => { descr => 'no typo complaints' },
	cftype   => {}, # for experimental param/type
	cfdepth  => {},
	confeff  => {},
    },
};

# initialize from config data according to method described in $doc
# hmmm, perhaps $doc is a poor choice of names....

my %fieldcache;
my %hasattrcache;
my @cfcache;


sub new {
    my $class = shift;
    my $x = { @_ };
    bless $x, $class;
}

sub unique {
    my $me = shift;

    my $n = "#<unknown:$me->{type}:$me->{name}>";
    $n =~ s/\s+/_/g;
    $n =~ tr/\000-\037//d;
    $n;
}

sub loggit {}

sub cfinit {
    my $me = shift;
    my $cf = shift;
    my $name = shift;
    my $type = shift;

    $me->{name} = $name;
    $me->{type} = $type;

    if( $type eq 'Host' ){
	# Host "name" => hostname: name
	$me->{config}{hostname} ||= $name;
	$me->{confck}{hostname}   = 1;	# no typo warnings
    }

    if( $cf ){
	$me->{definedinfile} ||= $cf->{file};
	$me->{definedonline} ||= $cf->{line};
    }

    $me->{definedattime} = $^T;

    if( $me->{parents} && (my $p = $me->{parents}[0]) ){
	$me->{cfdepth} = $p->{cfdepth} + 1;
    }

}

sub cfcleanup {
    my $me = shift;

    $me->rmconfeff();
}

sub mkconfeff {
    my $me   = shift;
    my $cf   = shift;

    my $ec  = {};
    my $mom = $me->{parents}[0];

    if( $mom && ! $mom->{confeff} ){
	$mom->mkconfeff($cf);
    }

    if( $mom ){
	# And he said unto him, I am the LORD that brought thee out of
	# Ur of the Chaldees, to give thee this land to inherit it.
	#     -- genesis 15:7
	for my $k (keys %{$mom->{confeff}}){
	    next if $k =~ /!$/;
	    $ec->{$k} = $mom->{confeff}{$k};
	}
    }

    # merge parent effconf + current conf
    for my $k (keys %{$me->{config}}){
	$ec->{$k} = { value => $me->{config}{$k}, src => $me, key => $k };
    }

    # pre-extend non-inherited ! params
    for my $k (keys %$ec){
	next if $k =~ /!$/;
	$ec->{"$k!"} ||= $ec->{$k};
    }

    $me->{confeff} = $ec;
}

sub rmconfeff {
    my $me   = shift;
    delete $me->{confeff};
    delete $me->{_config_location};
}

sub get_confeff_value {
    my $me = shift;
    my $k  = shift;
    my $inhp = shift;
    my $type = shift;

    my $kb = "$k!";
    my $ev = $me->{confeff}{$kb};

    # ignore inherited value if param not inheritable
    $ev = undef if $ev && !$inhp && $ev->{src} != $me;

    if( $ev ){
	# for detecting config file typos
	my $src = $ev->{src};
	my $key = $ev->{key};
	$src->{confck}{$key} = 1;
	return $ev->{value};
    }

    undef;
}

sub init_from_config {
    my $me   = shift;
    my $cf   = shift;
    my $doc  = shift;
    my $base = shift;

    $me->mkconfeff($cf) unless $me->{confeff};
    my $f = $doc->{package};

    # the profiler didn't like this, so we cache the field list,
    # cuts time in half and reduces the number of has_attr calls
    if( my $ks = $fieldcache{$f}{$base} ){
	foreach my $k ( keys %$ks ){
	    my $x = init_field_from_config_ok($me, $cf, $doc, $base, $k, $ks->{$k});
	}
    }else{
	foreach my $k (keys %{$doc->{fields}}){
	    # ignore fields that are not marked configurable
	    next unless has_attr($k, $doc, 'config');
	    my $keep = init_field_from_config($me, $cf, $doc, $base, $k);
	    next unless $keep;
	    $fieldcache{$f}{$base}{$k} = $keep;
	}
    }
}

sub init_field_from_config {
    my $me   = shift;
    my $cf   = shift;
    my $doc  = shift;
    my $base = shift;
    my $fld  = shift;
    my( $v, $kk );

    # return undef if base/key is ignored
    return if( $base && $fld !~ /::/ );
    $kk = $fld;
    $kk =~ s/^($base)::// if $base;
    return if( $kk =~ /::/ );

    return init_field_from_config_ok($me, $cf, $doc, $base, $fld, $kk );
}


sub init_field_from_config_ok {
    my $me   = shift;
    my $cf   = shift;
    my $doc  = shift;
    my $base = shift;
    my $fld  = shift;
    my $kk   = shift;
    my $v;

    # NB hasattrcache is full for this field
    my $attr = has_attr_hash($fld, $doc);

    my $type = lc($me->{cftype} || $me->{type});
    my $df   = $doc->{fields}{$fld};

    if( $attr->{acl} ){
	# skip simple fields
	return unless $doc->{fields}{$fld}{ifacl};
	$v = build_acl( $me, $doc, $kk );
    }else{
	$v = get_confeff_value($me, $kk, $attr->{inherit}, $type);
    }

    if( defined $v ){
	if( $attr->{deprecated} ){
	    my $descr = $doc->{fields}{$fld}{descr};
	    $cf->warning( "$kk is $descr" );
	}
        if( $df->{vals} && !(grep { $v eq $_ } @{$df->{vals}}) ){
            $cf->warning( "$kk has an invalid value ($v), must be [@{$df->{vals}}]" );
            $v = $df->{default};
        }
    }else{
	# if not set, is there a default
	$v = $df->{default};

	# default extended acl fields from simple field
	unless(defined $v){
	    my $fr = $df->{ifacl};
	    $v = $doc->{fields}{$fr}{default};
	}
    }

    return $kk unless defined $v;

    if( $attr->{bool} ){
	$v = ::ckbool($v);
    }

    # convert timespec
    if( $attr->{timespec} ){
	eval {
	    $v = ::timespec($v);
	};
	# QQQ - this can be quite noisy
	$cf->nonfatal("invalid timespec '$v'") if $@;
    }

    # install value
    $kk =~ s/.*\s//;	# 'foo bar' => 'bar'

    if( $base ){
	$me->{$base}{$kk} = $v;
    }else{
	$me->{$kk} = $v;
    }

    $kk;
}



# build cumulative acl - called only for extended acls
# acl = (extended || simple) + parent
sub build_acl {
    my $me    = shift;
    my $doc   = shift;
    my $field = shift;
    my( $pv, $mv, $v, %g );

    # check cache
    if( defined(my $c = $me->{aclcache}{$field}) ){
	return $c;
    }

    my $fr = $doc->{fields}{$field}{ifacl};

    # parent values, then mine
    my $mom = $me->{parents}[0];
    if( $mom ){
	$pv = build_acl($mom, $doc, $field);
    }
    $mv = $me->{config}{$field};
    $me->{confck}{$field} = 1;

    # convert simple -> extended
    if( !defined($mv) && $fr ){
	$mv = $me->{config}{$fr};
	$me->{confck}{$fr} = 1;
    }

    if( defined $pv && defined $mv ){
	$v = "$pv $mv";
    }elsif( defined $pv ){
	$v = $pv;
    }else{
	$v = $mv;
    }

    # process directives, etc
    foreach my $g (split /\s+/, $v){
	if( $g eq '-ALL' ){
	    %g = ();
	    next;
	}
	if( $g =~ /^-(.*)/ ){
	    delete $g{$1};
	    next;
	}
	$g{$g} = 1;
    }

    if( defined $v ){
	$v = join ' ', sort keys %g;
    }

    $me->{aclcache}{$field} = $v;

    $v;
}




# has_attr gets called for every field for every object (or about 500 times per object)
# at a 1000 objects, this adds up to some significant time
# memoize...

sub has_attr {
    my $field = shift;
    my $doc   = shift;
    my $attr  = shift;
    my( $v );

    my $c = $hasattrcache{ $doc->{package} }{$field};
    return $c->{$attr} if $c;

    $c = {};
    foreach my $a (@{$doc->{fields}{$field}{attrs}}){
	$c->{$a} = 1;
    }
    $hasattrcache{ $doc->{package} }{$field} = $c;

    $c->{$attr};
}

sub has_attr_hash {
    my $field = shift;
    my $doc   = shift;

    $hasattrcache{ $doc->{package} }{$field};
}

sub clearcache {
    %hasattrcache = ();
    %fieldcache   = ();
    @cfcache      = ();
}

# Error has no end.
#   -- Robert Browning, Paracelsus. Part iii.
sub check_typos {
    my $me = shift;
    my $cf = shift;

    return unless $cf;
    return if $me->{notypos};

    foreach my $k (keys %{$me->{config}}){
	next if $me->{confck}{$k};
        my $pos = $me->{_config_location}{$k};
	$cf->warning( "unused parameter '$k' - typo?", $pos );
    }
}

sub gen_conf_decl {
    my $me  = shift;
    my $doc = shift;

    $me->{type}  . ' '
    . ($doc->{conf}{quotp} ? "\"$me->{name}\"" : $me->{name});
}

# generate config tree for object - in config file format
sub gen_conf {
    my $me = shift;
    my( $r, $d );

    $d = Doc::objdocs($me);
    $r = $me->gen_conf_decl($d);

    if( $d->{conf}{bodyp} || keys %{$me->{config}} ){
	$r .= " {\n";
	$r .= "\t# this object contained config errors\n"
	    if $me->{conferrs} && !$d->{conf}{notypos};
	foreach my $k (sort keys %{$me->{config}}){
	    my $v = $me->{config}{$k};
	    next if ($k =~ /^_/) && ::topconf('_hide_expr');
            next if $k =~ / /;
	    $v =~ s/\#/\\\#/g;
	    $v =~ s/\n/\\n/g;
	    $v =~ s/\r/\\r/g;
	    $r .= "\t$k:\t$v";
	    $r .= "\t# unused parameter - typo?"
		unless $me->{confck}{$k} || $d->{conf}{notypos};
	    $r .= "\n";
	}

        # schedules
	foreach my $k (sort keys %{$me->{config}}){
            next unless $k =~ /^schedule /;
	    my $v = $me->{config}{$k};
            my $rc = $v->gen_conf();
            $rc =~ s/^/\t/gm;
            $r .= $rc;
        }

	if(exists $me->{children} || $me->{cronjobs}){
	    my $rc;
	    foreach my $c (@{$me->{cronjobs}}, @{$me->{children}}){
		$rc .= $c->gen_conf();
	    }
	    if( $rc ){
		$rc =~ s/^/\t/gm;
		$r .= "$rc";
	    }
	}
	$r .= "}";
    }

    $r .= "\n";
    $r;
}


DESTROY {
    my $me = shift;
    $me->cfcleanup();
}

################################################################
Doc::register( $doc );

1;

