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
use Plugins::BlissEmAll::RequestBuilder;

my $log = Slim::Utils::Log::logger('plugin.blissemall');
my $server_prefs = preferences('server');
my ($optimizer_binary, $job_root);
my %jobs;
my $serial = 0;

sub init {
    $optimizer_binary = shift;
    $job_root = ($server_prefs->get('cachedir') || Slim::Utils::Prefs::dir())
        . '/blissemall/jobs';
    make_path($job_root) unless -d $job_root;
}

sub _json {
    return JSON::XS->new->utf8->canonical->pretty;
}

sub _write_json {
    my ($path, $value) = @_;
    write_file($path, {binmode => ':raw'}, _json()->encode($value));
}

sub _repeat_capacity_hint {
    my $job = shift;
    my $total = $job->{track_count};
    for my $rule (
        ['artist', $job->{capability}->{artist_window}],
        ['album', $job->{capability}->{album_window}],
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
                . "Reorder only cannot fix this; reduce the window or use bridge insertion.";
        }
    }
    return;
}

sub start_reorder_preview {
    my ($playlist_id) = @_;
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
        $playlist_id, $job_id, $semantic_path,
    );
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
            $optimizer_binary, 'route', '--request', $request_path,
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
        stage => 'Optimizing',
        started_at => time(),
        playlist_id => 0 + $playlist_id,
        playlist_title => $built->{playlist}->title || $built->{playlist}->name,
        track_count => scalar @{$built->{request}->{source_tracks}},
        labels => $built->{labels},
        original_positions => $built->{original_positions},
        capability => $built->{capability},
        restart_count => $built->{request}->{route}->{search}->{restart_count},
        process => $process,
        result_path => $result_path,
        stderr_path => $stderr_path,
    };
    $log->info("job=$job_id stage=Optimizing playlist_id=$playlist_id");
    if (main::DEBUGLOG && $log->is_debug) {
        my $capability = $built->{capability};
        $log->debug(
            "job=$job_id request tracks=" . scalar(@{$built->{request}->{source_tracks}})
            . " algorithm=$capability->{algorithm}"
            . " seed_limit=$capability->{seed_limit}"
            . " learned_percent=$capability->{learned_percent}"
            . " matrix=" . ($capability->{matrix_available} ? 'present' : 'absent')
            . " repeat_artist=$capability->{artist_window}"
            . " repeat_album=$capability->{album_window}"
            . " repeat_track=$capability->{track_window}"
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
        $job->{state} = 'completed';
        $job->{stage} = 'Completed';
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
        my $candidate = $selected eq 'adaptive-arc'
            ? $job->{artifact}->{arc}
            : $job->{artifact}->{primary};
        $log->info(
            "job=$job_id stage=Completed elapsed_ms=$elapsed_ms"
            . " tracks=$job->{track_count} strategy=$selected"
            . sprintf(
                ' objective=%.3f worst_transition=%.3f',
                $candidate->{objective},
                $candidate->{worst_transition},
            )
        );
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

sub shutdown {
    for my $job (values %jobs) {
        if ($job->{process} && $job->{process}->alive) {
            $job->{process}->terminate;
        }
    }
    %jobs = ();
}

1;
