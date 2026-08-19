package Plugins::BetterCallBliss::Jobs;

use strict;
use File::Basename qw(basename);
use File::Path qw(make_path);
use File::Slurp qw(read_file write_file);
use Scalar::Util qw(blessed);
use JSON::XS;
use Proc::Background;
use Time::HiRes qw(time);
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::Timers;
use Slim::Utils::Unicode;
use Slim::Player::Client;
use Slim::Player::Playlist;
use Plugins::BetterCallBliss::BlissCompatibility;
use Plugins::BetterCallBliss::BridgeResolver;
use Plugins::BetterCallBliss::CandidateInventory;
use Plugins::BetterCallBliss::JobOptions;
use Plugins::BetterCallBliss::LastFmEvidence;
use Plugins::BetterCallBliss::RequestBuilder;
use Plugins::BetterCallBliss::PlaylistWriter;
use Plugins::BetterCallBliss::QueueWriter;

my $log = Slim::Utils::Log::logger('plugin.bettercallbliss');
my $server_prefs = preferences('server');
my ($optimizer_binary, $job_root, $library_cache_root,
    $optimizer_supports_progress, $optimizer_supports_trusted_request);
my %jobs;
my $serial = 0;

sub init {
    $optimizer_binary = shift;
    $optimizer_supports_progress = shift ? 1 : 0;
    $optimizer_supports_trusted_request = shift ? 1 : 0;
    my $cache_root = ($server_prefs->get('cachedir') || Slim::Utils::Prefs::dir())
        . '/bettercallbliss';
    $job_root = $cache_root . '/jobs';
    $library_cache_root = $cache_root . '/library-cache';
    make_path($job_root) unless -d $job_root;
    make_path($library_cache_root) unless -d $library_cache_root;
    Plugins::BetterCallBliss::CandidateInventory::init($cache_root);
}

sub _json {
    return JSON::XS->new->utf8->canonical->pretty;
}

sub _write_json {
    my ($path, $value) = @_;
    write_file($path, {binmode => ':raw'}, _json()->encode($value));
}

sub _file_identity {
    my $path = shift;
    my @stat = stat($path);
    return unless @stat;
    return join(':', @stat[0, 1, 7, 9]);
}

sub _playlist_title {
    my $playlist = shift;
    my $url = eval { $playlist->url } || '';
    if ($url =~ /^file:/i) {
        my $path = Slim::Utils::Misc::pathFromFileURL($url);
        my $decoded = Slim::Utils::Unicode::utf8decode_locale($path || '');
        my $filename = basename($decoded || '');
        $filename =~ s/\.[^.]+$//;
        return $filename if length $filename;
    }
    return $playlist->title || $playlist->name;
}

sub _repeat_capacity_hint {
    my $job = shift;
    my $total = $job->{track_count};
    for my $rule (
        ['artist', $job->{options}->{artist_window}],
        ['album', $job->{options}->{album_window}],
    ) {
        my ($field, $window) = @$rule;
        next unless $window > 0;
        my %counts;
        for my $label (values %{$job->{labels}}) {
            my $value = $label->{$field} || '';
            $counts{$value}++ if length $value;
        }
        for my $value (sort keys %counts) {
            my $occurrences = $counts{$value};
            my $available = $total - $occurrences;
            my $required = $window * ($occurrences - 1);
            next if $available >= $required;
            my $kind = ucfirst($field);
            return "$kind repeat window $window cannot be satisfied: "
                . "$occurrences of $total tracks are '$value', but $required "
                . "other-$field separators are required and only $available are available. "
                . "The base route cannot satisfy this; reduce or disable the window "
                . "before using either Reorder only or Extend automatically.";
        }
    }
    return;
}

sub _extension_detail {
    my ($options, $job) = @_;
    my $mode = $options->{extension_mode} || 'none';
    return 'Additional tracks: none; this run only reorders the source set.'
        if $mode eq 'none';
    return 'Additional tracks: improve difficult transitions; may add up to '
        . (0 + ($options->{max_added_tracks} || 0))
        . ' tracks when transitions exceed the configured trigger.'
        if $mode eq 'automatic';
    return 'Additional tracks: make the playlist exactly '
        . (0 + ($options->{additional_track_count} || 0))
        . ' tracks longer.'
        if $mode eq 'exact_count';
    return 'Additional tracks: reach '
        . (0 + ($options->{target_track_count} || 0))
        . ' total tracks.'
        if $mode eq 'target_count';
    return 'Additional tracks: double the source playlist to '
        . (0 + ($options->{target_track_count} || 0))
        . ' total tracks.'
        if $mode eq 'double_count';
    return 'Additional tracks: extend the playlist against the complete source '
        . 'set as the fixed reference.'
        if $mode eq 'fixed_source_extension';
    return 'Destination route: choose between '
        . (0 + ($options->{route_min_intermediates} || 0))
        . ' and ' . (0 + ($options->{route_max_intermediates} || 0))
        . ' intermediate tracks automatically.'
        if $mode eq 'destination_route'
            && ($options->{route_length_policy} || '') eq 'automatic';
    return 'Destination route: use exactly '
        . (0 + ($options->{route_exact_intermediates} || 0))
        . ' intermediate tracks.'
        if $mode eq 'destination_route';
    return 'Additional tracks: ' . $mode;
}

sub _ordering_detail {
    my $options = shift || {};
    return ($options->{ordering_policy} || '') eq 'preserve_order'
        ? 'Ordering: preserve the source order; additions are placed around those anchors.'
        : 'Ordering: optimize source and added tracks together.';
}

sub _native_progress_detail {
    my $job = shift || {};
    my $progress = ref($job->{native_progress}) eq 'HASH'
        ? $job->{native_progress} : undef;
    return unless $progress && length($progress->{msg} || '');
    my $detail = 'Status: native optimizer - ' . $progress->{msg};
    if (defined $progress->{percent}) {
        $detail .= sprintf(' (%.0f%%', 0 + $progress->{percent});
        if (defined $progress->{current} && defined $progress->{total}) {
            $detail .= ', ' . (0 + $progress->{current}) . '/' . (0 + $progress->{total});
        }
        $detail .= ')';
    } elsif (defined $progress->{current} && defined $progress->{total}) {
        $detail .= ' (' . (0 + $progress->{current}) . '/' . (0 + $progress->{total}) . ')';
    }
    $detail .= '.' unless $detail =~ /[.!?]\s*$/;
    return $detail;
}
sub _running_phase_detail {
    my $job = shift || {};
    my $native = _native_progress_detail($job);
    return $native if $native;
    if (!$job->{process}) {
        if (($job->{lastfm_state} || '') eq 'preparing') {
            return 'Status: ' . $job->{lastfm_progress_message}
                if length($job->{lastfm_progress_message} || '');
            return 'Status: collecting optional Last.fm track and artist evidence.';
        }
        return 'Status: preparing the optimizer request.';
    }
    return 'Status: native optimizer is selecting additions and searching the final route.'
        if ($job->{native_command} || '') eq 'bridge';
    return 'Status: native optimizer is searching the best route through the source tracks.';
}

sub status_detail_lines {
    my $job = shift || {};
    my $options = ref($job->{options}) eq 'HASH' ? $job->{options} : {};
    my $state = $job->{state} || 'unknown';
    my @details;

    if ($state eq 'running') {
        push @details, _running_phase_detail($job);
    } elsif ($state eq 'completed') {
        my $added = 0 + ($job->{added_track_count} || 0);
        my $final = 0 + ($job->{final_track_count} || 0);
        push @details, "Status: preview completed; final playlist has $final tracks"
            . ($added ? " with $added additions." : '.');
    } elsif ($state eq 'failed') {
        my $code = $job->{error_code} || 'UNKNOWN_FAILURE';
        my $error = $job->{error} || $job->{native_message} || 'No detail available';
        push @details, "Status: failed with $code - $error";
    } elsif ($state eq 'cancelled') {
        push @details, 'Status: preview was cancelled.';
    } else {
        push @details, 'Status: ' . ($job->{stage} || $state);
    }

    push @details, 'Source: ' . (0 + ($job->{track_count} || 0)) . ' tracks.';
    push @details, _ordering_detail($options);
    push @details, _extension_detail($options, $job);

    push @details, sprintf(
        'Repeat windows: artist %d, album %d, track %d.',
        0 + ($options->{artist_window} || 0),
        0 + ($options->{album_window} || 0),
        0 + ($options->{track_window} || 0),
    );

    if (($options->{extension_mode} || 'none') ne 'none'
        && ref($job->{candidate_inventory}) eq 'HASH') {
        my $inventory = $job->{candidate_inventory};
        push @details, sprintf(
            'Candidate inventory: %d LMS-matched Bliss rows, %d excluded non-LMS rows, cache %s.',
            0 + ($inventory->{allowed_row_count} || 0),
            0 + ($inventory->{unmatched_row_count} || 0),
            $inventory->{cache_state} || 'unknown',
        );
    }

    if ($options->{lastfm_enabled}) {
        push @details, sprintf(
            'Last.fm evidence: %s; track guidance %d%%, artist guidance %d%%.',
            $job->{lastfm_state} || 'unknown',
            0 + ($options->{lastfm_track_guidance_percent} || 0),
            0 + ($options->{lastfm_artist_guidance_percent} || 0),
        );
    } else {
        push @details, 'Last.fm evidence: disabled for this job.';
    }

    if (ref($job->{native_performance}) eq 'HASH') {
        my $perf = $job->{native_performance};
        push @details, sprintf(
            'Native optimizer timing: %d ms total, database cache %s.',
            0 + ($perf->{total_ms} || 0),
            $perf->{database_cache} || 'unknown',
        );
    }

    return \@details;
}

sub status_detail {
    my $lines = status_detail_lines(shift);
    return join(' ', @$lines);
}

sub _preview_workflow_total {
    my $job = shift || {};
    my $options = ref($job->{options}) eq 'HASH' ? $job->{options} : {};
    # Compact live status is shown only after a preview job exists. Earlier
    # synchronous work such as source form handling and candidate-inventory
    # lookup must not consume visible step numbers.
    return ($options->{extension_mode} || 'none') ne 'none' ? 7 : 3;
}

sub _extension_optimizer_step {
    my $job = shift || {};
    my $stage = ref($job->{native_progress}) eq 'HASH'
        ? ($job->{native_progress}->{stage} || '') : '';
    return 2 if $stage eq 'route_search';
    return 3 if $stage eq 'candidate_preparation'
        || $stage eq 'frozen_reference'
        || $stage eq 'gap_candidate_scoring'
        || $stage eq 'extension_relevance_model'
        || $stage eq 'extension_candidate_scoring'
        || $stage eq 'extension_candidate_sorting'
        || $stage eq 'extension_semantic_guidance'
        || $stage eq 'extension_selection_pool';
    return 4 if $stage eq 'bridge_selection'
        || $stage eq 'extension_membership_selection';
    return 5 if $stage eq 'extension_route_placement'
        || $stage eq 'extension_route_search';
    return 6 if $stage eq 'completed';
    return 2 if $job->{process};
    return 1;
}

sub _compact_status_step {
    my $job = shift || {};
    my $total = _preview_workflow_total($job);
    my $state = $job->{state} || '';
    return ($total, $total) if $state eq 'completed' || $state eq 'cancelled';
    return ($total, $total) if $state eq 'failed';
    if ($state eq 'running') {
        return (_extension_optimizer_step($job), $total) if $total == 7;
        return (2, $total) if $job->{process} || ref($job->{native_progress}) eq 'HASH';
        return (1, $total);
    }
    return (1, $total);
}

sub compact_status {
    my $job = shift || {};
    my $lines = status_detail_lines($job);
    my $status = @$lines ? ($lines->[0] || '') : '';
    $status =~ s/^Status:\s*//;
    $status =~ s/^native optimizer\s*-\s*//i;
    return $status if $status =~ /^\[\d+\/\d+\]\s/;
    my ($step, $total) = _compact_status_step($job);
    return "[$step/$total] $status";
}

sub duration_text {
    my $seconds = int(shift || 0);
    $seconds = 0 if $seconds < 0;
    my $hours = int($seconds / 3600);
    my $minutes = int(($seconds % 3600) / 60);
    my $secs = $seconds % 60;
    return sprintf('%02d:%02d:%02d', $hours, $minutes, $secs);
}

sub start_text {
    my $epoch = int(shift || 0);
    return '' unless $epoch;
    my ($sec, $min, $hour, $mday, $mon, $year) = localtime($epoch);
    return sprintf('%d.%d.%04d %02d:%02d:%02d',
        $mday, $mon + 1, $year + 1900, $hour, $min, $sec);
}
sub _read_progress {
    my $job = shift || {};
    my $path = $job->{progress_path} || return;
    my $payload = eval { read_file($path, binmode => ':raw') } || return;
    my $progress = eval { _json()->decode($payload) } || return;
    return unless ref($progress) eq 'HASH';
    return unless ($progress->{program} || '') eq 'bliss-playlist-optimizer';
    $job->{native_progress} = $progress;
}
sub _launch_optimizer {
    my ($job, $built, $semantic_bundle) = @_;
    _write_json($job->{semantic_path}, $semantic_bundle);
    Plugins::BetterCallBliss::RequestBuilder::normalize_request_types(
        $built->{request},
    );
    _write_json($job->{request_path}, $built->{request});

    open my $result_fh, '>', $job->{result_path}
        or die "Could not open optimizer result: $!";
    open my $stderr_fh, '>', $job->{stderr_path}
        or die "Could not open optimizer log: $!";

    my @params = (
        $optimizer_binary, $job->{native_command}, '--request',
        $job->{request_path}, '--timings', '--cache-dir', $library_cache_root,
    );
    push @params, '--trusted-request' if $optimizer_supports_trusted_request;
    push @params, '--progress', $job->{progress_path}
        if $optimizer_supports_progress && $job->{progress_path};

    my $retie_stderr = !main::ISWINDOWS && tied(*STDERR) ? 1 : 0;
    untie *STDERR if $retie_stderr;
    my ($process, $launch_error);
    eval {
        $process = Proc::Background->new(
            {
                die_upon_destroy => 1,
                stdout => $result_fh,
                stderr => $stderr_fh,
            },
            @params,
        );
    };
    $launch_error = $@;
    tie *STDERR, 'Slim::Utils::Log::Trapper' if $retie_stderr;
    close $result_fh;
    close $stderr_fh;
    die "Could not start optimizer: $launch_error" if $launch_error;
    die "Could not start optimizer" unless $process;

    $job->{process} = $process;
    $job->{stage} = $job->{native_command} eq 'bridge'
        ? 'Optimizing and selecting additions' : 'Optimizing';
    Slim::Utils::Timers::setTimer(
        undef, time() + 0.5, sub { _poll($job->{id}) },
    );
}

sub _track_label {
    my $track = shift;
    return 'Unknown track' unless $track;
    my $artist = eval { $track->artistName } || 'Unknown Artist';
    my $title = eval { $track->title } || eval { $track->path } || 'Unknown Title';
    return "$artist - $title";
}

sub _new_job_context {
    my $job_id = sprintf('preview-%d-%04d', int(time()), ++$serial);
    my $dir = $job_root . '/' . $job_id;
    make_path($dir);
    return ($job_id, $dir, $dir . '/semantic-evidence.json');
}

sub _start_preview_from_built {
    my ($job_id, $dir, $semantic_path, $built, $fields) = @_;
    $fields ||= {};
    my $native_command = $built->{options}->{extension_mode} ne 'none'
        ? 'bridge' : 'route';
    my $database_identity = _file_identity($built->{capability}->{database});
    die "Could not stat bliss.db" unless $database_identity;
    $built->{request}->{artifacts}->{database}->{cache_identity}
        = $database_identity;
    my $candidate_inventory;
    if ($native_command eq 'bridge') {
        $candidate_inventory = Plugins::BetterCallBliss::CandidateInventory::prepare(
            $built->{capability}, $database_identity,
        );
        $built->{request}->{artifacts}->{local_candidate_inventory}
            = $candidate_inventory->{artifact};
    }
    my $request_path = $dir . '/request.json';
    my $result_path = $dir . '/result.json';
    my $stderr_path = $dir . '/stderr.log';
    my $progress_path = $dir . '/progress.json';
    my $lastfm_applies = $built->{options}->{lastfm_enabled}
        && $built->{options}->{extension_mode} ne 'none';
    my $lastfm_source_tracks = $built->{request}->{source_tracks};
    my $lastfm_source_count = 0 + ($fields->{lastfm_source_track_count} || 0);
    if ($lastfm_source_count > 0
        && $lastfm_source_count < @{$lastfm_source_tracks}) {
        my $first = @{$lastfm_source_tracks} - $lastfm_source_count;
        $lastfm_source_tracks = [
            @{$lastfm_source_tracks}[$first .. $#{$lastfm_source_tracks}]
        ];
    }

    my $playlist_title = defined $fields->{playlist_title}
        ? $fields->{playlist_title}
        : _playlist_title($built->{playlist});
    $jobs{$job_id} = {
        id => $job_id,
        state => 'running',
        stage => $lastfm_applies
            ? 'Preparing Last.fm track and artist evidence' : 'Preparing request',
        started_at => time(),
        playlist_id => 0 + ($fields->{playlist_id} || 0),
        playlist_title => $playlist_title,
        track_count => scalar @{$built->{request}->{source_tracks}},
        source_track_ids => [
            map { $_->{id} } @{$built->{request}->{source_tracks}}
        ],
        labels => $built->{labels},
        original_positions => $built->{original_positions},
        track_urls => $built->{track_urls},
        capability => $built->{capability},
        options => $built->{options},
        lastfm_state => $lastfm_applies ? 'preparing'
            : ($built->{options}->{lastfm_enabled} ? 'not_applicable' : 'disabled'),
        restart_count => $built->{request}->{route}->{search}->{restart_count},
        native_command => $native_command,
        database_identity => $database_identity,
        candidate_inventory => $candidate_inventory
            ? $candidate_inventory->{status} : undef,
        semantic_path => $semantic_path,
        request_path => $request_path,
        result_path => $result_path,
        stderr_path => $stderr_path,
        progress_path => $progress_path,
    };
    for my $key (qw(
        route_to_track quick_route auto_apply route_output_skip_source_count route_player_id
        route_target_track_id route_tail_track_id route_target_label route_tail_label
        route_tail_url route_source_context_count route_queue_count
        source_mode source_player_id source_player_name source_queue_scope
        source_queue_count source_queue_current_index source_queue_active
        source_queue_start_index source_queue_track_urls source_queue_current_url
    )) {
        $jobs{$job_id}->{$key} = $fields->{$key} if exists $fields->{$key};
    }

    my $effective = $built->{options};
    my $initial_stage = $jobs{$job_id}->{stage};
    my $source_log = $fields->{source_log} || ('playlist_id=' . ($fields->{playlist_id} || 0));
    $log->info(
        "job=$job_id stage=$initial_stage $source_log"
        . " ordering=$effective->{ordering_policy}"
        . " extension=$effective->{extension_mode}"
        . " algorithm=$effective->{algorithm}"
        . " seed_limit=$effective->{seed_limit}"
        . " learned_percent=$effective->{learned_percent}"
        . " repeat_artist=$effective->{artist_window}"
        . " repeat_album=$effective->{album_window}"
        . " repeat_track=$effective->{track_window}"
        . " restarts=$effective->{restart_count}"
        . " variation=$effective->{variation_percent}"
        . " generation_seed=$effective->{generation_seed}"
        . ($effective->{extension_mode} eq 'destination_route'
            ? " search_effort=$effective->{route_search_effort}"
                . " route_length_policy=$effective->{route_length_policy}"
                . " route_min_intermediates=$effective->{route_min_intermediates}"
                . " route_max_intermediates=$effective->{route_max_intermediates}"
                . " route_exact_intermediates=$effective->{route_exact_intermediates}"
            : '')
        . " lastfm=" . ($effective->{lastfm_enabled} ? 'enabled' : 'disabled')
        . " lastfm_track_guidance=$effective->{lastfm_track_guidance_percent}"
        . " lastfm_artist_guidance=$effective->{lastfm_artist_guidance_percent}"
        . ($effective->{extension_mode} ne 'none'
            ? ' shortlist_limit='
                . $built->{request}->{extension}->{shortlist_limit}
                . ' local_candidates='
                . $candidate_inventory->{status}->{allowed_row_count}
                . ' non_lms_bliss_rows='
                . $candidate_inventory->{status}->{unmatched_row_count}
                . ' inventory_cache='
                . $candidate_inventory->{status}->{cache_state}
            : '')
        . ($effective->{extension_mode} eq 'automatic'
            ? " max_added=$effective->{max_added_tracks}"
                . " trigger_percent=$effective->{trigger_percent}"
            : '')
        . (($effective->{extension_mode} eq 'fixed_source_extension'
                || $effective->{extension_mode} eq 'target_count'
                || $effective->{extension_mode} eq 'double_count')
            ? " target_tracks=$effective->{target_track_count}"
            : '')
        . " output_mode=$effective->{output_mode}"
        . ($effective->{output_mode} eq 'player_queue'
            ? " queue_player=$effective->{queue_player_id}"
                . " queue_action=$effective->{queue_action}"
                . " queue_start=$effective->{queue_start_playback}"
            : '')
    );
    $log->info(
        'job=' . $job_id
        . ' exact_count_requested=' . $effective->{additional_track_count}
        . ' max_tracks_per_gap=1 endpoints='
        . ($built->{request}->{extension}->{allow_opening_track}
            || $built->{request}->{extension}->{allow_closing_track}
            ? 'enabled' : 'disabled')
    ) if $effective->{extension_mode} eq 'exact_count'
        || $effective->{extension_mode} eq 'target_count'
        || $effective->{extension_mode} eq 'double_count';
    if (main::DEBUGLOG && $log->is_debug) {
        my $capability = $built->{capability};
        $log->debug(
            "job=$job_id request tracks=" . scalar(@{$built->{request}->{source_tracks}})
            . " command=$native_command"
            . " ordering=$effective->{ordering_policy}"
            . " extension=$effective->{extension_mode}"
            . " algorithm=$effective->{algorithm}"
            . " seed_limit=$effective->{seed_limit}"
            . " learned_percent=$effective->{learned_percent}"
            . " matrix=" . ($capability->{matrix_available} ? 'present' : 'absent')
            . " repeat_artist=$effective->{artist_window}"
            . " repeat_album=$effective->{album_window}"
            . " repeat_track=$effective->{track_window}"
            . " output_mode=$effective->{output_mode}"
        );
    }
    my $prepare_ok = eval {
        Plugins::BetterCallBliss::LastFmEvidence::prepare(
            $lastfm_applies, $lastfm_source_tracks, sub {
                my $bundle = shift;
                my $job = $jobs{$job_id} || return;
                my $provider = ref($bundle->{providers}) eq 'ARRAY'
                    ? $bundle->{providers}->[0] : undef;
                $job->{lastfm_state} = $provider
                    ? $provider->{state} : 'disabled'
                    if $lastfm_applies;
                my $launch_ok = eval {
                    _launch_optimizer($job, $built, $bundle);
                    1;
                };
                unless ($launch_ok) {
                    my $message = $@ || 'Could not prepare optimizer request';
                    $message =~ s/\s+/ /g;
                    $job->{state} = 'failed';
                    $job->{stage} = 'Failed';
                    $job->{finished_at} = time();
                    $job->{error_code} = 'OPTIMIZER_LAUNCH_FAILED';
                    $job->{error} = substr($message, 0, 400);
                    $job->{native_message} = $job->{error};
                    $log->error(
                        "job=$job_id stage=Failed code=OPTIMIZER_LAUNCH_FAILED"
                        . " message=$job->{error}"
                    );
                }
            },
            sub {
                my $progress = shift || {};
                my $job = $jobs{$job_id} || return;
                my $total = 0 + ($progress->{total} || 0);
                my $done = 0 + ($progress->{requests} || 0);
                my $edges = 0 + ($progress->{edges} || 0);
                my $successes = 0 + ($progress->{successes} || 0);
                my $failures = 0 + ($progress->{failures} || 0);
                my $message = $progress->{message}
                    || 'Collecting Last.fm track and artist evidence';
                if ($total) {
                    $message .= " ($done/$total requests, $successes ok";
                    $message .= ", $failures failed" if $failures;
                    $message .= ", $edges edges)";
                }
                $job->{lastfm_progress_message} = $message;
            },
        );
        1;
    };
    unless ($prepare_ok) {
        my $message = $@ || 'Could not start Last.fm evidence preparation';
        $message =~ s/\s+/ /g;
        my $job = $jobs{$job_id};
        $job->{lastfm_state} = 'failed';
        $log->warn(
            "job=$job_id Last.fm preparation failed; falling back to Bliss: "
            . substr($message, 0, 400)
        );
        my $fallback = {
            schema_version => 1,
            frozen_at => '1970-01-01T00:00:00Z',
            providers => [{
                provider => 'last.fm',
                dataset_or_algorithm =>
                    'LastMix track.getSimilar + artist.getSimilar',
                state => 'failed',
                request_count => 0,
                failure_count => 1,
                error_codes => ['EVIDENCE_PREPARATION_FAILED'],
            }],
            edges => [],
        };
        my $launch_ok = eval {
            _launch_optimizer($job, $built, $fallback);
            1;
        };
        unless ($launch_ok) {
            my $launch_message = $@ || 'Could not prepare optimizer request';
            $launch_message =~ s/\s+/ /g;
            $job->{state} = 'failed';
            $job->{stage} = 'Failed';
            $job->{finished_at} = time();
            $job->{error_code} = 'OPTIMIZER_LAUNCH_FAILED';
            $job->{error} = substr($launch_message, 0, 400);
        }
    }
    return $jobs{$job_id};
}

sub start_reorder_preview {
    my ($playlist_id, $options) = @_;
    die "Optimizer binary is unavailable"
        unless $optimizer_binary && -x $optimizer_binary;

    my ($job_id, $dir, $semantic_path) = _new_job_context();
    my $built = Plugins::BetterCallBliss::RequestBuilder::build_reorder_request(
        $playlist_id, $job_id, $semantic_path, $options,
    );
    return _start_preview_from_built(
        $job_id, $dir, $semantic_path, $built,
        {playlist_id => 0 + $playlist_id},
    );
}

sub start_queue_preview {
    my ($player_id, $scope, $options) = @_;
    die "Optimizer binary is unavailable"
        unless $optimizer_binary && -x $optimizer_binary;

    my ($job_id, $dir, $semantic_path) = _new_job_context();
    my $built = Plugins::BetterCallBliss::RequestBuilder::build_queue_request(
        $player_id, $scope, $job_id, $semantic_path, $options,
    );
    my $snapshot = $built->{queue_snapshot} || {};
    return _start_preview_from_built(
        $job_id, $dir, $semantic_path, $built,
        {
            playlist_id => 0,
            playlist_title => $built->{playlist_title},
            source_log => 'player_queue player=' . ($snapshot->{player_id} || $player_id)
                . ' scope=' . ($snapshot->{scope} || $scope || 'full')
                . ' captured_tracks=' . scalar(@{$built->{request}->{source_tracks} || []})
                . ' queue_count=' . (0 + ($snapshot->{queue_count} || 0))
                . ' current_index=' . (0 + ($snapshot->{current_index} || 0))
                . ' active=' . (($snapshot->{active} || 0) ? 1 : 0),
            source_mode => 'player_queue',
            source_player_id => $snapshot->{player_id} || $player_id,
            source_player_name => $snapshot->{player_name} || $player_id,
            source_queue_scope => $snapshot->{scope} || $scope || 'full',
            source_queue_count => 0 + ($snapshot->{queue_count} || 0),
            source_queue_current_index => 0 + ($snapshot->{current_index} || 0),
            source_queue_start_index => 0 + ($snapshot->{start_index} || 0),
            source_queue_active => ($snapshot->{active} || 0) ? 1 : 0,
            source_queue_track_urls => $snapshot->{track_urls} || [],
            source_queue_current_url => $snapshot->{current_url},
        },
    );
}
sub start_route_to_track_preview {
    my ($player_id, $target_track_id, $options) = @_;
    die "Optimizer binary is unavailable"
        unless $optimizer_binary && -x $optimizer_binary;
    $player_id = '' unless defined $player_id;
    $player_id =~ s/^\s+|\s+$//g;
    die "Choose the player whose queue should be used as the route start"
        unless length $player_id;

    my $client = Slim::Player::Client::getClient($player_id);
    die "The selected player is no longer connected" unless blessed($client);
    $client = $client->master if $client->can('master');
    my $count = eval { Slim::Player::Playlist::count($client) } || 0;
    die "The selected player queue is empty; play or queue a source track first"
        unless $count > 0;
    my $tail = Slim::Player::Playlist::track($client, $count - 1, 1, 0);
    die "Could not resolve the current queue tail to a local LMS track"
        unless $tail && !$tail->remote && $tail->can('id');

    die "Choose a destination track"
        unless defined $target_track_id && "$target_track_id" =~ /^\d+$/;
    my $target = Slim::Schema->find('Track', int($target_track_id));
    die "Destination track was not found in the LMS library"
        unless $target && !$target->remote && $target->can('id');
    die "The selected destination is already the current queue tail"
        if $tail->id == $target->id;

    my %route_options = (%{$options || {}});
    $route_options{ordering_policy} = 'preserve_order';
    $route_options{extension_mode} = 'destination_route';
    delete $route_options{addition_purpose};
    $route_options{output_mode} = 'player_queue';
    $route_options{queue_player_id} = $player_id;
    $route_options{queue_action} = 'append';
    $route_options{queue_start_playback} = 0;

    my $capability = Plugins::BetterCallBliss::BlissCompatibility::snapshot();
    my $normalized = Plugins::BetterCallBliss::JobOptions::normalize(
        $capability, \%route_options,
    );
    my $context_limit = $normalized->{seed_limit};
    $context_limit = $normalized->{artist_window}
        if $normalized->{artist_window} > $context_limit;
    $context_limit = $normalized->{album_window}
        if $normalized->{album_window} > $context_limit;
    $context_limit = $normalized->{track_window}
        if $normalized->{track_window} > $context_limit;
    $context_limit = 1 if $context_limit < 1;

    my @context;
    my $first = $count > $context_limit ? $count - $context_limit : 0;
    for my $index ($first .. $count - 1) {
        my $item = Slim::Player::Playlist::track($client, $index, 1, 0);
        if (!$item || $item->remote || !$item->can('id')) {
            @context = ();
            next;
        }
        if ($item->id == $target->id) {
            @context = ();
            next;
        }
        push @context, $item;
    }
    die "Could not capture an analyzed local queue tail for destination routing"
        unless @context && $context[-1]->id == $tail->id;

    my ($job_id, $dir, $semantic_path) = _new_job_context();
    my $tail_label = _track_label($tail);
    my $target_label = _track_label($target);
    my $title = "Bliss me there: $tail_label -> $target_label";
    my $built = Plugins::BetterCallBliss::RequestBuilder::build_sequence_request(
        $title, [@context, $target], $job_id, $semantic_path, $normalized,
    );
    return _start_preview_from_built(
        $job_id, $dir, $semantic_path, $built,
        {
            playlist_id => 0,
            playlist_title => $title,
            source_log => 'route_to_track player=' . ($client->id || $player_id)
                . ' tail_track=' . $tail->id . ' target_track=' . $target->id,
            route_to_track => 1,
            quick_route => $route_options{quick_route} ? 1 : 0,
            auto_apply => $route_options{auto_apply} ? 1 : 0,
            route_output_skip_source_count => scalar @context,
            route_player_id => $client->id || $player_id,
            route_tail_track_id => 0 + $tail->id,
            route_target_track_id => 0 + $target->id,
            route_tail_url => $tail->url,
            route_source_context_count => scalar @context,
            route_queue_count => 0 + $count,
            lastfm_source_track_count =>
                ($normalized->{seed_limit} + 1 < @context + 1)
                    ? $normalized->{seed_limit} + 1 : @context + 1,
            route_tail_label => $tail_label,
            route_target_label => $target_label,
        },
    );
}
sub _poll {
    my $job_id = shift;
    my $job = $jobs{$job_id} || return;
    return unless $job->{state} eq 'running';
    return unless $job->{process};

    if ($job->{process}->alive) {
        _read_progress($job);
        Slim::Utils::Timers::setTimer(
            undef, time() + 0.5, sub { _poll($job_id) },
        );
        return;
    }

    _read_progress($job);
    my $exit = $job->{process}->exit_code;
    $job->{finished_at} = time();
    delete $job->{process};
    my $payload = eval { read_file($job->{result_path}, binmode => ':raw') } || '';
    my $decode_error;
    if (length $payload) {
        eval { $job->{artifact} = _json()->decode($payload) };
        $decode_error = $@;
    }
    if ($job->{artifact}) {
        my $performance = $job->{artifact}->{performance};
        if (ref($performance) eq 'HASH') {
            $job->{native_performance} = $performance;
            if (main::DEBUGLOG && $log->is_debug) {
                my $stages = join(',', map {
                    ($_->{stage} || 'unknown') . ':' . (0 + ($_->{elapsed_ms} || 0))
                } @{$performance->{stages} || []});
                $log->debug(
                    "job=$job_id native_timing"
                    . " total_ms=" . (0 + ($performance->{total_ms} || 0))
                    . " database_cache=" . ($performance->{database_cache} || 'unknown')
                    . " stages=$stages"
                );
            }
        }
        my $normalized;
        my $normalize_ok = eval {
            if ($job->{options}->{extension_mode} ne 'none') {
                die "DATABASE_CHANGED: bliss.db changed while the preview was running\n"
                    unless (_file_identity($job->{capability}->{database}) || '')
                        eq $job->{database_identity};
                $normalized =
                    Plugins::BetterCallBliss::BridgeResolver::resolve_bridge_preview($job);
                for my $key (keys %$normalized) {
                    $job->{$key} = $normalized->{$key};
                }
            } else {
                die "RESULT_KIND_INVALID: Expected an adaptive route artifact\n"
                    unless ($job->{artifact}->{artifact_kind} || '')
                        eq 'adaptive-route-v1';
                $job->{final_track_ids} = [
                    @{$job->{artifact}->{selected_track_ids} || []}
                ];
                $job->{final_track_count} = scalar @{$job->{final_track_ids}};
                $job->{bridge_track_ids} = [];
                $job->{added_track_count} = 0;
                $job->{additions} = [];
            }
            1;
        };
        if ($normalize_ok) {
            $job->{state} = 'completed';
            $job->{stage} = 'Completed';
        } else {
            my $message = $@ || 'RESULT_NORMALIZATION_FAILED: Invalid optimizer result';
            $message =~ s/\s+/ /g;
            $message = substr($message, 0, 400);
            my ($code, $detail) = $message =~ /^([A-Z_]+):\s*(.*)$/;
            $job->{state} = 'failed';
            $job->{stage} = 'Failed';
            $job->{error_code} = $code || 'RESULT_NORMALIZATION_FAILED';
            $job->{error} = $detail || $message;
            $job->{native_message} = $job->{error};
        }
    } else {
        my $stderr = eval { read_file($job->{stderr_path}, binmode => ':raw') } || '';
        my $native = eval { _json()->decode($stderr) };
        $stderr =~ s/\s+/ /g;
        $stderr = substr($stderr, 0, 400);
        my $code = ref($native) eq 'HASH' && $native->{code}
            ? $native->{code}
            : (length $payload ? 'INVALID_RESULT' : 'OPTIMIZER_FAILED');
        my $message = ref($native) eq 'HASH' && $native->{message}
            ? $native->{message}
            : ($stderr || $decode_error || 'Optimizer produced no result');
        $message =~ s/\s+/ /g;
        $message = substr($message, 0, 400);
        my $ui_message = $message;
        if ($message =~ /source track '([^']+)'/) {
            my $label = $job->{labels}->{$1};
            $ui_message .= sprintf(
                ' (%s - %s)',
                $label->{artist} || 'Unknown Artist',
                $label->{title} || $1,
            ) if $label;
        }
        if ($code eq 'ROUTE_SEARCH_FAILED') {
            my $hint = _repeat_capacity_hint($job);
            $ui_message .= " $hint" if $hint;
        }
        $job->{state} = 'failed';
        $job->{stage} = 'Failed';
        $job->{error_code} = $code;
        $job->{error} = $ui_message;
        $job->{native_message} = $message;
    }
    if ($job->{state} eq 'failed') {
        my $code = $job->{error_code} || 'UNKNOWN_FAILURE';
        my $message = $job->{native_message} || $job->{error};
        my $elapsed_ms = int(1000 * ($job->{finished_at} - $job->{started_at}));
        $log->error(
            "job=$job_id stage=Failed code=$code exit="
            . (defined $exit ? $exit : 'unknown')
            . " elapsed_ms=$elapsed_ms"
            . " message=$message"
        );
        main::DEBUGLOG && $log->is_debug && $log->debug(
            "job=$job_id diagnostics source_count=$job->{track_count}"
        );
    } else {
        my $elapsed_ms = int(1000 * ($job->{finished_at} - $job->{started_at}));
        my $selected = $job->{artifact}->{selected_strategy} || 'adaptive';
        my $native = $job->{native_performance};
        my $native_summary = ref($native) eq 'HASH'
            ? " native_ms=" . (0 + ($native->{total_ms} || 0))
                . " database_cache=" . ($native->{database_cache} || 'unknown')
            : '';
        if ($job->{options}->{extension_mode} ne 'none') {
            my $fixed_source_extension_summary = '';
            my $destination_model_summary = '';
            if ($job->{options}->{extension_mode} eq 'destination_route') {
                my $model_selection =
                    (($job->{artifact}->{selection_preview} || {})
                        ->{route_quality} || {})->{model_selection} || {};
                my %direct_models = map {
                    (($_->{matrix_role} || '') => $_)
                } @{$model_selection->{direct_edge_models} || []};
                if (%direct_models) {
                    $destination_model_summary = ' destination_model='
                        . ($model_selection->{selected_matrix_role} || 'unknown');
                    for my $role ('static-weights', 'learned-matrix') {
                        next unless $direct_models{$role};
                        (my $label = $role) =~ s/-/_/g;
                        $destination_model_summary .= sprintf(
                            ' %s_direct_percentile=%.1f',
                            $label,
                            100 * ($direct_models{$role}
                                ->{source_relative_percentile} || 0),
                        );
                    }
                }
            }
            if ($job->{options}->{extension_mode} eq 'fixed_source_extension') {
                my $preview = $job->{artifact}->{selection_preview} || {};
                my $relevance = $preview->{relevance_summary} || {};
                my $route = $preview->{route_summary} || {};
                $fixed_source_extension_summary = sprintf(
                    ' relevance_min=%.4f relevance_mean=%.4f relevance_max=%.4f'
                        . ' route_worst=%.3f route_objective=%.3f proofs=passed',
                    0 + ($relevance->{minimum_distance} || 0),
                    0 + ($relevance->{mean_distance} || 0),
                    0 + ($relevance->{maximum_distance} || 0),
                    0 + ($route->{worst_transition} || 0),
                    0 + ($route->{objective} || 0),
                );
            }
            $log->info(
                "job=$job_id stage=Completed elapsed_ms=$elapsed_ms"
                . $native_summary
                . " source_tracks=$job->{track_count}"
                . " final_tracks=$job->{final_track_count}"
                . " added=$job->{added_track_count}"
                . " strategy=$selected"
                . " semantic_mode=$job->{artifact}->{semantic_mode}"
                . " lastfm_state=$job->{lastfm_state}"
                . $destination_model_summary
                . sprintf(
                    ' base_route_objective=%.3f',
                    $job->{artifact}->{selected_route_objective},
                )
                . $fixed_source_extension_summary
            );
        } else {
            my $candidate = $selected eq 'adaptive-arc'
                ? $job->{artifact}->{arc}
                : $job->{artifact}->{primary};
            $log->info(
                "job=$job_id stage=Completed elapsed_ms=$elapsed_ms"
                . $native_summary
                . " tracks=$job->{track_count} strategy=$selected"
                . " lastfm_state=$job->{lastfm_state}"
                . sprintf(
                    ' objective=%.3f worst_transition=%.3f',
                    $candidate->{objective},
                    $candidate->{worst_transition},
                )
            );
        }
    }

    if ($job->{state} eq 'completed' && $job->{auto_apply}) {
        my $sent = eval { send_to_queue($job_id, {}); };
        if ($sent) {
            $job->{stage} = 'Completed and sent to player queue';
        } else {
            my $error = $@ || 'QUEUE_SEND_FAILED: Unknown automatic queue output failure';
            $error =~ s/\s+/ /g;
            $job->{stage} = 'Completed; queue send failed';
            $log->error(
                "job=$job_id stage=AutomaticQueueSendFailed message="
                . substr($error, 0, 500)
            );
        }
    }
}

sub get {
    my $job_id = shift;
    _poll($job_id) if $jobs{$job_id} && $jobs{$job_id}->{state} eq 'running';
    return $jobs{$job_id};
}

sub all {
    _poll($_) for grep { $jobs{$_}->{state} eq 'running' } keys %jobs;
    return sort { $b->{started_at} <=> $a->{started_at} } values %jobs;
}


sub cancel {
    my $job_id = shift;
    my $job = $jobs{$job_id};
    die "JOB_NOT_FOUND: Preview job is no longer available\n" unless $job;
    return $job unless ($job->{state} || '') eq 'running';

    if ($job->{process}) {
        if ($job->{process}->alive) {
            eval { $job->{process}->die; };
            eval { $job->{process}->terminate; } if $@;
        } else {
            _poll($job_id);
            return $jobs{$job_id};
        }
    }

    delete $job->{process};
    $job->{state} = 'cancelled';
    $job->{stage} = 'Cancelled';
    $job->{finished_at} = time();
    $job->{error_code} = 'CANCELLED';
    $job->{error} = 'Preview cancelled by user. No playlist or player queue was changed.';
    $log->info("job=$job_id stage=Cancelled");
    return $job;
}

sub _clean_output_name {
    my $name = shift;
    $name = '' unless defined $name;
    $name =~ s/[\x00-\x1f]+/ /g;
    $name =~ s/^\s+|\s+$//g;
    die "INVALID_OUTPUT_NAME: Output playlist name is too long\n"
        if length($name) > 255;
    return $name;
}

sub _apply_output_options {
    my ($job, $mode, $params) = @_;
    $params ||= {};
    die "INVALID_OUTPUT_MODE: Unknown output target\n"
        unless $mode eq 'create_copy'
            || $mode eq 'overwrite_source'
            || $mode eq 'player_queue';

    my $options = $job->{options} ||= {};
    $options->{output_mode} = $mode;

    if ($mode eq 'create_copy') {
        my $name = exists $params->{output_name}
            ? $params->{output_name} : $options->{output_name};
        $options->{output_name} = _clean_output_name($name);
        $options->{output_name_generated} =
            length($options->{output_name} || '') ? 0 : 1;
    } elsif ($mode eq 'player_queue') {
        my $player_id = $job->{route_to_track}
            ? $job->{route_player_id}
            : (exists $params->{queue_player_id}
                ? $params->{queue_player_id} : $options->{queue_player_id});
        $player_id = '' unless defined $player_id;
        $player_id =~ s/^\s+|\s+$//g;
        die "PLAYER_REQUIRED: Choose a player for queue output\n"
            unless length $player_id;
        $options->{queue_player_id} = $player_id;

        my $action = $job->{route_to_track}
            ? 'append'
            : (exists $params->{queue_action}
                ? $params->{queue_action} : ($options->{queue_action} || 'replace'));
        die "INVALID_QUEUE_ACTION: Queue action must be Replace queue, Replace upcoming tracks, Append to queue, or Play next\n"
            unless $action eq 'replace'
                || $action eq 'replace_upcoming'
                || $action eq 'append'
                || $action eq 'play_next';
        $options->{queue_action} = $action;
        $options->{queue_start_playback} = $job->{route_to_track}
            ? 0
            : (exists $params->{queue_start_playback}
                ? ($params->{queue_start_playback} ? 1 : 0)
                : ($options->{queue_start_playback} ? 1 : 0));
    }
}
sub create_copy {
    my ($job_id, $params) = @_;
    my $job = get($job_id);
    die "JOB_NOT_FOUND: Preview job is no longer available\n" unless $job;
    die "PREVIEW_NOT_COMPLETE: Wait for the preview to complete\n"
        unless $job->{state} eq 'completed' && $job->{artifact};
    _apply_output_options($job, 'create_copy', $params);
    return $job->{persistence} if $job->{write_state}
        && $job->{write_state} eq 'completed' && $job->{persistence};
    die "CREATE_IN_PROGRESS: Playlist creation is already running\n"
        if $job->{write_state} && $job->{write_state} eq 'running';

    delete @$job{qw(write_error_code write_error)};
    $job->{write_state} = 'running';
    $job->{write_stage} = 'Creating';
    $log->info(
        "job=$job_id stage=Creating output_mode=create_copy"
    );
    my $result;
    eval {
        $result = Plugins::BetterCallBliss::PlaylistWriter::create_copy(
            $job, $job->{options}->{output_name},
            $job->{options}->{output_name_generated},
        );
    };
    if ($@ || !$result) {
        my $error = $@ || 'CREATE_FAILED: Unknown playlist creation failure';
        $error =~ s/\s+/ /g;
        $error = substr($error, 0, 500);
        my ($code, $message) = $error =~ /^([A-Z_]+):\s*(.*)$/;
        $job->{write_state} = 'failed';
        $job->{write_stage} = 'Create failed';
        $job->{write_error_code} = $code || 'CREATE_FAILED';
        $job->{write_error} = $message || $error;
        if ($job->{write_error_code} eq 'OUTPUT_EXISTS'
            || $job->{write_error_code} eq 'INVALID_OUTPUT_NAME') {
            $log->warn(
                "job=$job_id stage=CreateRejected"
                . " code=$job->{write_error_code}"
            );
        } else {
            $log->error(
                "job=$job_id stage=CreateFailed code=$job->{write_error_code}"
                . " message=$job->{write_error}"
            );
        }
        die "$job->{write_error_code}: $job->{write_error}\n";
    }

    $job->{write_state} = 'completed';
    $job->{write_stage} = 'Created and verified';
    $job->{persistence} = $result;
    $job->{options}->{output_name} = $result->{title};
    $log->info(
        "job=$job_id stage=CreatedAndVerified"
        . " playlist_id=$result->{playlist_id}"
        . " tracks=$result->{track_count}"
    );
    return $result;
}

sub overwrite_source {
    my ($job_id, $confirmed, $params) = @_;
    my $job = get($job_id);
    die "JOB_NOT_FOUND: Preview job is no longer available\n" unless $job;
    die "PREVIEW_NOT_COMPLETE: Wait for the preview to complete\n"
        unless $job->{state} eq 'completed' && $job->{artifact};
    _apply_output_options($job, 'overwrite_source', $params);
    die "OVERWRITE_NOT_CONFIRMED: Confirm that the source playlist should be overwritten\n"
        unless $confirmed;
    return $job->{persistence} if $job->{write_state}
        && $job->{write_state} eq 'completed' && $job->{persistence};
    die "OVERWRITE_IN_PROGRESS: Playlist overwrite is already running\n"
        if $job->{write_state} && $job->{write_state} eq 'running';

    delete @$job{qw(write_error_code write_error)};
    $job->{write_state} = 'running';
    $job->{write_stage} = 'Overwriting';
    $log->info(
        "job=$job_id stage=Overwriting output_mode=overwrite_source"
    );
    my $result;
    eval {
        $result = Plugins::BetterCallBliss::PlaylistWriter::overwrite_source($job);
    };
    if ($@ || !$result) {
        my $error = $@ || 'OVERWRITE_FAILED: Unknown playlist overwrite failure';
        $error =~ s/\s+/ /g;
        $error = substr($error, 0, 500);
        my ($code, $message) = $error =~ /^([A-Z_]+):\s*(.*)$/;
        $job->{write_state} = 'failed';
        $job->{write_stage} = 'Overwrite failed';
        $job->{write_error_code} = $code || 'OVERWRITE_FAILED';
        $job->{write_error} = $message || $error;
        $log->error(
            "job=$job_id stage=OverwriteFailed code=$job->{write_error_code}"
            . " message=$job->{write_error}"
        );
        die "$job->{write_error_code}: $job->{write_error}\n";
    }

    $job->{write_state} = 'completed';
    $job->{write_stage} = 'Overwritten and verified';
    $job->{persistence} = $result;
    $log->info(
        "job=$job_id stage=OverwrittenAndVerified"
        . " playlist_id=$result->{playlist_id}"
        . " tracks=$result->{track_count}"
    );
    return $result;
}

sub send_to_queue {
    my ($job_id, $params) = @_;
    my $job = get($job_id);
    die "JOB_NOT_FOUND: Preview job is no longer available\n" unless $job;
    die "PREVIEW_NOT_COMPLETE: Wait for the preview to complete\n"
        unless $job->{state} eq 'completed' && $job->{artifact};
    _apply_output_options($job, 'player_queue', $params);
    return $job->{persistence} if $job->{write_state}
        && $job->{write_state} eq 'completed' && $job->{persistence};
    die "QUEUE_SEND_IN_PROGRESS: Queue output is already running\n"
        if $job->{write_state} && $job->{write_state} eq 'running';

    delete @$job{qw(write_error_code write_error)};
    $job->{write_state} = 'running';
    $job->{write_stage} = 'Sending to player queue';
    $log->info(
        "job=$job_id stage=SendingToPlayerQueue"
        . " player=$job->{options}->{queue_player_id}"
        . " action=$job->{options}->{queue_action}"
        . " start=$job->{options}->{queue_start_playback}"
    );
    my $result;
    eval {
        $result = Plugins::BetterCallBliss::QueueWriter::send_to_player($job);
    };
    if ($@ || !$result) {
        my $error = $@ || 'QUEUE_SEND_FAILED: Unknown queue output failure';
        $error =~ s/\s+/ /g;
        $error = substr($error, 0, 500);
        my ($code, $message) = $error =~ /^([A-Z_]+):\s*(.*)$/;
        $job->{write_state} = 'failed';
        $job->{write_stage} = 'Queue send failed';
        $job->{write_error_code} = $code || 'QUEUE_SEND_FAILED';
        $job->{write_error} = $message || $error;
        $log->error(
            "job=$job_id stage=QueueSendFailed code=$job->{write_error_code}"
            . " message=$job->{write_error}"
        );
        die "$job->{write_error_code}: $job->{write_error}\n";
    }

    $job->{write_state} = 'completed';
    $job->{write_stage} = 'Sent to player queue';
    $job->{persistence} = $result;
    $log->info(
        "job=$job_id stage=SentToPlayerQueue"
        . " player=$result->{player_id}"
        . " action=$result->{queue_action}"
        . " tracks=$result->{track_count}"
        . " start=$result->{started_playback}"
    );
    return $result;
}

sub shutdown {
    for my $job (values %jobs) {
        if ($job->{process} && $job->{process}->alive) {
            $job->{process}->terminate;
        }
    }
    %jobs = ();
}

1;
