use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/..";

BEGIN {
    package Slim::Utils::Log;
    sub logger { return bless {}, 'TestLogger' }
    $INC{'Slim/Utils/Log.pm'} = __FILE__;

    package TestLogger;
    sub info { }
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

done_testing;
