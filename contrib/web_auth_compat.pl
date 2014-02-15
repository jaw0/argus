# -*- perl -*-
# replacement web_auth
#
# use system passwd/groups
# just like old argus

# if system has shadow file, this will need to be run as root
#
# user's home object is always 'Top'
# returns list of unix groups as access control groups

sub auth_user {
    my $user = shift;
    my $pass = shift;

    my $cp = (getpwnam($user))[1];
    if( crypt($pass, $cp) eq $cp){
	my $g = `groups $user`;
	chop $g;
	my @g = split /\s+/, $g;

	return ('Top', @g);
    }
    return ;
}

1;
