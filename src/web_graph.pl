# -*- perl -*-

# Copyright (c) 2005 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2005-Dec-10 12:51 (EST)
# Function: cgi graph functions
#
# $Id: web_graph.pl,v 1.15 2012/10/02 01:38:26 jaw Exp $

package Argus::Web;
use Socket;
use POSIX ('_exit');
use strict;
use vars qw($argusd $datadir $libdir);

my $USE_CACHE = 1;

sub web_graph {
    my $me = shift;
    my( $file, $ht, $r, $buf, $i );

    my $q   = $me->{q};
    my $obj = decode( $q->param('object') );
    my $tag = $q->param('tag');
    my $which = $q->param('which');
    my $size  = $q->param('size');


    return unless $me->check_acl_func($obj, 'page', 1);

    # look for recently cached image
    if( $tag ){
        $file = "$datadir/gcache/" . encode($obj) . ";$tag.$which.$size.png";
    }else{
        $file = "$datadir/gcache/" . encode($obj) . ";$which.$size.png";
    }

    if( $USE_CACHE && -f $file ){
	my $d  = (stat($file))[9];
	my $te = ($size eq 'thumb') ? 1200 : ($which eq 'samples') ? 120 : 300;
	if( $d + $te > $^T ){
	    my( $b, $i );
	    # use cached graph image
	    # print STDERR "using cached image\n";
	    open( F, $file ) || return $me->error( "could not open '$file': $!" );
	    binmode(F);
	    print $q->header( -type=>'image/png', -expires=>'+5m');
	    while( ($i=read(F, $b, 8192)) > 0 ){
		print $b;
	    }
	    close F;
	    $me->{header} = 1;
	    return;
	}
    }

    # ask picasso to paint the image
    # talk to argus, get data needed to generate graph
    $r = $argusd->command( func   => 'graphdata',
			   object => encode($obj),
                           tag    => $tag,
			   );
    return $me->error( "unable to connect to server" ) unless $r;
    return $me->error( "Unable to access <I>$obj</I><BR>$r->{resultcode} $r->{resultmsg}" )
	unless $r->{resultcode} == 200;

    my $prog = decode($r->{picasso}) || "$libdir/picasso";
    $r->{size}  = $size;
    $r->{which} = $which;

    my @list = split /\s+/, $r->{list};
    delete $r->{list};

    alarm(30);			 # trap for protocol botch, etc.
    open( CACHE, "> $file.$$" ); # we want to cache the data

    # send data to/from picasso over stdio
    pipe(PICR, PICW) || die "pipe failed: $!\n";
    pipe(PNGR, PNGW) || die "pipe failed: $!\n";

    my $pid;
    if( $pid = fork ){
	# parent
	for my $k (keys %$r){
	    print PICW "-$k: $r->{$k}\n";
	}
	for my $o (@list){
	    print PICW $o, "\n";
	}
	# empty line tells picasso: no more data to read
	print PICW "\n";

	close PICW; close PICR;
	close PNGW;
    }else{
	# child
	# shuffle filedescriptors around
        eval { untie(*STDIN); untie(*STDOUT); };	# bug in some vesions of mod_perl
	close STDIN;  open( STDIN,  "<&PICR" );
	close STDOUT; open( STDOUT, ">&PNGW" );
	close PICR; close PNGR;
	close PICW; close PNGW;
	exec( $prog, '-stdin', '1');
	_exit(-1);
    }

    binmode(CACHE);
    binmode(PNGR);
    my $sent = 0;
    while( read(PNGR, $buf, 8192) > 0 ){
	unless( $sent ){
	    print $q->header( -type=>'image/png', -expires=>'+5m');
	    $sent = 1;
	}
	# send image to user and to cache file
	print CACHE $buf;
	print $buf;
    }
    close CACHE;
    close PNGR;
    waitpid $pid, 0;
    my $err = $?;
    alarm(0);

    unless( $sent ){
	# if no data was returned by picasso, remove tmpfile and display error image
	$err ||= 1;
	return $me->web_graph_error_image();
    }

    if( $err ){
	# toss tmp file if picasso had an error
	unlink "$file.$$";
    }else{
	rename "$file.$$", $file;
    }
    $me->{header} = 1;

}

sub web_graphpage {
    my $me = shift;
    my( $obj, $which, $size, $r, $back, @opt );

    $obj = decode( $me->{q}->param('object') );
    my $tag = $me->{q}->param('tag');
    my $url = $me->{q}->url();

    return unless $me->check_acl_func($obj, 'page', 1);

    $r = $argusd->command( func   => 'graphdata',
			   object => encode($obj),
                           tag    => $tag,
			   );
    return $me->error( "unable to connect to server" ) unless $r;
    return $me->error( "Unable to access <I>$obj</I><BR>$r->{resultcode} $r->{resultmsg}" )
	unless $r->{resultcode} == 200;

    $which = $me->{q}->param('which');
    $back  = $me->{q}->url() . "?object=" . encode($obj) . ";func=page";
    $me->startpage( title   => "Graph $obj",
		    refresh => decode($r->{refresh}),
		    bkgimg  => decode($r->{bkgimg}),
		    style   => decode($r->{style_sheet}),
		    icon    => decode($r->{icon}) );
    print decode($r->{header}), "\n";

    # <A HREF="$back"><FONT COLOR="#000000">$obj</FONT></A>

    my $ht = $r->{gr_height} || 192;

    my $title = ($obj =~ /^Top/) ? "<A HREF=\"$url?object=" . encode($obj) . ";func=page\">$obj</A>" : $obj;
    $me->top_of_table( mainclass => 'graphmain', title => $title, branding => decode($r->{branding}) );

    print "<TR><TD VALIGN=TOP>\n";

    graphpage_links($me, $r, $obj, $which);

    print "<BR><CENTER>\n";
    my $tagd = $tag ? "tag=$tag;" : '';
    print "<IMG WIDTH=640 HEIGHT=$ht SRC=\"$url?object=",
    encode($obj), ";func=graph;which=$which;size=full;${tagd}ext=.png\"><BR>\n";
    print "</CENTER><BR>\n";

    print "</TD></TR>\n";


    $me->bot_of_table();
    print decode($r->{footer}), "\n";
    $me->endpage();
}

sub graphpage_links {
    my $me = shift;
    my $r  = shift;
    my $obj   = shift;
    my $which = shift;

    my @links  = map {decode($_)} split /\s+/, $r->{links};
    my @labels = map {decode($_)} split /\s+/, $r->{clabels};

    if( @links > 1 || $obj ne $links[0] ){
        # include list of sub-objects
        print qq{<div class=graphpagelinks><br>};

        # link to page or graphpage ?
        my $topage = (@links == 1) ? 1 : 0;

        while( @links ){
            my $link  = shift @links;
            my $label = shift @labels;

            if( $topage ){
                print qq{<A HREF="}, $me->{q}->url(), "?object=", $link, qq{;func=page">$label</A><BR>\n};
            }else{
                print qq{<A HREF="}, $me->{q}->url(), "?object=", $link, qq{;func=graphpage;which=$which;size=full">$label</A><BR>\n};
            }
        }
        print "</div>\n";
    }
}

# gif image of:
#    argus cgi: graph error ...
my $web_graph_error_gif = <<EOIMAGE;
47494638 3761A000 40008000 00000000  FF88882C 00000000 A0004000 0002FE84
8FA9CBED 0FA39CB4 B280B3DE BCFB0F86  E24896E6 B919E8CA B6EE0B87 6A4CD7F6
EDCEF8CE F7B81E40 60121961 1030441E  811CE352 A9301989 C919D5AA 6C12AFCE
69378B3D 26C5E270 B8638682 B3E34F7A  FC2EAB3D CCB8CA3E 6FDFE775 3E9BFEC7
D456F5A7 D107E787 38981298 28A748A6  9376B018 A92658D4 88A6E9D6 4869F974
F9A9F5C9 55EA372A B9958A44 799609C8  B8042BD5 BAA72A74 48A6C588 BB8608A4
AA78B657 89B9ABF7 5B3B9C57 6C98C7FB  0C4A6CBB 2BFC88ED AC5D980C 6ACC4DBB
3DCD79AC 2B8E3788 1E4A9879 CC4E68EB  E5BE8E6E 0E1EA5EE D5EDD333 CFFFBF09
A0C08104 A5153C88 7087BF84 0C1B8A58  E830A2C4 4A132B5A 84D802DC 40FE8D0A
7D6064C1 D1108F90 6E5690CC C1861594  48D6B0B8 5339A4E5 4A5CEF66 019AB906
67CC8FCB 62FA2CC2 D24A10A0 434BEE04  2A140C4B 91457F72 532A5464 D2953724
916A8534 AB4F8E50 7321F5DA 8B2A3C34  5A9FDD29 7BF28455 A643A1A2 FD79136E
53AC6C9D C225592A C55BA555 F9B685B3  97A8D8BA 4DED06D2 BB94AE51 A282ABFD
759A5646 4A618A2B 5731B829 A75D9B85  CEA67B19 551AD6D0 CA5EF0AC CAB8A15F
1091639C EEDB9ADF 281904FD C586316F  F288DB16 29AA96CB 7A776F93 5D695D3E
6E33F96C C4ED8CDF A53C1CC5 35BFAB1F  5BB74C36 7BE1B95A 5F0F5FCB 1DB83EE3
D56B7661 BE2575F4 DDD4191F BE8BB83C  FCCDEED1 AFEFB934 FC63CFD7 FEF5332F
0A1E7D5B 95765F40 3B69869C 673021D7  842C9734 976065BC 45146081 16F623DF
851AD2E0 1D481BDA D0613400 4DF8211D  C2496616 84C9D9C7 1932BD40 E8185F79
81A6535B 083A66A2 8ACBC562 D85B0D1E  752070DC 15D71F91 4F7D1564 9183B1D8
1F8AE4E5 E2845436 BAA2DE93 54B2150F  7F3769B9 9D5B0FD5 97216682 FD47D668
4C66F79E 945DD246 589A8A05 B7D98E06  0E496683 661A7424 9055D295 668EEAB9
B99D9F5E CA22A272 349978A3 8B291E97  27A30F85 261EA471 45A85BA1 255E2AE8
A3986EDA C9492172 0AEAA7A0 6E2AEAA8  97966AEA 87A8A6AA E1AAAC5A E8EAABF7
C52A6B74 B4D6DADB ADB856A4 EBAE12F5  EAAB43C0 06CBD0B0 C422640B 41B2CA2E
CB6CB3CE 4A500000 3B
EOIMAGE
    ;
$web_graph_error_gif =~ s/\s//gs;
$web_graph_error_gif = pack('H*', $web_graph_error_gif);

# spit out canned error image
sub web_graph_error_image {
    my $me = shift;

    print STDERR "picasso failed. cannot generate graph image.\n";
    print $me->{q}->header( -type=>'image/gif', -expires=>'+5m');
    $me->{header} = 1;

    print $web_graph_error_gif;

}

1;
