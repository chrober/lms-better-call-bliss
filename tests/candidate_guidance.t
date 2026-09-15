use strict;
use warnings;
use Test::More;
use FindBin;
use File::Temp qw(tempdir);
use File::Spec;
use DBI;
use lib "$FindBin::Bin/..";

BEGIN {
    package Slim::Utils::Log;
    sub logger { return bless {}, 'TestLogger' }
    $INC{'Slim/Utils/Log.pm'} = __FILE__;

    package TestLogger;
    sub info { }

    package Slim::Utils::Timers;
    our @pending;
    sub setTimer { push @pending, $_[2] }
    $INC{'Slim/Utils/Timers.pm'} = __FILE__;
}

require Plugins::BetterCallBliss::CandidateGuidance;

my $recording_mbid = '11111111-1111-4111-8111-111111111111';
my $artist_mbid = '22222222-2222-4222-8222-222222222222';
my $bundle = {
    schema_version => 1,
    frozen_at => '2026-09-14T12:00:00Z',
    providers => [{provider => 'last.fm', state => 'fresh'}],
    edges => [
        {
            provider => 'last.fm',
            source => {kind => 'recording', id => 'lms-track-1'},
            candidate => {
                kind => 'recording', id => 'remote-recording',
                mbid => $recording_mbid, name => 'Different spelling',
                title => 'Different title',
            },
            scope => 'endpoint_local', raw_rank => 1,
            identity_confidence => 1,
        },
        {
            provider => 'last.fm',
            source => {kind => 'artist', id => 'artist:seed', name => 'Seed'},
            candidate => {
                kind => 'artist', id => 'artist:govt mule', name => "Gov't Mule",
            },
            scope => 'collection_fallback', raw_rank => 2,
            identity_confidence => 0.9,
        },
        {
            provider => 'last.fm',
            source => {kind => 'artist', id => 'artist:seed', name => 'Seed'},
            candidate => {kind => 'artist', id => 'artist:missing', name => 'Missing'},
            scope => 'collection_fallback', raw_rank => 3,
            identity_confidence => 0.9,
        },
    ],
};
my $inventory = {
    identities => [
        {
            candidate_id => 'bliss-row-10', row_id => 10, lms_track_id => 20,
            title => 'Any title', artist => 'Any artist',
            recording_mbid => uc($recording_mbid),
        },
        {
            candidate_id => 'bliss-row-11', row_id => 11, lms_track_id => 21,
            title => 'Your Only Friend', artist => "Gov't Mule",
            artist_mbid => $artist_mbid,
        },
    ],
};

my ($resolved, $stats) =
    Plugins::BetterCallBliss::CandidateGuidance::resolve(
        $bundle, $inventory, {job_id => 'preview-1-test'},
    );

is_deeply(
    [map { $_->{resolved_candidate_id} } @{$resolved->{edges}}],
    ['bliss-row-10', 'bliss-row-11'],
    'provider results are resolved to explicit local Bliss candidates',
);
is($stats->{input_edge_count}, 3, 'all provider edges are counted');
is($stats->{resolved_edge_count}, 2, 'only locally resolved edges are retained');
is($stats->{recording_edge_count}, 1, 'recording support is counted');
is($stats->{artist_edge_count}, 1, 'artist support is counted');
is($stats->{unmatched_edge_count}, 1, 'unmatched provider evidence is visible');
is($resolved->{providers}->[0]->{provider}, 'last.fm',
    'provider provenance is retained for reporting');
ok(!exists $bundle->{edges}->[0]->{resolved_candidate_id},
    'the raw provider bundle is not mutated');

my ($async_resolved, $async_stats, $async_error);
Plugins::BetterCallBliss::CandidateGuidance::resolve_async(
    $bundle, $inventory, {job_id => 'preview-2-test'}, sub {
        ($async_resolved, $async_stats, $async_error) = @_;
    },
);
while (my $callback = shift @Slim::Utils::Timers::pending) {
    $callback->();
}
is($async_error, undef, 'asynchronous candidate resolution succeeds');
is_deeply($async_resolved, $resolved,
    'asynchronous candidate resolution produces the synchronous result');
is_deeply($async_stats, $stats,
    'asynchronous candidate resolution reports the synchronous statistics');

my $empty_callback_was_immediate = 0;
Plugins::BetterCallBliss::CandidateGuidance::resolve_async(
    {edges => []}, $inventory, {}, sub {
        my ($empty_resolved, $empty_stats, $error) = @_;
        is($error, undef, 'empty asynchronous guidance succeeds');
        is_deeply($empty_resolved->{edges}, [],
            'empty guidance does not build a candidate index');
        is($empty_stats->{candidate_identity_count}, 2,
            'empty guidance still reports candidate inventory size');
        $empty_callback_was_immediate = 1;
    },
);
ok($empty_callback_was_immediate,
    'empty guidance completes without scheduling chunk work');

my $cancelled_callback_ran = 0;
Plugins::BetterCallBliss::CandidateGuidance::resolve_async(
    $bundle, $inventory,
    {should_continue => sub { 0 }},
    sub { $cancelled_callback_ran = 1 },
);
while (my $callback = shift @Slim::Utils::Timers::pending) {
    $callback->();
}
ok(!$cancelled_callback_ran,
    'cancelled guidance matching stops without completing stale work');

my $lookup_root = tempdir(CLEANUP => 1);
my $lookup_path = File::Spec->catfile($lookup_root, 'identities.sqlite');
my $lookup_dbh = DBI->connect(
    "dbi:SQLite:dbname=$lookup_path", '', '', {RaiseError => 1},
);
$lookup_dbh->do(
    'CREATE TABLE candidate_identity ('
    . 'candidate_id TEXT PRIMARY KEY, recording_mbid TEXT, '
    . 'recording_artist TEXT, recording_title TEXT, '
    . 'artist_mbid TEXT, artist_name TEXT)'
);
$lookup_dbh->do(
    'INSERT INTO candidate_identity VALUES (?, ?, ?, ?, ?, ?)', undef,
    'bliss-row-10', $recording_mbid, 'any artist', 'any title', '',
    'any artist',
);
$lookup_dbh->do(
    'INSERT INTO candidate_identity VALUES (?, ?, ?, ?, ?, ?)', undef,
    'bliss-row-11', '', "gov't mule", 'your only friend', $artist_mbid,
    "gov't mule",
);
$lookup_dbh->disconnect;
my ($lookup_resolved, $lookup_stats, $lookup_error);
Plugins::BetterCallBliss::CandidateGuidance::resolve_async(
    $bundle,
    {
        identities => [],
        identity_lookup_path => $lookup_path,
        status => {allowed_row_count => 2},
    },
    {},
    sub { ($lookup_resolved, $lookup_stats, $lookup_error) = @_ },
);
while (my $callback = shift @Slim::Utils::Timers::pending) {
    $callback->();
}
is($lookup_error, undef, 'indexed candidate resolution succeeds');
is_deeply($lookup_resolved, $resolved,
    'indexed candidate resolution produces the in-memory result');
is_deeply($lookup_stats, $stats,
    'indexed candidate resolution preserves reporting statistics');

done_testing();
