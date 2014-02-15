# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Apr-04 14:38 (EST)
# Function: handle documentation
#
# $Id: Doc.pm,v 1.26 2008/10/25 15:31:47 jaw Exp $

# maintain and validate internal documentation
# export it if requested

package Doc;
#use DebugOMatic;

use strict;

my %docbypkg = ();

sub register {
    my $doc = shift;
    my( $pkg );

    $pkg = $doc->{package};
    ::warning( "required doc entry 'package' missing!" ) unless $pkg;
    ::warning( "duplicate doc entry for '$pkg'" ) if $docbypkg{$pkg};
    $docbypkg{$pkg} = $doc;
}

sub check_all {
    my( $p, $f, $d, $b, %need );

    foreach $p (keys %docbypkg){
        $d = $docbypkg{$p};
	
	foreach $f (qw(fields methods package file isa)){
	    unless( defined($d->{$f}) ){
		::warning( "required doc entry '$f' missing for '$p'" )
	    }
	}

        foreach $b ( @{$d->{isa}} ){
            $need{$b} = $p;
        }
    }

    foreach $p (keys %need){
        unless( $docbypkg{$p} ){
            ::warning( "Documentation missing for Class '$p' - required for '$need{$p}'" );
        }
    }
}


sub fill_isa {
    my $pkg = shift;
    my %isa;
    my @isa;

    @isa = @{$docbypkg{$pkg}{isa}};

    while(@isa){
	my $i = shift @isa;
	unless( $isa{$i} ){
	    $isa{$i} = 1;
	    # recursively
	    push @isa, @{$docbypkg{$i}{isa}};
	}
    }
    
    @{$docbypkg{$pkg}{isall}} = keys %isa;
}


sub doc_for {
    my $pkg = shift;
    my $typ = shift;
    my $fld = shift;
    my( $b );
    
    return $docbypkg{$pkg}{$typ}{$fld}
        if $docbypkg{$pkg}{$typ}{$fld};

    # check base classes
    fill_isa($pkg) unless $docbypkg{$pkg}{isall};
    
    foreach $b ( @{$docbypkg{$pkg}{isall}} ){
        return $docbypkg{$b}{$typ}{$fld}
            if $docbypkg{$b}{$typ}{$fld};
    }
    return undef;
}

sub objdocs {
    my $obj = shift;
    my( $p );

    $p = ref $obj;
    $docbypkg{$p};
}

# check an object
sub check {
    my $obj = shift;
    my( $p, $d, $f );

    $p = ref($obj);

    # check (some) fields
    foreach $f (keys %$obj){
        next if ref($obj->{$f}) eq "HASH";
	unless( doc_for($p, 'fields', $f) ){
	    print STDERR "check failed for $p/$f\n";
	    print STDERR "obj: ", $obj->unique(), "\n" if $obj->can('unique');
	    # exit;
	}
    }

    return 1;
    
}

################################################################
# generate documentation
################################################################

# quick rough wack
sub normalize_version {
    my $ver = shift;

    return unless $ver;
    
    if( $ver =~ /^(\d+)\.(\d+).*/ ){
	# A.B.C => A.B
	return "$1.$2";
    }

    if( $ver =~ /dev-(\d+)/ ){
	my $date = $1;

	return '3.6' if $date ge '20081027';
	return '3.5' if $date ge '20070614';
	return '3.4' if $date ge '20050514';
	return '3.3' if $date ge '20040323';
	return '3.2' if $date ge '20030414';
	return '3.1' if $date ge '20021020';
	return '3.0' if $date ge '20010101';
    }

    die "unknown version: $ver\n";
}

sub describe_config {
    describe_docs( $_[0], 0, $_[1] );
}

sub describe_internal {
    describe_docs( $_[0], 1, $_[1] );
}

sub describe_docs {
    my $html  = shift;
    my $all   = shift;
    my $since = shift;
    my( $p, $f, $d, $e, $k, $kk, $base, $px );

    $since = normalize_version($since);
    
    if( $html ){
	my $st = $since ? " Since $since" : '';
	print "<HTML><HEAD></HEAD><BODY BGCOLOR=\"#FFFFFF\">\n<TABLE BORDER=1>\n";
	if( $all ){
	    print "<H1>Auto-Generated Documentation - Detailed Params$st</H1>\n";
	}else{
	    print "<H1>Auto-Generated Documentation - Config Params$st</H1>\n";
	}
    }
    
    foreach $p (sort keys %docbypkg){
	$d = $docbypkg{$p};
	$f = $d->{file};
	foreach $k (sort keys %{$d->{fields}}){
	    next unless $all || Configable::has_attr( $k, $d, 'config' );
	    $kk = $k;
	    ($base) = $k =~ /(.*)::/;
	    $kk =~ s/^.*::// unless $all;
	    $e = $d->{fields}{$k};
	    my( $descr, $def, $ver, $exmpl, $link, @attr, @vals );

	    next if $kk =~ /^_/;
	    $descr = $e->{descr}   || 'undocumented';
	    $def   = $e->{default};
	    $ver   = $e->{versn} || $d->{versn};
	    next if $since && $ver <= $since;
	    $exmpl = $e->{exmpl};
	    $link  = $e->{html}  || $d->{html};
	    @attr  = @{$e->{attrs}} if $e->{attrs};
	    @vals  = @{$e->{vals}}  if $e->{vals};
	    @attr  = grep { !/config/ } @attr unless $all;
	    foreach (@attr) { s/nyi/not-currently-implemented/ };
	    
	    $px = $p;
	    # A E I O U and some times Y
	    #   -- Ebn Ozn
	    $px =~ tr/aeiouy//d;
	    $base = '' if( lc($px) eq $base || lc($p) eq $base );
	    $base = " ($base)" if $base;
	    
	    if( $html ){
		print "<TR><TD><B><A NAME=\"$kk\">$kk</A></B></TD><TD>$descr";
		print "<BR><B>attr:</B> @attr" if @attr;
		print "<BR><B>vals:</B> @vals" if @vals;
		print "<BR><B>default:</B> $def" if $def;
		print "<BR><B>for example:</B> $exmpl" if $exmpl;
		print "<BR><B>used in:</B> $p$base";
		print "&nbsp;&nbsp;<B>see also:</B> <A HREF=\"$link.html\">$link docs</A>" if $link;
		print "<BR><I>this feature is new or changed in version <B>$ver</B></I>" if $ver;
		print "</TD></TR>\n";
	    }else{
		print "$kk\t$descr\n";
		print "\t\tattr: @attr\n" if @attr;
		print "\t\tvals: @vals\n" if @vals;
		print "\t\tdefault: $def\n" if $def;
		print "\t\tfor example: $exmpl\n" if $exmpl;
		print "\t\tused in: $p$base\n";
		print "\t\tthis feature is new or changed in version $ver\n" if $ver;
		print "\n";
	    }
	}
    }
    if( $html ){
	print "</TABLE>\n";
	print "<BR><FONT SIZE=-1>Generated by <A HREF=\"http://argus.tcp4me.com\">Argus</A> ",
		"Version: $::VERSION</FONT>\n";
	print "</BODY></HTML>\n";
    }
    exit;
}

sub describe_control {
    my $html = shift;
    my( $cmd, $descr, $param, %d );

    %d = %Control::cmd_docs;
    if( $html ){
	print "<HTML><HEAD></HEAD><BODY BGCOLOR=\"#FFFFFF\">\n<TABLE BORDER=1>\n";
	print "<H1>Auto-Generated Documentation - Control Channel</H1>\n";
    }

    foreach $cmd (sort keys %d){
	$descr = $d{$cmd}{descr} || 'undocumented';
	$param = $d{$cmd}{param};

	if( $html ){
	    print "<TR><TD><B>$cmd</B></TD><TD>$descr";
	    print "<BR><B>params:</B> $param" if $param;
	    print "</TD></TR>\n";
	}else{
	    print "$cmd\t$descr\n";
	    print "\tparams: $param\n" if $param;
	}

    }
    if( $html ){
	print "</TABLE>\n";
	print "<BR><FONT SIZE=-1>Argus Version: $::VERSION</FONT>\n";
	print "</BODY></HTML>\n";
    }
    exit;
}


1;
