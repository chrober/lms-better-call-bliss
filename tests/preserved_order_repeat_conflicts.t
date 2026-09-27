use strict;
use warnings;
use FindBin;
use Test::More tests => 9;

use lib "$FindBin::Bin/..";
require Plugins::BetterCallBliss::RepeatConflicts;

my @almtal = (
    {artist => 'Rory Gallagher', album => 'Album 1'},
    {artist => 'Uriah Heep', album => 'Album 2'},
    {artist => 'Rainbow', album => 'Album 3'},
    {artist => 'The Black Keys', album => 'Album 4'},
    {artist => 'The Black Angels', album => 'Album 5'},
    {artist => 'Karma to Burn', album => 'Album 6'},
    {artist => 'Wovenhand', album => 'Album 7'},
    {artist => 'Cream', album => 'Album 8'},
    {artist => 'Ten Years After', album => 'Cricklewood Green'},
    {artist => 'Jared James Nichols', album => 'Album 10'},
    {artist => 'The Vintage Caravan', album => 'Album 11'},
    {artist => 'Ten Years After', album => 'A Space in Time'},
);

my $artist = Plugins::BetterCallBliss::RepeatConflicts::first_preserved_order_conflict(
    \@almtal, 5, 10,
);
is($artist->{kind}, 'artist', 'finds the first preserved-order artist conflict');
is($artist->{value}, 'Ten Years After', 'reports the repeated artist');
is_deeply($artist->{positions}, [9, 12], 'reports one-based source positions');
is($artist->{window}, 5, 'reports the active artist look-back window');
is(
    Plugins::BetterCallBliss::RepeatConflicts::preserved_order_conflict_message($artist),
    'Preserve source order violates the artist repeat window of 5: Ten Years After occurs at source positions 9 and 12. Improve difficult transitions cannot repair this fixed source spacing. Choose Add spacing tracks as needed or Optimize source order.',
    'formats an actionable explanation for the preview result',
);

ok(!Plugins::BetterCallBliss::RepeatConflicts::first_preserved_order_conflict(
    \@almtal, 2, 10,
), 'does not flag an artist outside its look-back window');

my $album = Plugins::BetterCallBliss::RepeatConflicts::first_preserved_order_conflict(
    [
        {artist => 'Artist A', album => 'Shared Album'},
        {artist => 'Artist B', album => 'Other Album'},
        {artist => 'Artist C', album => 'Shared Album'},
    ],
    0, 2,
);
is($album->{kind}, 'album', 'also detects preserved-order album conflicts');
is($album->{value}, 'Shared Album', 'reports the repeated album');
is_deeply($album->{positions}, [1, 3], 'reports album conflict positions');
