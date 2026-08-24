use strict;
use warnings;
use FindBin;
use Test::More tests => 30;

BEGIN {
    package TestLog;
    sub debug { }
    sub info { }

    package Slim::Utils::Log;
    sub logger { return bless {}, 'TestLog' }
    $INC{'Slim/Utils/Log.pm'} = __FILE__;

    package Slim::Player::Client;
    our $client;
    sub getClient { return $client }
    $INC{'Slim/Player/Client.pm'} = __FILE__;

    package Slim::Player::Playlist;
    sub count { return scalar @{$_[0]->{queue}} }
    sub track { return $_[0]->{queue}->[$_[1]] }
    $INC{'Slim/Player/Playlist.pm'} = __FILE__;

    package Slim::Player::Source;
    our $playing_index = 0;
    our $playmode = 'play';
    sub playingSongIndex { return $playing_index }
    sub playmode { return $playmode }
    $INC{'Slim/Player/Source.pm'} = __FILE__;

    package Plugins::BetterCallBliss::PlaylistWriter;
    our $resolved_urls = [qw(file:///tail.flac file:///bridge.flac file:///target.flac)];
    sub resolved_tracks_for_job {
        return ({}, [@$resolved_urls]);
    }
    $INC{'Plugins/BetterCallBliss/PlaylistWriter.pm'} = __FILE__;
}

{
    package TestTrack;
    sub new { return bless {url => $_[1]}, $_[0] }
    sub url { return $_[0]->{url} }
}

{
    package TestRequest;
    sub isStatusError { return 0 }
}

{
    package TestClient;
    sub new {
        return bless {
            queue => [TestTrack->new('file:///tail.flac')],
            commands => [],
        }, $_[0];
    }
    sub id { return 'aa:bb:cc:dd:ee:ff' }
    sub name { return 'Wohnzimmer' }
    sub execute {
        my ($self, $command) = @_;
        push @{$self->{commands}}, $command;
        return bless {}, 'TestRequest';
    }
}

use lib "$FindBin::Bin/..";
require Plugins::BetterCallBliss::QueueWriter;

my $client = TestClient->new;
$Slim::Player::Client::client = $client;
my $job = {
    state => 'completed',
    artifact => {},
    route_to_track => 1,
    route_source => 'queue_end',
    route_start_url => 'file:///tail.flac',
    route_output_skip_source_count => 1,
    options => {
        queue_player_id => 'aa:bb:cc:dd:ee:ff',
        queue_action => 'replace',
        queue_start_playback => 1,
    },
};

my $result = Plugins::BetterCallBliss::QueueWriter::send_to_player($job);
is($result->{queue_action}, 'append', 'destination route always appends');
is($result->{track_count}, 2, 'queue-tail source prefix is omitted');
is($result->{player_name}, 'Wohnzimmer', 'result reports the locked player');
is(scalar @{$client->{commands}}, 1, 'route acceptance sends one queue command');
is($client->{commands}->[0]->[0], 'playlist', 'uses an LMS playlist command');
is($client->{commands}->[0]->[1], 'addtracks', 'route is appended');
is_deeply(
    $client->{commands}->[0]->[3],
    [qw(file:///bridge.flac file:///target.flac)],
    'only intermediates and destination are appended',
);

my $now_client = TestClient->new;
$now_client->{queue} = [
    TestTrack->new('file:///tail.flac'),
    TestTrack->new('file:///old-upcoming-1.flac'),
    TestTrack->new('file:///old-upcoming-2.flac'),
];
$Slim::Player::Client::client = $now_client;
$Slim::Player::Source::playing_index = 0;
my $now_job = {
    %$job,
    route_source => 'now_playing',
};
my $now_result = Plugins::BetterCallBliss::QueueWriter::send_to_player($now_job);
is($now_result->{queue_action}, 'replace_upcoming', 'now-playing route replaces the upcoming queue');
is($now_result->{track_count}, 2, 'now-playing source prefix is omitted');
is(scalar @{$now_client->{commands}}, 3, 'now-playing route removes two future entries and appends once');
is($now_client->{commands}->[0]->[2], 2, 'future queue entries are removed from the end first');
is($now_client->{commands}->[1]->[2], 1, 'the remaining upcoming entry is removed');
is($now_client->{commands}->[2]->[1], 'addtracks', 'generated suffix is appended after the preserved current song');
is_deeply(
    $now_client->{commands}->[2]->[3],
    [qw(file:///bridge.flac file:///target.flac)],
    'replacement contains only intermediates and destination',
);
is($now_result->{preserved_queue_prefix}, 1, 'currently playing queue prefix is preserved');
is($now_result->{removed_upcoming_count}, 2, 'result reports removed upcoming entries');

my $round_client = TestClient->new;
$round_client->{queue} = [
    TestTrack->new('file:///tail.flac'),
    TestTrack->new('file:///rejoin.flac'),
    TestTrack->new('file:///later.flac'),
];
$Slim::Player::Client::client = $round_client;
$Slim::Player::Source::playing_index = 0;
$Plugins::BetterCallBliss::PlaylistWriter::resolved_urls = [qw(
    file:///tail.flac file:///outward.flac file:///target.flac
    file:///return.flac file:///rejoin.flac
)];
my $round_job = {
    %$job,
    route_source => 'round_trip',
    route_rejoin_url => 'file:///rejoin.flac',
    route_output_skip_suffix_count => 1,
};
my $round_result = Plugins::BetterCallBliss::QueueWriter::send_to_player($round_job);
is($round_result->{queue_action}, 'play_next', 'round-trip route inserts before upcoming tracks');
is($round_result->{track_count}, 3, 'both anchors are omitted from the inserted excursion');
is(scalar @{$round_client->{commands}}, 1, 'round-trip route sends one non-destructive queue command');
is($round_client->{commands}->[0]->[1], 'inserttracks', 'round-trip route uses LMS play-next insertion');
is_deeply($round_client->{commands}->[0]->[3], [qw(
    file:///outward.flac file:///target.flac file:///return.flac
)], 'inserted excursion contains outward route, waypoint, and return route');
is($round_result->{removed_upcoming_count}, 0, 'round-trip route removes no existing queue entries');

$round_client->{queue}->[1] = TestTrack->new('file:///different-rejoin.flac');
my $round_before = scalar @{$round_client->{commands}};
eval { Plugins::BetterCallBliss::QueueWriter::send_to_player($round_job) };
like($@, qr/ROUTE_PREVIEW_STALE/, 'changed rejoin anchor refuses a round-trip route');
is(scalar @{$round_client->{commands}}, $round_before,
    'stale round-trip route sends no queue command');

$Slim::Player::Source::playmode = 'stop';
$Slim::Player::Client::client = $now_client;
$Plugins::BetterCallBliss::PlaylistWriter::resolved_urls = [qw(
    file:///tail.flac file:///bridge.flac file:///target.flac
)];
my $stopped_before = scalar @{$now_client->{commands}};
eval { Plugins::BetterCallBliss::QueueWriter::send_to_player($now_job) };
like($@, qr/ROUTE_PREVIEW_STALE/, 'stopped playback refuses a now-playing route');
is(scalar @{$now_client->{commands}}, $stopped_before, 'stopped route sends no queue command');
$Slim::Player::Source::playmode = 'play';

$now_client->{queue}->[0] = TestTrack->new('file:///different-current.flac');
my $now_before = scalar @{$now_client->{commands}};
eval { Plugins::BetterCallBliss::QueueWriter::send_to_player($now_job) };
like($@, qr/ROUTE_PREVIEW_STALE/, 'changed current song refuses a now-playing route');
is(scalar @{$now_client->{commands}}, $now_before, 'stale now-playing route sends no queue command');

$client->{queue} = [TestTrack->new('file:///different-tail.flac')];
$Slim::Player::Client::client = $client;
my $before = scalar @{$client->{commands}};
eval { Plugins::BetterCallBliss::QueueWriter::send_to_player($job) };
like($@, qr/ROUTE_PREVIEW_STALE/, 'changed queue tail refuses the stale preview');
is(scalar @{$client->{commands}}, $before, 'stale preview sends no queue command');
