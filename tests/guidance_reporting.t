use strict;
use warnings;
use Test::More;
require './BetterCallBliss/GuidanceReporting.pm';

my $summary = Plugins::BetterCallBliss::GuidanceReporting::summary([
    { provider_id => 'library-signals-guidance', channel => 'album_playcount', contribution => 0.2 },
    { provider_id => 'library-signals-guidance', channel => 'artist_last_played', contribution => -0.1 },
]);
like($summary, qr/album play-count boost \+0\.2000/, 'album influence is explained in the result');
like($summary, qr/artist last-played penalty -0\.1000/, 'artist influence is explained in the result');
done_testing();
