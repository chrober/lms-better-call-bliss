use strict;
use warnings;
use FindBin;
use Test::More;

use lib "$FindBin::Bin/..";
require Plugins::BetterCallBliss::Defaults;

{
    package IdentityTestPrefs;
    sub new { bless { %{$_[1] || {}} }, $_[0] }
    sub get { $_[0]->{$_[1]} }
    sub set { $_[0]->{$_[1]} = $_[2] }
}

my $existing = IdentityTestPrefs->new({ artist_repeat_mode => 'primary_artist' });
Plugins::BetterCallBliss::Defaults::migrate_artist_identity($existing);
is($existing->get('artist_repeat_mode'), 'follow_lab',
    'upgrade switches the existing identity preference to follow Lab');
$existing->set('artist_repeat_mode', 'exact_bliss_credit');
Plugins::BetterCallBliss::Defaults::migrate_artist_identity($existing);
is($existing->get('artist_repeat_mode'), 'exact_bliss_credit',
    'subsequent initialization retains the user-selected override');
my $fresh = IdentityTestPrefs->new({});
Plugins::BetterCallBliss::Defaults::migrate_artist_identity($fresh);
is($fresh->get('artist_repeat_mode'), 'follow_lab',
    'a fresh installation follows Lab');
done_testing();
