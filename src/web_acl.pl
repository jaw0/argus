# -*- perl -*-

# Copyright (c) 2002 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2002-Sep-17 17:18 (EDT)
# Function: acl handling for web pages
#
# $Id: web_acl.pl,v 1.14 2012/09/16 18:52:50 jaw Exp $

# return 0 on failure
#        1 on good

sub check_acl_func {
    my $me  = shift;
    my $obj = shift;
    my $fnc = shift;
    my $epp = shift;
    my( $r, $acl );

    $obj = 'Top' if $obj =~ /^Dash:/; # QQQ
    $r = $argusd->command( func => 'getparam',
			   object => encode($obj),
			   param => "acl_$fnc",
			   );
    unless( $r && $r->{value} ){
	$me->error( "an error occurred while talking to the server" )
	    if $epp;
	return 0;
    }
    $acl = decode($r->{value});

    # print STDERR "acl: $acl\n";
    return 1 if $me->check_acl($acl);

    $me->web_acl_error($fnc) if $epp;
    0;
}

sub check_acl_ack {
    my $me = shift;
    my $id = shift;
    my $epp = shift;
    my( $r, $acl, $fnc );
    
    if( $id eq 'all' ){
	$fnc = 'ntfyackall';
	$r = $argusd->command( func => 'getparam',
			       object => 'Top',
			       param => 'acl_ntfyackall',
			       );
	unless( $r && $r->{value} ){
	    $me->error( "an error occurred while talking to the server" )
		if $epp;
	    return 0;
	}
	$acl = decode($r->{value});
    }else{
	$fnc = 'ntfyack';
	$r = $argusd->command( func => 'notify_detail',
			       idno => $id );
	unless( $r && $r->{resultcode} == 200 ){
	    $me->error( "an error occurred while talking to the server" )
		if $epp;
	    return 0;
	}
	$acl = decode($r->{acl_ntfyack});
    }
    return 1 if $me->check_acl($acl);
    $me->web_acl_error($fnc) if $epp;
    0;
}

sub check_acl {
    my $me = shift;
    my $acl = shift;
    my( @grps );
    
    return 1 if $acl =~ /ALL/;
    @grps = @{$me->{auth}{grps}};
    
    foreach my $a (split /\s+/, $acl){
	return 1 if grep {$a eq $_} @grps;
    }
    0;
}

sub web_acl_error {
    my $me = shift;
    my $fnc = shift;
    
    $me->error( "<B>Access Denied</B><P><I>You do not have</I> <TT>$fnc</TT> " .
		"<I>permission on the requested object</I>" );
}

1;
