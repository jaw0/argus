# -*- perl -*-

# Copyright (c) 2012
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2012-Sep-15 12:45 (EDT)
# Function: custom dashboards
#
# $Id: Argus::Dashboard.pm,v 1.5 2012/10/14 21:42:06 jaw Exp $

package Argus::Dashboard;
@ISA = qw(Configable);
use vars qw(@ISA $doc);

use Argus::Color;
use Argus::Encode;
use Argus::Interpolate;
use Argus::Dashboard::Row;
use Argus::Dashboard::Col;
use Argus::Dashboard::Widget;
use strict;

my %alldash = ();


my @param = qw(cssid cssclass style);
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

sub find {
    my $name = shift;

    $name =~ s/^Dash://i;
    return $alldash{ $name };
}

sub list {
    return keys %alldash;
}

sub config {
    my $me = shift;
    my $cf = shift;
    my $more = shift;

    $me->init_from_config( $cf, $doc, '' );
    $me->{maxwidth} = $me->width();
    $me->check($cf);

    $alldash{ $me->{name} } = $me;
}

sub check {
    my $me = shift;
    my $cf = shift;

    $me->check_typos( $cf ) if $cf;
    Doc::check( $me )       if $::opt_T;

}

sub width {
    my $me = shift;

    my $max;
    for my $c (@{$me->{children}}){
        my $w = $c->width();
        $max = $w if $w > $max;
    }
    return $max;
}

sub pathname {
    my $me = shift;

    my $f = encode('Dash:' . $me->{name});
    my $d = ::hashed_directory($f);

    return "$d/$f";

}

sub web_build {
    my $me = shift;

    my $top  = $::Top;
    my $file = "$::datadir/html/" . $me->pathname();

    my $fh = BaseIO::anon_fh();
    return ::loggit( "Cannot open web file '$file': $!", 0 )
	unless open( $fh, "> $file" ) ;
    $top->{web}{buildtime} = $^T;

    $top->web_header($fh, "Dashboard : $me->{name}", 'dashboard' );


    # RSN - acl
    # print $fh "<!-- START AUTHORIZATION READ NEEDED $me->{acl_page} -->\n";

    if( $top->{alarm} ){
	my $t = $top->{sirentime};
	my $wav = $top->{web}{sirensong};
        print $fh "<!-- START SIREN $t $wav -->\n" if $wav;
    }

    print $fh "<TABLE WIDTH=\"100%\" BORDER=0 CLASS=DASHBOARD>\n";
    $top->web_branding($fh, 2);
    $top->web_show_has_errors($fh, 2) if $Conf::has_errors;

    my $color = web_element_color( $Conf::has_errors ? 'top_error' : 'top_normal' );
    my $attr  = $me->attr();
    my $nospkr = $top->{web}{nospkr_icon};
    $nospkr = "<IMG SRC=\"$nospkr\" ALT=\"speaker off\">" if $nospkr;

    print $fh <<X;
<!-- PUT WARNINGS HERE -->
<TR BGCOLOR="$color"><TD COLSPAN=2>
  <TABLE BORDER=0 WIDTH="100%" CLASS=TOPBAR>
    <TR><TD ALIGN=LEFT class=objectname><L10N Dashboard> : $me->{name}</TD>
        <TD ALIGN=RIGHT class=username><L10N User>: <TT>__USER__</TT>
	<!-- SIREN ICON -->$nospkr
    </TD></TR>
  </TABLE>
</TD></TR>
X
    ;

    $me->buttons($fh);

    print $fh "<TR><TD colspan=2><TABLE $attr cellpadding=2 cellspacing=0 border=0>\n";


    for my $c ( @{$me->{children}} ){
        $c->web_make($fh);
    }


    print $fh "</TABLE></TD></TR></TABLE>\n";
    $top->web_footer($fh);
    return $file;
}

sub web_button {
    my $me = shift;
    return '<td>' . $::Top->web_button(@_) . '</td>';
}
sub web_button_no {
    my $me = shift;
    return '<td>' . $::Top->web_button_no(@_) . '</td>';
}
sub web_button_text {
    my $me = shift;
    return '<td>' . $::Top->web_button_text(@_) . '</td>';
}

sub buttons {
    my $me = shift;
    my $fh = shift;

    my $top = $::Top;

    print $fh "<TR><TD colspan=2 align=right><table class=dashbuttons cellspacing=0 cellpadding=0>\n";

    # Top
    print $fh $me->web_button_text( "<A HREF=\"__BASEURL__?object=__TOP__;func=page\"><span class=buttonarrow>&lArr;</span>&nbsp;&nbsp;Top</A>" );


    print $fh "<!-- START AUTHORIZATION RW NEEDED $top->{acl_ntfylist} -->\n";
    print $fh $me->web_button_no('Notifies', undef, 'func=ntfylist');
    print $fh $me->web_button_no('Un-Acked__NUMUNACKED__', '__UNACKEDCLASS__', 'func=ntfylsua');
    print $fh "<!-- END AUTHORIZATION RW NEEDED -->\n";

    print $fh $me->web_button_no('Overview', undef, 'object=overview', 'func=page');

    # error log
    print $fh "<!-- START AUTHORIZATION RW NEEDED $top->{acl_logfile} -->\n";

    my $errclass = $Conf::has_errors ? 'ERRORSBUTTON' : undef;
    print $fh $me->web_button_no('Error Log', $errclass, 'func=logfile', 'abridge=1' );
    print $fh "<!-- END AUTHORIZATION RW NEEDED -->\n";

    if( $top->{alarm} && $top->{web}{sirensong} ){
	my $t = $top->{sirentime};
	print $fh "<!-- START SIRENBUTTON $t -->\n";
        print $fh $me->web_button_no('Hush Siren', undef, 'func=hushsiren', "object=Dash:" . encode($me->{name}));
	print $fh "<!-- END SIRENBUTTON -->\n";
    }

    print $fh $me->web_button('Logout', undef, 'func=logout');


    print $fh "</table></TD></TR>\n";
}

sub attr {
    my $me = shift;

    my $t;
    $t .= " class=\"$me->{cssclass}\"" if $me->{cssclass};
    $t .= " class=\"$me->{cssid}\"" if $me->{cssid};

    for my $a (@_){
        $t .= " $a=\"$me->{$a}\"" if $me->{$a};
    }

    return $t;
}

sub debug {}

sub expand {
    my $me = shift;
    my $txt = shift;

    return interpolate($me, $txt);
}

sub gen_confs {
    my( $r );

    foreach my $d (sort {$a->{name} cmp $b->{name}} values %alldash){
        $r .= $d->gen_conf();
    }
    $r = "\n$r" if $r;

    $r;
}


################################################################
Doc::register( $doc );

1;
