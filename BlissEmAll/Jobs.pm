package Plugins::BlissEmAll::Jobs;

use strict;
use File::Path qw(make_path);
use File::Slurp qw(read_file write_file);
use JSON::XS;
use Proc::Background;
use Time::HiRes qw(time);
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Timers;
use Plugins::BlissEmAll::BridgeResolver;
use Plugins::BlissEmAll::RequestBuilder;
use Plugins::BlissEmAll::PlaylistWriter;

my $log = Slim::Utils::Log::logger('plugin.blissemall');
my $server_prefs = preferences('server');
my ($optimizer_binary, $job_root, $library_cache_root);
my %jobs;
my $serial = 0;

sub init {
    $optimizer_binary = shift;
    $job_root = ($server_prefs->get('cachedir') || Slim::Utils::Prefs::dir())
        . '/blissemall/jobs';
    $library_cache_root = ($server_prefs->get('cachedir') || Slim::Utils::Prefs::dir())
        . '/blissemall/library-cache';
    make_path($job_root) unless -d $job_root;
    make_path($library_cache_root) unless -d $library_cache_root;
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

sub start_reorder_preview {
    my ($playlist_id, $options) = @_;
    die "Optimizer binary is unavailable"
        unless $optimizer_binary && -x $optimizer_binary;

    my $job_id = sprintf('preview-%d-%04d', int(time()), ++$serial);
    my $dir = $job_root . '/' . $job_id;
    make_path($dir);
    my $semantic_path = $dir . '/semantic-evidence.json';
    _write_json($semantic_path, {
        schema_version => 1,
        frozen_at => '1970-01-01T00:00:00Z',
        providers => [],
        edges => [],
    });

    my $built = Plugins::BlissEmAll::RequestBuilder::build_reorder_request(
        $playlist_id, $job_id, $semantic_path, $options,
    );
    my $native_command = $built->{options}->{extension_mode} ne 'none'
        ? 'bridge' : 'route';
    my $database_identity = _file_identity($built->{capability}->{database});
    die "Could not stat bliss.db" unless $database_identity;
    $built->{request}->{artifacts}->{database}->{cache_identity}
        = $database_identity;
    my $request_path = $dir . '/request.json';
    my $result_path = $dir . '/result.json';
    my $stderr_path = $dir . '/stderr.log';
    _write_json($request_path, $built->{request});

    open my $result_fh, '>', $result_path
        or die "Could not open optimizer result: $!";
    open my $stderr_fh, '>', $stderr_path
        or die "Could not open optimizer log: $!";

    # LMS ties STDERR to its logger. Proc::Background cannot clone a tied
    # handle while redirecting a child, so follow the scanner's launch pattern.
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
            $optimizer_binary, $native_command, '--request', $request_path,
            '--timings', '--cache-dir', $library_cache_root,
        );
    };
    $launch_error = $@;
    tie *STDERR, 'Slim::Utils::Log::Trapper' if $retie_stderr;
    close $result_fh;
    close $stderr_fh;
    die "Could not start optimizer: $launch_error" if $launch_error;
    die "Could not start optimizer" unless $process;

    $jobs{$job_id} = {
        id => $job_id,
        state => 'running',
        stage => $native_command eq 'bridge'
            ? 'Optimizing and selecting additions' : 'Optimizing',
        started_at => time(),
        playlist_id => 0 + $playlist_id,
        playlist_title => $built->{playlist}->title || $built->{playlist}->name,
        track_count => scalar @{$built->{request}->{source_tracks}},
        source_track_ids => [
            map { $_->{id} } @{$built->{request}->{source_tracks}}
        ],
        labels => $built->{labels},
        original_positions => $built->{original_positions},
        track_urls => $built->{track_urls},
        capability => $built->{capability},
        options => $built->{options},
        restart_count => $built->{request}->{route}->{search}->{restart_count},
        native_command => $native_command,
        database_identity => $database_identity,
        process => $process,
        result_path => $result_path,
        stderr_path => $stderr_path,
    };
    my $effective = $built->{options};
    $log->info(
        "job=$job_id stage=Optimizing playlist_id=$playlist_id"
        . " extension=$effective->{extension_mode}"
        . " algorithm=$effective->{algorithm}"
        . " seed_limit=$effective->{seed_limit}"
        . " learned_percent=$effective->{learned_percent}"
        . " repeat_artist=$effective->{artist_window}"
        . " repeat_album=$effective->{album_window}"
        . " repeat_track=$effective->{track_window}"
        . " restarts=$effective->{restart_count}"
        . ($effective->{extension_mode} eq 'automatic'
            ? " max_added=$effective->{max_added_tracks}"
                . " trigger_percent=$effective->{trigger_percent}"
            : '')
        . " output_mode=$effective->{output_mode}"
    );
    $log->info(
        'job=' . $job_id
        . ' exact_count_requested=' . $effective->{additional_track_count}
        . ' max_tracks_per_gap=1 endpoints=disabled'
    ) if $effective->{extension_mode} eq 'exact_count';
    if (main::DEBUGLOG && $log->is_debug) {
        my $capability = $built->{capability};
        $log->debug(
            "job=$job_id request tracks=" . scalar(@{$built->{request}->{source_tracks}})
            . " command=$native_command"
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
    Slim::Utils::Timers::setTimer(undef, time() + 0.5, sub { _poll($job_id) });
    return $jobs{$job_id};
}

sub _poll {
    my $job_id = shift;
    my $job = $jobs{$job_id} || return;
    return unless $job->{state} eq 'running';

    if ($job->{process}->alive) {
        Slim::Utils::Timers::setTimer(
            undef, time() + 0.5, sub { _poll($job_id) },
        );
        return;
    }

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
                    Plugins::BlissEmAll::BridgeResolver::resolve_bridge_preview($job);
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
            $log->info(
                "job=$job_id stage=Completed elapsed_ms=$elapsed_ms"
                . $native_summary
                . " source_tracks=$job->{track_count}"
                . " final_tracks=$job->{final_track_count}"
                . " added=$job->{added_track_count}"
                . " strategy=$selected"
                . " semantic_mode=$job->{artifact}->{semantic_mode}"
                . sprintf(
                    ' base_route_objective=%.3f',
                    $job->{artifact}->{selected_route_objective},
                )
            );
        } else {
            my $candidate = $selected eq 'adaptive-arc'
                ? $job->{artifact}->{arc}
                : $job->{artifact}->{primary};
            $log->info(
                "job=$job_id stage=Completed elapsed_ms=$elapsed_ms"
                . $native_summary
                . " tracks=$job->{track_count} strategy=$selected"
                . sprintf(
                    ' objective=%.3f worst_transition=%.3f',
                    $candidate->{objective},
                    $candidate->{worst_transition},
                )
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

sub create_copy {
    my $job_id = shift;
    my $job = get($job_id);
    die "JOB_NOT_FOUND: Preview job is no longer available\n" unless $job;
    die "PREVIEW_NOT_COMPLETE: Wait for the preview to complete\n"
        unless $job->{state} eq 'completed' && $job->{artifact};
    die "OUTPUT_MODE_MISMATCH: This job requested Overwrite source\n"
        unless $job->{options}->{output_mode} eq 'create_copy';
    return $job->{persistence} if $job->{write_state}
        && $job->{write_state} eq 'completed' && $job->{persistence};
    die "CREATE_IN_PROGRESS: Playlist creation is already running\n"
        if $job->{write_state} && $job->{write_state} eq 'running';

    $job->{write_state} = 'running';
    $job->{write_stage} = 'Creating';
    $log->info(
        "job=$job_id stage=Creating output_mode=create_copy"
    );
    my $result;
    eval {
        $result = Plugins::BlissEmAll::PlaylistWriter::create_copy(
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

sub shutdown {
    for my $job (values %jobs) {
        if ($job->{process} && $job->{process}->alive) {
            $job->{process}->terminate;
        }
    }
    %jobs = ();
}

1;
