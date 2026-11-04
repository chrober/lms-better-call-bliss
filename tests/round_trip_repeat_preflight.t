use strict;
use warnings;
use FindBin;
use Test::More;
use lib "$FindBin::Bin/..";
require Plugins::BetterCallBliss::RepeatConflicts;

my $tracks = [
    { id => 'start', artist => 'Artist', album => 'Album' },
    { id => 'target', artist => 'Artist', album => 'Album' },
    { id => 'rejoin', artist => 'Artist', album => 'Album' },
];
is(Plugins::BetterCallBliss::RepeatConflicts::round_trip_minimum_intermediates(
    $tracks, 5, 10, 0, 'exact_bliss_credit'), 20,
    'both fixed boundaries require ten album-spacing tracks');
is(Plugins::BetterCallBliss::RepeatConflicts::round_trip_minimum_intermediates(
    $tracks, 5, 0, 0, 'exact_bliss_credit'), 10,
    'artist spacing applies to both boundaries independently');
is(Plugins::BetterCallBliss::RepeatConflicts::round_trip_minimum_intermediates(
    $tracks, 0, 0, 0, 'exact_bliss_credit'), 0,
    'disabled repeat windows do not require additions');
my $distinct = [
    { id => 'start', artist => 'A', album => 'One' },
    { id => 'target', artist => 'B', album => 'Two' },
    { id => 'rejoin', artist => 'C', album => 'Three' },
];
is(Plugins::BetterCallBliss::RepeatConflicts::round_trip_minimum_intermediates(
    $distinct, 5, 10, 0, 'exact_bliss_credit'), 0,
    'distinct boundary anchors are not rejected by the lower bound');
my $return_to_album = [
    { id => 'start', artist => 'A', album => 'Album A' },
    { id => 'target', artist => 'B', album => 'Album B' },
    { id => 'rejoin', artist => 'A', album => 'Album A' },
];
is(Plugins::BetterCallBliss::RepeatConflicts::round_trip_minimum_intermediates(
    $return_to_album, 5, 10, 0, 'exact_bliss_credit'), 0,
    'existing queue anchor pair does not require extra bridge tracks');
my $album_destination = [
    { id => 'start', artist => 'A', album => 'X' },
    { id => 'first', artist => 'A', album => 'Y' },
    { id => 'last', artist => 'B', album => 'Z' },
    { id => 'rejoin', artist => 'C', album => 'Z' },
];
is(Plugins::BetterCallBliss::RepeatConflicts::round_trip_minimum_intermediates(
    $album_destination, 5, 10, 0, 'exact_bliss_credit'), 15,
    'album destination uses its first and last tracks as the two boundaries');
my $collaboration = [
    { id => 'start', artist => 'A & B', artist_identity_keys => ['artist:a', 'artist:b'], primary_artist_identity_key => 'artist:b' },
    { id => 'target', artist => 'A', artist_identity_keys => ['artist:a'], primary_artist_identity_key => 'artist:a' },
    { id => 'rejoin', artist => 'C', artist_identity_keys => ['artist:c'], primary_artist_identity_key => 'artist:c' },
];
is(Plugins::BetterCallBliss::RepeatConflicts::round_trip_minimum_intermediates(
    $collaboration, 5, 0, 0, 'shared_artist'), 5,
    'shared artist identities detect a boundary conflict');
is(Plugins::BetterCallBliss::RepeatConflicts::round_trip_minimum_intermediates(
    $collaboration, 5, 0, 0, 'primary_artist'), 0,
    'primary identity mode does not turn another contributor into a conflict');
my $aliased = [
    { id => 'start', database_file => '/music/a.flac' },
    { id => 'target', database_file => '/music/a.flac' },
    { id => 'rejoin', database_file => '/music/b.flac' },
];
is(Plugins::BetterCallBliss::RepeatConflicts::round_trip_minimum_intermediates(
    $aliased, 0, 0, 100, 'exact_bliss_credit'), 100,
    'two identifiers for the same analyzed file satisfy the track-repeat test');
done_testing();
