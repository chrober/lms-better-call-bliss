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

sub _queue_urls {
    my $client = shift;
    my (undef, $count) = _current_queue_index($client);
    my @urls;
    for my $index (0 .. $count - 1) {
        my $track = eval { Slim::Player::Playlist::track($client, $index, 1, 0) };
        push @urls, $track ? $track->url : undef;
    }
    return \@urls;
}

sub _url_position {
    my ($urls, $wanted) = @_;
    return undef unless defined $wanted && ref($urls) eq 'ARRAY';
    for my $index (0 .. $#$urls) {
        return $index if defined $urls->[$index] && $urls->[$index] eq $wanted;
    }
    return undef;
}

sub _live_current_url {
    my ($client, $current) = @_;
    my $track = eval { Slim::Player::Playlist::track($client, $current, 1, 0) };
    return $track ? $track->url : undef;
}

sub _reconciled_same_player_upcoming_urls {
    my ($job, $client, $urls) = @_;
    return ($urls, {}) unless ($job->{source_mode} || '') eq 'player_queue';
    return ($urls, {}) unless ($job->{source_player_id} || '') eq (eval { $client->id } || '');
    return ($urls, {}) if ($job->{source_queue_scope} || '') eq 'upcoming_only';

    my ($current, $count) = _current_queue_index($client);
    _fail(
        'QUEUE_SNAPSHOT_CHANGED',
        'The selected player queue is empty; rerun the preview or choose Replace queue/Append to queue.',
    ) unless $count > 0;

    my $live_current_url = _live_current_url($client, $current);
    _fail(
        'QUEUE_SNAPSHOT_CHANGED',
        'The current queue item is no longer a local LMS track; rerun the preview or choose Replace queue/Append to queue.',
    ) unless defined $live_current_url;

    my $captured_urls = ref($job->{source_queue_track_urls}) eq 'ARRAY'
        ? $job->{source_queue_track_urls}
        : [];
    my $captured_position = _url_position($captured_urls, $live_current_url);
    _fail(
        'QUEUE_SNAPSHOT_CHANGED',
        'The player advanced or changed to a track outside the preview snapshot; rerun the preview or choose Replace queue/Append to queue.',
    ) unless defined $captured_position;

    my $live_urls = _queue_urls($client);
    my $remaining_live = $count - $current;
    my $remaining_captured = @$captured_urls - $captured_position;
    my $compare = $remaining_live < $remaining_captured
        ? $remaining_live : $remaining_captured;
    for my $offset (0 .. $compare - 1) {
        my $live = $live_urls->[$current + $offset];
        my $captured = $captured_urls->[$captured_position + $offset];
        next if defined $live && defined $captured && $live eq $captured;
        _fail(
            'QUEUE_SNAPSHOT_CHANGED',
            'The selected player queue changed since this preview was created; rerun the preview or choose Replace queue/Append to queue.',
        );
    }

    my $result_position = _url_position($urls, $live_current_url);
    _fail(
        'QUEUE_PREVIEW_NO_LONGER_ALIGNED',
        'The currently playing track is not present in the accepted preview result; rerun the preview or choose Replace queue/Append to queue.',
    ) unless defined $result_position;

    my $first_upcoming = $result_position + 1;
    _fail(
        'EMPTY_RESULT',
        'The accepted preview contains no tracks after the currently playing item.',
    ) if $first_upcoming > $#$urls;

    my @trimmed = @$urls[$first_upcoming .. $#$urls];
    return (\@trimmed, {
        reconciled_same_player => 1,
        live_current_index => 0 + $current,
        preview_current_position => 0 + $result_position,
        trimmed_preview_prefix => 0 + $first_upcoming,
    });
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

    if ($job->{route_to_track}) {
        my (undef, $live_count) = _current_queue_index($client);
        _fail(
            'ROUTE_PREVIEW_STALE',
            'The player queue is now empty. Recalculate the route from the current queue.',
        ) unless $live_count > 0;
        my $live_tail = eval {
            Slim::Player::Playlist::track($client, $live_count - 1, 1, 0)
        };
        my $live_tail_url = $live_tail ? $live_tail->url : undef;
        _fail(
            'ROUTE_PREVIEW_STALE',
            'The player queue tail changed while this route was being reviewed. Recalculate Bliss me there from the new queue tail.',
        ) unless defined $live_tail_url
            && defined $job->{route_tail_url}
            && $live_tail_url eq $job->{route_tail_url};
    }

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

    my $action = $job->{route_to_track}
        ? 'append' : ($options->{queue_action} || 'replace');
    my $start = $job->{route_to_track} ? 0 : ($options->{queue_start_playback} ? 1 : 0);
    my $command;
    my $queue_edit = {};
    my $reconcile = {};
    if ($action eq 'replace') {
        _execute($client, ['playlist', 'clear']);
        $command = ['playlist', 'addtracks', 'listRef', $urls];
        _execute($client, $command);
    } elsif ($action eq 'replace_upcoming') {
        ($urls, $reconcile) = _reconciled_same_player_upcoming_urls($job, $client, $urls);
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
        . ($reconcile->{reconciled_same_player}
            ? " reconciled_same_player=1 trimmed_preview_prefix="
                . (0 + ($reconcile->{trimmed_preview_prefix} || 0))
                . " live_current_index="
                . (0 + ($reconcile->{live_current_index} || 0))
            : '')
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
        reconciled_same_player => $reconcile->{reconciled_same_player} ? 1 : 0,
        trimmed_preview_prefix => 0 + ($reconcile->{trimmed_preview_prefix} || 0),
    };
}

1;
