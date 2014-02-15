# -*- perl -*-

# Copyright (c) 2003 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Date: 2003-Sep-16 23:05 (EDT)
# Function: i18n, l10n
#
# $Id: localization.pl,v 1.5 2011/11/19 19:02:32 jaw Exp $

# Therefore is the name of it called Babel; because the LORD did there confound
# the language of all the earth
#   -- GEN 11:9

my $lang;
my %table;

sub l10n_curr_lang { $lang }

sub init_l10n {
    my $web = shift;
    $lang = shift;   # see above
    my( $id, $str );

    return unless $lang;
    # print STDERR "init lang: $lang\n";
    
    unless( $table{$lang} ){
	# load translations

	unless( open( T, "$datadir/locale/$lang" ) ){
	    print STDERR "requested locale ($lang) not found, using english.\n"
		unless $lang eq 'default';
	    return;
	}

	my($l, $c) = $lang =~ /([^\.]+)(?:\.(.*))?/;
	$table{$lang}{lang} = $l;
	$table{$lang}{charset} = $c;
	
	while( <T> ){
	    chop;
	    next if /^\#/;
	    next if /^\s*$/;
	    
	    if( /^msgid\s+"(.*)"/ ){
		$id = $1;
	    }
	    elsif( /^msgstr\s+"(.*)"/ ){
		$str = $1;
		
		$table{$lang}{p}{$id} = $str if $id;
		$id = undef;
	    }
	    
	    elsif( /^days\s+(.*)/ ){
		$table{$lang}{days} = [ split /\s+/, $1 ];
	    }
	    elsif( /^months\s+(.*)/ ){
		$table{$lang}{months} = [ split /\s+/, $1 ];
	    }
	    
	    elsif( /^charset\s+"(.*)"/ ){
		$table{$lang}{charset} = $1;
	    }
	    elsif( /^lang\s+"(.*)"/ ){
		$table{$lang}{lang} = $1;
	    }
	    elsif( /^datefmt\s+"(.*)"/ ){
		$table{$lang}{datefmt} = $1;
	    }
	    else{
		print STDERR "invalid line: $_\n";
	    }
	    
	    # ...
	    
	}
	close T;
    }

    $web->{charset} = $table{$lang}{charset};
    
}

sub l10n {
    my $phrase = shift;

    # if( $lang eq 'piglatin' ){
    # 	  $phrase =~ s/(\w)(\w*)/$2$1ay/g;
    # 	  return $phrase;
    # }

    # print STDERR "L10N: $phrase\n";

    return $phrase unless $table{$lang};
    $table{$lang}{p}{$phrase} || $phrase;
}

sub l10n_localtime {
    my $t = shift || $^T;

    # NB: localtime obeys ENV{TZ}
    my @l = localtime($t);

    if( is_mobile() ){
        return strftime('%Y-%m-%d %H:%M', @l);
    }
    
    if( $table{$lang} && $table{$lang}{datefmt} ){
        return strftime( $table{$lang}{datefmt}, @l );
    }
    
    # day dom mon HH:MM:SS YYYY
    if( $table{$lang} && $table{$lang}{days} && $table{$lang}{months} ){
	sprintf "%s %d %s %0.2d:%0.2d:%0.2d %d",
	$table{$lang}{days}[ $l[6] ],	# 0..6
	$l[3],
	$table{$lang}{months}[ $l[4] ], # 0..11
	@l[2,1,0],
	$l[5] + 1900;

    }else{
	strftime( "%a %e %b %T %Y", @l );
    }
}

1;
