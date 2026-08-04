use strict;
use warnings;
use FindBin;
use Test::More tests => 16;

BEGIN {
    package main;
    sub DEBUGLOG () { 0 }

    package TestLogger;
    sub is_debug { return 0 }
    sub debug { }
    sub info { }
    sub warn { }

    package Slim::Utils::Log;
    sub logger { return bless {}, 'TestLogger' }
    $INC{'Slim/Utils/Log.pm'} = __FILE__;

    package Slim::Utils::PluginManager;
    sub isEnabled { return 1 }
    $INC{'Slim/Utils/PluginManager.pm'} = __FILE__;

    package Plugins::LastMix::LFM;
    our ($mode, $calls);
    sub getSimilarTracks {
        my ($class, $callback, $args) = @_;
        $calls++;
        return $callback->({
            similartracks => {
                track => [{
                    name => 'Similar ' . $args->{title},
                    match => '0.90',
                    artist => {name => 'Similar ' . $args->{artist}},
                }],
            },
        });
    }
    sub getSimilarArtists {
        my ($class, $callback, $args) = @_;
        $calls++;
        if ($mode eq 'rate_limit' && $args->{artist} eq 'Artist B') {
            return $callback->({
                error => 29,
                message => 'Rate limit exceeded',
            });
        }
        return $callback->({
            similarartists => {
                artist => [{
                    name => 'Similar ' . $args->{artist},
                    match => '0.75',
                }],
            },
        });
    }
    $INC{'Plugins/LastMix/LFM.pm'} = __FILE__;
}

use lib "$FindBin::Bin/..";
require Plugins::BetterCallBliss::LastFmEvidence;

my @two_artists = (
    {artist => 'Artist A', artist_mbids => []},
    {artist => 'Artist A', artist_mbids => []},
    {artist => 'Artist B', artist_mbids => []},
);

$Plugins::LastMix::LFM::mode = 'fresh';
$Plugins::LastMix::LFM::calls = 0;
my $fresh;
Plugins::BetterCallBliss::LastFmEvidence::prepare(
    1, \@two_artists, sub { $fresh = shift },
);
ok($fresh, 'fresh evidence callback runs');
is($fresh->{providers}->[0]->{state}, 'fresh', 'healthy provider is fresh');
is($fresh->{providers}->[0]->{request_count}, 2, 'distinct artists are queried');
is(scalar @{$fresh->{edges}}, 4, 'each result has local and collection edges');
is_deeply(
    [sort map { $_->{scope} } @{$fresh->{edges}}],
    [qw(collection_fallback collection_fallback endpoint_local endpoint_local)],
    'both evidence scopes are emitted',
);

$Plugins::LastMix::LFM::mode = 'fresh';
$Plugins::LastMix::LFM::calls = 0;
my $track_evidence;
Plugins::BetterCallBliss::LastFmEvidence::prepare(
    1,
    [{
        id => 'lms-track-7',
        title => 'Source Song',
        artist => 'Source Artist',
        artist_mbids => [],
    }],
    sub { $track_evidence = shift },
);
is($track_evidence->{providers}->[0]->{request_count}, 2,
    'one source track produces one track and one artist request');
is(scalar @{$track_evidence->{edges}}, 3,
    'track result and both artist scopes are frozen');
my ($recording_edge) = grep {
    $_->{source}->{kind} eq 'recording'
} @{$track_evidence->{edges}};
ok($recording_edge, 'recording-level evidence is emitted');
is($recording_edge->{source}->{id}, 'lms-track-7',
    'recording evidence binds to the optimizer source identity');
is($recording_edge->{candidate}->{title}, 'Similar Source Song',
    'similar track title is retained for local candidate matching');
is($recording_edge->{raw_score}, 0.90,
    'Last.fm track match score is retained');

my @three_artists = (
    @two_artists,
    {artist => 'Artist C', artist_mbids => []},
);
$Plugins::LastMix::LFM::mode = 'rate_limit';
$Plugins::LastMix::LFM::calls = 0;
my $partial;
Plugins::BetterCallBliss::LastFmEvidence::prepare(
    1, \@three_artists, sub { $partial = shift },
);
ok($partial, 'partial evidence callback runs');
is($partial->{providers}->[0]->{state}, 'partial', 'rate limit is partial');
is($Plugins::LastMix::LFM::calls, 2, 'rate limit opens the circuit');
is_deeply(
    $partial->{providers}->[0]->{error_codes},
    ['LASTFM_29'],
    'rate-limit error is reported',
);

my $disabled;
Plugins::BetterCallBliss::LastFmEvidence::prepare(
    0, \@three_artists, sub { $disabled = shift },
);
is($disabled->{providers}->[0]->{state}, 'disabled', 'disabled stays local');
