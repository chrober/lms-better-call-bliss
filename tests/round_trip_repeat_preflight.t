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
my $history = [{id => 'history', artist => 'A', album => 'X'}];
my $one_way_album = [
    {id => 'start', artist => 'C', album => 'Z'},
    {id => 'first', artist => 'B', album => 'Y'},
    {id => 'second', artist => 'A', album => 'X'},
];
is(Plugins::BetterCallBliss::RepeatConflicts::destination_minimum_intermediates(
    $history, $one_way_album, 0, 0, 5, 0, 'exact_bliss_credit'), 3,
    'one-way album checks later destination tracks against listening history');
my $one_way_track = [
    {id => 'start', artist => 'A', album => 'X'},
    {id => 'target', artist => 'A', album => 'X'},
];
is(Plugins::BetterCallBliss::RepeatConflicts::destination_minimum_intermediates(
    [], $one_way_track, 0, 5, 10, 0, 'exact_bliss_credit'), 10,
    'one-way track computes the strictest boundary requirement');
is(Plugins::BetterCallBliss::RepeatConflicts::destination_minimum_intermediates(
    [], $one_way_track, 0, 0, 0, 0, 'exact_bliss_credit'), 0,
    'one-way track is feasible with repeat windows disabled');
is(Plugins::BetterCallBliss::RepeatConflicts::destination_minimum_intermediates(
    [], $return_to_album, 1, 5, 10, 0, 'exact_bliss_credit'), 0,
    'round trip exempts the original queue anchors from each other');
my $fixed = [
    {id => 'a', artist => 'A', album => 'X', database_file => 'same'},
    {id => 'b', artist => 'B', album => 'Y', database_file => 'same'},
];
is(Plugins::BetterCallBliss::RepeatConflicts::fixed_gap_repeat_conflict(
    $fixed, 1, 0, 0, 2, 'exact_bliss_credit')->{kind}, 'track',
    'fixed gaps detect two identifiers for the same track');
ok(!Plugins::BetterCallBliss::RepeatConflicts::fixed_gap_repeat_conflict(
    $fixed, 2, 0, 0, 2, 'exact_bliss_credit'),
    'fixed gap with enough positions is feasible');
my $empty_files = [ {id => 'one', database_file => ''}, {id => 'two', database_file => ''} ];
ok(!Plugins::BetterCallBliss::RepeatConflicts::fixed_gap_repeat_conflict(
    $empty_files, 1, 0, 0, 2, 'exact_bliss_credit'),
    'empty database paths are not treated as identical track identities');
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
open my $jobs_file, '<', "$FindBin::Bin/../BetterCallBliss/Jobs.pm" or die $!;
local $/;
my $jobs_source = <$jobs_file>;
close $jobs_file;
my $destination_check = index($jobs_source, 'RepeatConflicts::destination_minimum_intermediates(');
my $fixed_check = index($jobs_source, 'RepeatConflicts::fixed_gap_repeat_conflict(');
my $inventory = index($jobs_source, 'CandidateInventory::prepare_async(', $destination_check);
ok($destination_check >= 0 && $inventory > $destination_check,
    'destination preflight is positioned before asynchronous candidate inventory');
ok($fixed_check >= 0 && $inventory > $fixed_check,
    'fixed-gap preflight is positioned before asynchronous candidate inventory');
done_testing();
