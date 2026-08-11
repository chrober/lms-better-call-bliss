use strict;
use warnings;
use FindBin;
use Test::More tests => 9;

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
    sub playingSongIndex { return 0 }
    $INC{'Slim/Player/Source.pm'} = __FILE__;

    package Plugins::BetterCallBliss::PlaylistWriter;
    sub resolved_tracks_for_job {
        return ({}, [qw(file:///tail.flac file:///bridge.flac file:///target.flac)]);
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
    route_tail_url => 'file:///tail.flac',
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

$client->{queue} = [TestTrack->new('file:///different-tail.flac')];
my $before = scalar @{$client->{commands}};
eval { Plugins::BetterCallBliss::QueueWriter::send_to_player($job) };
like($@, qr/ROUTE_PREVIEW_STALE/, 'changed queue tail refuses the stale preview');
is(scalar @{$client->{commands}}, $before, 'stale preview sends no queue command');
