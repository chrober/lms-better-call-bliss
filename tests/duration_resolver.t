use strict;
use warnings;
use FindBin;
use File::Spec;
use File::Temp qw(tempdir);
use DBI;
use Test::More;

BEGIN {
    package Slim::Schema;
    $INC{'Slim/Schema.pm'} = __FILE__;
    package Slim::Utils::Misc;
    $INC{'Slim/Utils/Misc.pm'} = __FILE__;
    package Slim::Utils::Unicode;
    $INC{'Slim/Utils/Unicode.pm'} = __FILE__;
}
use lib "$FindBin::Bin/..";
require Plugins::BetterCallBliss::BridgeResolver;

my $directory = tempdir(CLEANUP => 1);
my $database = File::Spec->catfile($directory, 'bliss.db');
my $dbh = DBI->connect("dbi:SQLite:dbname=$database", '', '', {RaiseError => 1});
$dbh->do('CREATE TABLE TracksV2 (File TEXT, Title TEXT, Artist TEXT, Album TEXT, Ignore INTEGER)');
$dbh->do(q{INSERT INTO TracksV2 VALUES ('candidate.flac', 'Candidate', 'Artist', 'Album', 0)});
$dbh->disconnect;
my $proofs = {map { $_ => 1 } qw(exact_target_satisfied all_source_tracks_retained_once
    all_additions_from_local_inventory unique_membership artist_repeat_window_satisfied
    album_repeat_window_satisfied track_repeat_window_satisfied_by_unique_membership)};
my $target = {source_ms => 120000, minimum_ms => 110000, maximum_ms => 130000};
my $preview = {
    mode => 'fixed_source_extension', target_track_count => 2, feasible => 1,
    added_track_count => 0, unique_membership => 1, acceptance_proofs => $proofs,
    duration_result => {%$target, actual_ms => 120000}, selected_additions => [],
    final_sequence => [{position => 0, kind => 'original', track_id => 'a'},
        {position => 1, kind => 'original', track_id => 'b'}],
};
my $job = {options => {extension_mode => 'fixed_source_extension', ordering_policy => 'preserve_order',
        addition_amount_mode => 'target_duration', target_track_count => 2, duration_target => $target},
    source_track_ids => [qw(a b)], capability => {database => $database, music_roots => []},
    artifact => {artifact_kind => 'contextual-bridge-analysis-v1', ordering_policy => 'preserve_order',
        selected_track_ids => [qw(a b)], selection_preview => $preview}};
my $result = Plugins::BetterCallBliss::BridgeResolver::resolve_bridge_preview($job);
is($result->{added_track_count}, 0, 'duration preview accepts an already suitable source');
$preview->{duration_result}->{actual_ms} = 150000;
my $valid = eval { Plugins::BetterCallBliss::BridgeResolver::resolve_bridge_preview($job); 1 };
ok(!$valid, 'a tampered duration result is rejected before acceptance');
{
    package TestDurationTrack;
    sub new { bless {secs => $_[1]}, $_[0] }
    sub secs { $_[0]->{secs} }
    sub remote { 0 }
    sub url { 'file:///candidate.flac' }
    sub artistName { 'Artist' }
    sub title { 'Candidate' }
    sub albumname { 'Album' }
}
{
    no warnings 'redefine';
    my $track = TestDurationTrack->new(120);
    local *Plugins::BetterCallBliss::BridgeResolver::_track_for_database_file = sub { $track };
    $target->{minimum_ms} = 216000;
    $target->{maximum_ms} = 264000;
    $job->{options}->{target_track_count} = 3;
    $preview->{target_track_count} = 3;
    $preview->{added_track_count} = 1;
    $preview->{duration_result} = {%$target, actual_ms => 240000};
    $preview->{selected_additions} = [{candidate_id => 'bliss-row-1', relevance_distance => 0.1}];
    $preview->{final_sequence} = [{position => 0, kind => 'original', track_id => 'a'},
        {position => 1, kind => 'bridge', track_id => 'bliss-row-1'},
        {position => 2, kind => 'original', track_id => 'b'}];
    my $added = Plugins::BetterCallBliss::BridgeResolver::resolve_bridge_preview($job);
    is($added->{added_track_count}, 1, 'duration preview resolves an added local track');
    $track->{secs} = 121;
    ok(!eval { Plugins::BetterCallBliss::BridgeResolver::resolve_bridge_preview($job); 1 },
        'a changed Lyrion track duration invalidates the frozen result');
}
done_testing();
