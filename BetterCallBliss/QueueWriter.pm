package Plugins::BetterCallBliss::QueueWriter;

use strict;
use Scalar::Util qw(blessed);
use Slim::Player::Client;
use Slim::Player::Playlist;
use Slim::Player::Source;
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

sub _current_queue_index {
    my $client = shift;
    my $count = eval { Slim::Player::Playlist::count($client) } || 0;
    return (0, 0) unless $count > 0;
    my $index = eval { Slim::Player::Source::playingSongIndex($client) };
    $index = 0 unless defined $index && "$index" =~ /^\d+$/;
    $index = 0 if $index < 0;
    $index = $count - 1 if $index >= $count;
    return (0 + $index, 0 + $count);
}

sub _replace_upcoming_tracks {
    my ($client, $urls) = @_;
    my ($current, $count) = _current_queue_index($client);
    my $removed = 0;
    if ($count > 0) {
        for (my $index = $count - 1; $index > $current; $index--) {
            _execute($client, ['playlist', 'delete', $index]);
            $removed++;
        }
    }
    _execute($client, ['playlist', 'addtracks', 'listRef', $urls]);
    return {
        preserved_count => $count > 0 ? $current + 1 : 0,
        removed_count => $removed,
    };
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
    if ($action eq 'replace_upcoming'
        && ($job->{source_mode} || '') eq 'player_queue'
        && ($job->{source_player_id} || '') eq ($client->id || $player_id)
        && ($job->{source_queue_scope} || '') ne 'upcoming_only') {
        _fail(
            'QUEUE_ACTION_NEEDS_UPCOMING_SOURCE',
            'Replace upcoming tracks on the same player requires a preview built from Use only upcoming tracks, otherwise the current song could be duplicated. Choose Replace queue or rerun with the upcoming-only queue snapshot.',
        );
    }
    my $start = $options->{queue_start_playback} ? 1 : 0;
    my $command;
    my $queue_edit = {};
    if ($action eq 'replace') {
        _execute($client, ['playlist', 'clear']);
        $command = ['playlist', 'addtracks', 'listRef', $urls];
        _execute($client, $command);
    } elsif ($action eq 'replace_upcoming') {
        $queue_edit = _replace_upcoming_tracks($client, $urls);
    } elsif ($action eq 'append') {
        $command = ['playlist', 'addtracks', 'listRef', $urls];
        _execute($client, $command);
    } elsif ($action eq 'play_next') {
        $command = ['playlist', 'inserttracks', 'listRef', $urls];
        _execute($client, $command);
    } else {
        _fail('INVALID_QUEUE_ACTION', 'Unknown queue action');
    }

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
        . ($action eq 'replace_upcoming'
            ? " preserved_queue_prefix=" . (0 + ($queue_edit->{preserved_count} || 0))
                . " removed_upcoming=" . (0 + ($queue_edit->{removed_count} || 0))
            : '')
    );

    return {
        output_mode => 'player_queue',
        player_id => $client->id || $player_id,
        player_name => _player_label($client),
        queue_action => $action,
        started_playback => $start,
        track_count => scalar @$urls,
        queue_count => defined $queue_count ? 0 + $queue_count : undef,
        preserved_queue_prefix => 0 + ($queue_edit->{preserved_count} || 0),
        removed_upcoming_count => 0 + ($queue_edit->{removed_count} || 0),
    };
}

1;
