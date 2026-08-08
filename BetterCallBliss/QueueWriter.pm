package Plugins::BetterCallBliss::QueueWriter;

use strict;
use Scalar::Util qw(blessed);
use Slim::Player::Client;
use Slim::Player::Playlist;
use Slim::Utils::Log;
use Plugins::BetterCallBliss::PlaylistWriter;

my $log = Slim::Utils::Log::logger('plugin.bettercallbliss');

sub _fail {
    my ($code, $message) = @_;
    die "$code: $message\n";
}

sub _player_label {
    my $client = shift;
    return eval { $client->name } || eval { $client->id } || 'selected player';
}

sub _execute {
    my ($client, $command) = @_;
    my $request = $client->execute($command);
    _fail('QUEUE_COMMAND_FAILED', 'LMS did not accept the queue command')
        unless $request;
    _fail('QUEUE_COMMAND_REJECTED', 'LMS rejected the queue command')
        if $request->can('isStatusError') && $request->isStatusError;
    return $request;
}

sub send_to_player {
    my $job = shift;
    _fail('INVALID_JOB', 'A completed preview is required')
        unless $job && $job->{state} eq 'completed' && $job->{artifact};

    my $options = $job->{options} || {};
    my $player_id = $options->{queue_player_id} || '';
    _fail('PLAYER_REQUIRED', 'Choose a player for queue output')
        unless length $player_id;

    my $client = Slim::Player::Client::getClient($player_id);
    _fail('PLAYER_NOT_FOUND', 'The selected player is no longer connected')
        unless blessed($client);
    $client = $client->master if $client->can('master');

    my (undef, $urls) =
        Plugins::BetterCallBliss::PlaylistWriter::resolved_tracks_for_job($job);
    _fail('EMPTY_RESULT', 'The preview did not produce any tracks')
        unless $urls && @$urls;

    my $skip = 0 + ($job->{route_output_skip_source_count} || 0);
    if ($skip > 0) {
        _fail('EMPTY_RESULT', 'The generated route contains no tracks to send')
            if $skip >= @$urls;
        $urls = [@$urls[$skip .. $#$urls]];
    }

    my $action = $options->{queue_action} || 'replace';
    my $start = $options->{queue_start_playback} ? 1 : 0;
    my $command;
    if ($action eq 'replace') {
        _execute($client, ['playlist', 'clear']);
        $command = ['playlist', 'addtracks', 'listRef', $urls];
    } elsif ($action eq 'append') {
        $command = ['playlist', 'addtracks', 'listRef', $urls];
    } elsif ($action eq 'play_next') {
        $command = ['playlist', 'inserttracks', 'listRef', $urls];
    } else {
        _fail('INVALID_QUEUE_ACTION', 'Unknown queue action');
    }
    _execute($client, $command);

    if ($start) {
        if ($action eq 'replace') {
            _execute($client, ['playlist', 'jump', 0]);
        } else {
            _execute($client, ['play']);
        }
    }

    my $queue_count = eval { Slim::Player::Playlist::count($client) };
    $log->info(
        'sent preview job=' . ($job->{id} || 'unknown')
        . ' to player=' . ($client->id || $player_id)
        . " action=$action start=$start tracks=" . scalar(@$urls)
        . ($skip ? " skipped_source_anchors=$skip" : '')
    );

    return {
        output_mode => 'player_queue',
        player_id => $client->id || $player_id,
        player_name => _player_label($client),
        queue_action => $action,
        started_playback => $start,
        track_count => scalar @$urls,
        queue_count => defined $queue_count ? 0 + $queue_count : undef,
    };
}

1;
