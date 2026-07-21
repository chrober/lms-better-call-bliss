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
        process => $process,
        result_path => $result_path,
        stderr_path => $stderr_path,
    };
    $log->info("job=$job_id stage=Optimizing playlist_id=$playlist_id");
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
    if (defined $exit && $exit == 0) {
        eval {
            my $payload = read_file($job->{result_path}, binmode => ':raw');
            $job->{artifact} = _json()->decode($payload);
        };
        if ($@ || !$job->{artifact}) {
            $job->{state} = 'failed';
            $job->{stage} = 'Failed';
            $job->{error} = 'Optimizer returned invalid JSON';
        } else {
            $job->{state} = 'completed';
            $job->{stage} = 'Completed';
        }
    } else {
        my $stderr = eval { read_file($job->{stderr_path}, binmode => ':raw') } || '';
        $stderr =~ s/\s+/ /g;
        $stderr = substr($stderr, 0, 400);
        $job->{state} = 'failed';
        $job->{stage} = 'Failed';
        $job->{error} = $stderr || 'Optimizer exited unsuccessfully';
    }
    $log->info("job=$job_id stage=$job->{stage}");
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
