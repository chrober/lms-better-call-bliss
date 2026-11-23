use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use File::Temp qw(tempdir);
use Fcntl qw(:flock);
use Test::More;

BEGIN {
    package main;
    sub ISWINDOWS () { 0 }
    sub DEBUGLOG () { 0 }
    sub INFOLOG () { 0 }
    package HistoryTestPrefs;
    our $cache;
    our %values;
    sub get { $_[1] eq 'cachedir' ? $cache : $values{$_[1]} }
    package Slim::Utils::Prefs;
    sub preferences { bless {}, 'HistoryTestPrefs' }
    sub import { no strict 'refs'; *{caller() . '::preferences'} = \&preferences }
    sub dir { $HistoryTestPrefs::cache }
    package Slim::Utils::Log;
    sub logger { bless {}, 'HistoryTestLog' }
    package HistoryTestLog;
    sub info {} sub warn {} sub error {} sub debug {} sub is_debug { 0 }
    package Slim::Utils::Timers;
    our @callbacks;
    sub setTimer { push @callbacks, $_[2] }
    package Slim::Utils::Strings;
    sub string { return shift }
    package Slim::Music::Import;
    our $scanning = 0;
    sub stillScanning { return $scanning }
    package HistoryTestProcess;
    sub alive { $_[0]->{alive} }
    sub die { 0 }
    sub exit_code { 0 }
    package Plugins::BetterCallBliss::ScanSnapshotProcess;
    our $next;
    sub start { return $next }
    package HistoryTestSnapshotProcess;
    sub poll { return $_[0]->{status} }
    sub cancel { $_[0]->{cancelled}++; $_[0]->{status} = {state => 'cancelled'} }
    sub cleanup { $_[0]->{cleaned}++ }
    sub pid { 987654 }
    package Plugins::BetterCallBliss::CandidateInventory;
    sub init {} sub shutdown {}
    sub _register_shared_bundle { '/test/shared-inventory' }
    our @snapshot_cancellations;
    our @snapshot_preparations;
    sub cancel_snapshot_preparation { push @snapshot_cancellations, $_[0] }
    sub prepare_snapshots_async { push @snapshot_preparations, [@_]; return {snapshot_task => 1} }
    package Plugins::BetterCallBliss::UserNotification;
    sub route_failure {}
    package Plugins::BetterCallBliss::GuidanceProviderDiscovery;
    sub dispatch_native_diagnostics {}
    package Plugins::BetterCallBliss::CandidateGuidance;
    sub native_provider_state { undef }
    for my $module (qw(
        Proc/Background.pm Slim/Music/Import.pm Slim/Utils/Log.pm
        Slim/Utils/Misc.pm Slim/Utils/Prefs.pm Slim/Utils/Timers.pm Slim/Utils/Strings.pm
        Slim/Utils/Unicode.pm Slim/Player/Client.pm Slim/Player/Playlist.pm
        Slim/Player/Source.pm Plugins/BetterCallBliss/BlissCompatibility.pm
        Plugins/BetterCallBliss/BridgeResolver.pm Plugins/BetterCallBliss/CandidateInventory.pm
        Plugins/BetterCallBliss/CandidateGuidance.pm Plugins/BetterCallBliss/DurationTarget.pm
        Plugins/BetterCallBliss/GuidanceProviderDiscovery.pm Plugins/BetterCallBliss/AlbumDestination.pm
        Plugins/BetterCallBliss/JobOptions.pm Plugins/BetterCallBliss/LogDiagnostics.pm
        Plugins/BetterCallBliss/RequestBuilder.pm Plugins/BetterCallBliss/PlaylistWriter.pm
        Plugins/BetterCallBliss/QueueWriter.pm Plugins/BetterCallBliss/RepeatConflicts.pm
        Plugins/BetterCallBliss/RouteMode.pm Plugins/BetterCallBliss/UserNotification.pm
        Plugins/BetterCallBliss/ScanSnapshotProcess.pm
    )) { $INC{$module} = __FILE__ }
}

require "$FindBin::Bin/../BetterCallBliss/JobHistory.pm";
$INC{'Plugins/BetterCallBliss/JobHistory.pm'} = __FILE__;
require "$FindBin::Bin/../BetterCallBliss/Jobs.pm";

$HistoryTestPrefs::cache = tempdir(CLEANUP => 1);
my $crash_root = "$HistoryTestPrefs::cache/bettercallbliss/jobs";
require File::Path;
File::Path::make_path("$crash_root/preview-1000-crash");
my $crash_history = Plugins::BetterCallBliss::JobHistory->new($crash_root);
my $running_saved = eval { $crash_history->save({
    id => 'preview-1000-crash', state => 'running', started_at => 1,
    playlist_id => 42, playlist_title => 'Interrupted crash preview',
    options => { ordering_policy => 'preserve_order', extension_mode => 'none', artist_window => 9 },
    capability => {},
}); 1 };
ok($running_saved, 'running job state can be saved before a crash');
File::Path::make_path("$crash_root/preview-1000-settled");
$crash_history->save({ id => 'preview-1000-settled', state => 'running', started_at => 0.1,
    options => { artist_window => 3 }, capability => {},
    _history_owner_pid => 99999999, _history_optimizer_pid => 99999998 });
for my $case (
    [ 'live', { _history_owner_pid => $$, _history_optimizer_pid => 99999998 } ],
    [ 'acquiring', { _history_owner_pid => 99999999, _history_optimizer_pid => 99999998, _history_external_pending => 1 } ],
    [ 'launching', { _history_owner_pid => 99999999, _history_optimizer_pid => 99999998, _history_launching => 1 } ],
) {
    my ($label, $ownership) = @$case;
    my $id = "preview-1000-$label";
    File::Path::make_path("$crash_root/$id");
    $crash_history->save({ id => $id, state => 'running', started_at => 0.1,
        options => {}, capability => {}, %$ownership });
}
open my $launch_result, '>', "$crash_root/preview-1000-launching/result.json" or die $!;
flock($launch_result, LOCK_EX | LOCK_NB) or die $!;
File::Path::make_path("$crash_root/preview-1000-cancelled-pending");
$crash_history->save({ id => 'preview-1000-cancelled-pending', state => 'cancelled', started_at => 0.1,
    options => { artist_window => 7 }, capability => {}, _history_cleanup_pending => 1,
    _history_owner_pid => 99999999, _history_optimizer_pid => 99999998, _history_external_pending => 1 });
File::Path::make_path("$crash_root/preview-1000-watched");
$crash_history->save({ id => 'preview-1000-watched', state => 'running', started_at => 0.1,
    options => {}, capability => {}, _history_owner_pid => 99999999, _history_optimizer_pid => $$ });
Plugins::BetterCallBliss::Jobs::init('/test/optimizer', 0, 0);
my $crashed = Plugins::BetterCallBliss::Jobs::get('preview-1000-crash');
is($crashed && $crashed->{state}, 'failed', 'a preview interrupted by a crash is not shown as still running');
is($crashed && $crashed->{error_code}, 'PREVIEW_INTERRUPTED', 'crash recovery explains that a rerun is required');
is($crashed && $crashed->{options}->{artist_window}, 9, 'crash recovery preserves editable options');
my $settled = Plugins::BetterCallBliss::Jobs::get('preview-1000-settled');
ok($settled && !$settled->{_history_orphaned}, 'interrupted job with confirmed exited processes is no longer pinned');
my ($disk_settled) = grep { $_->{id} eq 'preview-1000-settled' } $crash_history->load;
is($disk_settled && $disk_settled->{state}, 'failed', 'settled interruption is persisted as failed');
for my $label (qw(live launching)) {
    ok(Plugins::BetterCallBliss::Jobs::get("preview-1000-$label")-> { _history_orphaned },
        "$label interruption is protected while external work may still be active");
}
ok(!Plugins::BetterCallBliss::Jobs::get('preview-1000-acquiring')->{_history_orphaned},
    'preparation is released when the owning server has exited');
my $cancelled_pending = Plugins::BetterCallBliss::Jobs::get('preview-1000-cancelled-pending');
is($cancelled_pending->{state}, 'cancelled', 'pending cancellation remains cancelled after restart');
ok(!$cancelled_pending->{_history_orphaned}, 'pending cancellation is released when its owning server has exited');
is($cancelled_pending->{options}->{artist_window}, 7, 'pending cancellation retains its editable options');
my $watched = Plugins::BetterCallBliss::Jobs::get('preview-1000-watched');
ok($watched->{_history_orphaned}, 'a surviving optimizer keeps an interrupted job protected');
my $recheck = shift @Slim::Utils::Timers::callbacks;
ok($recheck, 'a surviving optimizer is checked again without requiring a new job');
$watched->{_history_optimizer_pid} = 99999998;
close $launch_result;
$recheck->() if $recheck;
ok(!$watched->{_history_orphaned}, 'interrupted job is released when its optimizer exits');
ok(!Plugins::BetterCallBliss::Jobs::get('preview-1000-launching')->{_history_orphaned},
    'launch interruption is released after its result lock is released');
my ($id) = Plugins::BetterCallBliss::Jobs::_new_job_context('preview-1234-restart');
Plugins::BetterCallBliss::Jobs::_create_deferred_sequence_job(
    $id, 'Example playlist', 3, { ordering_policy => 'preserve_order' }, { playlist_id => 42 },
);
Plugins::BetterCallBliss::Jobs::_fail_deferred_route_job($id, 'Example failure', 'TEST_ERROR');
Plugins::BetterCallBliss::Jobs::shutdown();
Plugins::BetterCallBliss::Jobs::init('/test/optimizer', 0, 0);
my $restored = Plugins::BetterCallBliss::Jobs::get($id);
ok($restored, 'failed preview is restored after plugin restart');
is($restored && $restored->{error_code}, 'TEST_ERROR', 'failure reason survives restart');
is($restored && $restored->{options}->{ordering_policy}, 'preserve_order', 'editor parameters survive restart');
Plugins::BetterCallBliss::Jobs::shutdown();

Plugins::BetterCallBliss::Jobs::init('/test/optimizer', 0, 0);
my ($success_id, $success_dir) = Plugins::BetterCallBliss::Jobs::_new_job_context('preview-3000-success');
my $success = Plugins::BetterCallBliss::Jobs::_create_deferred_sequence_job(
    $success_id, 'Completed playlist', 2,
    { ordering_policy => 'preserve_order', extension_mode => 'none' }, { playlist_id => 42 },
);
my $db_path = "$HistoryTestPrefs::cache/bliss.db";
open my $db, '>', $db_path or die $!; print {$db} 'db'; close $db;
my $result_path = "$success_dir/result.json";
open my $result, '>', $result_path or die $!;
print {$result} '{"artifact_kind":"adaptive-route-v1","selected_track_ids":["track-1","track-2"],"primary":{"objective":1,"worst_transition":1}}';
close $result;
$success->{capability} = { database => $db_path };
$success->{database_identity} = Plugins::BetterCallBliss::Jobs::_file_identity($db_path);
$success->{result_path} = $result_path;
$success->{process} = bless { alive => 0 }, 'HistoryTestProcess';
Plugins::BetterCallBliss::Jobs::_poll($success_id);
is($success->{state}, 'completed', 'native result becomes a completed preview');
Plugins::BetterCallBliss::Jobs::shutdown();
Plugins::BetterCallBliss::Jobs::init('/test/optimizer', 0, 0);
my $completed = Plugins::BetterCallBliss::Jobs::get($success_id);
is($completed && $completed->{state}, 'completed', 'completed native preview survives restart');
is_deeply($completed && $completed->{final_track_ids}, ['track-1', 'track-2'], 'restored result keeps selected track order');

my ($cancel_id) = Plugins::BetterCallBliss::Jobs::_new_job_context('preview-3001-cancel');
Plugins::BetterCallBliss::Jobs::_create_deferred_sequence_job(
    $cancel_id, 'Cancelled playlist', 2,
    { ordering_policy => 'preserve_order', artist_window => 4 }, { playlist_id => 42 },
);
Plugins::BetterCallBliss::Jobs::cancel($cancel_id);
Plugins::BetterCallBliss::Jobs::shutdown();
Plugins::BetterCallBliss::Jobs::init('/test/optimizer', 0, 0);
my $cancelled = Plugins::BetterCallBliss::Jobs::get($cancel_id);
is($cancelled && $cancelled->{state}, 'cancelled', 'recent user-cancelled preview survives restart');
is($cancelled && $cancelled->{options}->{artist_window}, 4, 'cancelled preview retains its editable repeat window');
is($cancelled && $cancelled->{playlist_id}, 42, 'cancelled preview retains its source playlist');
Plugins::BetterCallBliss::Jobs::shutdown();

Plugins::BetterCallBliss::Jobs::init('/test/optimizer', 0, 0);
my ($interrupted_id) = Plugins::BetterCallBliss::Jobs::_new_job_context('preview-3002-interrupted');
Plugins::BetterCallBliss::Jobs::_create_deferred_sequence_job(
    $interrupted_id, 'Interrupted playlist', 2,
    { ordering_policy => 'preserve_order', artist_window => 6 }, { playlist_id => 42 },
);
Plugins::BetterCallBliss::Jobs::shutdown();
Plugins::BetterCallBliss::Jobs::init('/test/optimizer', 0, 0);
my $interrupted = Plugins::BetterCallBliss::Jobs::get($interrupted_id);
is($interrupted && $interrupted->{state}, 'failed', 'preview interrupted by normal shutdown is visible after restart');
is($interrupted && $interrupted->{error_code}, 'PREVIEW_INTERRUPTED', 'interruption is not presented as a successful preview');
is($interrupted && $interrupted->{options}->{artist_window}, 6, 'interrupted preview keeps editable parameters');
Plugins::BetterCallBliss::Jobs::shutdown();

Plugins::BetterCallBliss::Jobs::init('/test/optimizer', 0, 0);
my ($preparing_id) = Plugins::BetterCallBliss::Jobs::_new_job_context('preview-3003-preparing');
my $preparing = Plugins::BetterCallBliss::Jobs::_create_deferred_sequence_job(
    $preparing_id, 'Cancelled during preparation', 2,
    { ordering_policy => 'preserve_order', artist_window => 7 }, { playlist_id => 42 },
);
my ($before_acquire) = grep { $_->{id} eq $preparing_id } $crash_history->load;
ok($before_acquire->{_history_owner_pid} && $before_acquire->{_history_optimizer_pid},
    'newly preparing job records process ownership before asynchronous work');
Plugins::BetterCallBliss::Jobs::_history_busy_begin($preparing);
my ($during_acquire) = grep { $_->{id} eq $preparing_id } $crash_history->load;
ok($during_acquire->{_history_external_pending}, 'external preparation is recorded before cancellation or crash');
Plugins::BetterCallBliss::Jobs::cancel($preparing_id);
my ($cancel_pending) = grep { $_->{id} eq $preparing_id } $crash_history->load;
is($cancel_pending->{state}, 'cancelled', 'cancellation is persisted immediately while preparation is still finishing');
ok($cancel_pending->{_history_cleanup_pending}, 'persisted cancellation protects unfinished preparation');
Plugins::BetterCallBliss::Jobs::_fail_deferred_route_job($preparing_id, 'Late callback', 'TEST_ERROR');
is($preparing->{state}, 'cancelled', 'late preparation failure does not change a user cancellation');
Plugins::BetterCallBliss::Jobs::_history_busy_end($preparing);
Plugins::BetterCallBliss::Jobs::shutdown();
Plugins::BetterCallBliss::Jobs::init('/test/optimizer', 0, 0);
my $restored_cancel = Plugins::BetterCallBliss::Jobs::get($preparing_id);
is($restored_cancel && $restored_cancel->{state}, 'cancelled', 'cancel during preparation survives restart once work exits');
is($restored_cancel && $restored_cancel->{options}->{artist_window}, 7, 'preparation cancellation keeps its parameters');
ok(!$restored_cancel->{_history_cleanup_pending}, 'cleanup protection is cleared when preparation finishes');
Plugins::BetterCallBliss::Jobs::shutdown();

Plugins::BetterCallBliss::Jobs::init('/test/optimizer', 0, 0);
my @ids;
for my $n (1 .. 10) {
    my ($next) = Plugins::BetterCallBliss::Jobs::_new_job_context(sprintf('preview-2000-%04d', $n));
    my $job = Plugins::BetterCallBliss::Jobs::_create_deferred_sequence_job(
        $next, "Playlist $n", 3, { ordering_policy => 'preserve_order' }, { playlist_id => 42 },
    );
    $job->{started_at} = $n;
    push @ids, $next;
    Plugins::BetterCallBliss::Jobs::_fail_deferred_route_job($next, 'Example failure', 'TEST_ERROR');
}
my @recent = Plugins::BetterCallBliss::Jobs::all();
my @ordinary_recent = grep { !$_->{_history_orphaned} } @recent;
is(scalar @ordinary_recent, 8, 'only the last eight completed jobs remain accessible');
ok(-d "$crash_root/preview-1000-crash", 'unconfirmed orphan remains protected even outside the recent eight');
ok(!-d "$crash_root/preview-1000-settled", 'old interrupted job is removed after both processes exit');
ok(!Plugins::BetterCallBliss::Jobs::get($ids[0]), 'old job cannot still be opened by direct URL');
ok(!-d "$HistoryTestPrefs::cache/bettercallbliss/jobs/$ids[0]", 'old job directory is removed');
Plugins::BetterCallBliss::Jobs::shutdown();
Plugins::BetterCallBliss::Jobs::init('/test/optimizer', 0, 0);
my @after_restart = Plugins::BetterCallBliss::Jobs::all();
my @ordinary_after_restart = grep { !$_->{_history_orphaned} } @after_restart;
is(scalar @ordinary_after_restart, 8, 'the same eight completed jobs are available after another restart');

my ($active_id) = Plugins::BetterCallBliss::Jobs::_new_job_context('preview-2000-active');
my $active_job = Plugins::BetterCallBliss::Jobs::_create_deferred_sequence_job(
    $active_id, 'Active', 3, {}, {},
);
$active_job->{started_at} = 0.5;
my $process = bless { alive => 1 }, 'HistoryTestProcess';
$active_job->{process} = $process;
Plugins::BetterCallBliss::Jobs::cancel($active_id);
my ($native_cancel) = grep { $_->{id} eq $active_id } $crash_history->load;
is($native_cancel->{state}, 'cancelled', 'native-process cancellation is saved without waiting for process termination');
ok($native_cancel->{_history_cleanup_pending}, 'native-process cancellation remains protected while termination is pending');
ok(!$native_cancel->{_history_external_pending}, 'a terminating optimizer is tracked separately from external acquisition');
ok(-d "$HistoryTestPrefs::cache/bettercallbliss/jobs/$active_id", 'cancelled job remains while its process is alive');
ok(Plugins::BetterCallBliss::Jobs::get($active_id), 'cancelled job remains accessible while its process is alive');
$process->{alive} = 0;
my $check = pop @Slim::Utils::Timers::callbacks;
$check->();
ok(!-d "$HistoryTestPrefs::cache/bettercallbliss/jobs/$active_id", 'old cancelled job is removed after its process exits');
$HistoryTestPrefs::values{preview_history_size_mb} = 1;
my ($large_id, $large_dir) = Plugins::BetterCallBliss::Jobs::_new_job_context('preview-4000-large');
Plugins::BetterCallBliss::Jobs::_create_deferred_sequence_job(
    $large_id, 'Large preview', 2, { artist_window => 4 }, { playlist_id => 42 },
);
open my $large_file, '>', "$large_dir/payload" or die $!;
print {$large_file} 'x' x 1_100_000; close $large_file;
Plugins::BetterCallBliss::Jobs::_fail_deferred_route_job($large_id, 'Example failure', 'TEST_ERROR');
ok(!-d $large_dir, 'oversized preview files are removed to enforce storage limit');
my $large_notice = Plugins::BetterCallBliss::Jobs::get($large_id);
is($large_notice && $large_notice->{error_code}, 'PREVIEW_NOT_RETAINED', 'oversized preview returns an explicit notice');
like($large_notice && $large_notice->{error}, qr/storage limit/i, 'oversized notice explains the storage limit');
Plugins::BetterCallBliss::Jobs::shutdown();

my $snapshot_task = {};
my $snapshot_job = {state => 'running', _scan_inventory_task => $snapshot_task};
Plugins::BetterCallBliss::Jobs::_mark_cancelled($snapshot_job);
is($snapshot_job->{state}, 'cancelled', 'cancelling a snapshot job marks it cancelled');
is($Plugins::BetterCallBliss::CandidateInventory::snapshot_cancellations[-1], $snapshot_task,
    'cancelling a snapshot job stops its inventory worker');
ok(!exists $snapshot_job->{_scan_inventory_task}, 'cancelled job releases its worker handle');

my $handoff_dir = tempdir(CLEANUP => 1);
my $frozen_bliss = "$handoff_dir/bliss-snapshot.db";
open my $frozen_file, '>', $frozen_bliss or die $!;
print {$frozen_file} 'frozen';
close $frozen_file;
my $handoff = {
    capability => {database => '/live/bliss.db'},
    request => {artifacts => {database => {path => '/live/bliss.db'}},
        source_tracks => [{id => 'source'}], route => {search => {restart_count => 1}}},
    options => {extension_mode => 'test_extension'}, candidate_library => {id => 'scope'},
};
my $launched = Plugins::BetterCallBliss::Jobs::_start_preview_from_built(
    'preview-6000-scan', $handoff_dir, "$handoff_dir/semantic.json", $handoff,
    {playlist_title => 'Test', scan_snapshot => {directory => $handoff_dir,
        snapshots => {lyrion => "$handoff_dir/lyrion-snapshot.db", bliss => $frozen_bliss}}},
);
my $args = $Plugins::BetterCallBliss::CandidateInventory::snapshot_preparations[-1];
is($args->[0]->{database}, $frozen_bliss, 'job passes the frozen Bliss database to inventory preparation');
is($args->[3], "$handoff_dir/lyrion-snapshot.db", 'job passes the frozen Lyrion database to inventory preparation');
is($launched->{capability}->{database}, $frozen_bliss, 'bridge resolution retains the same frozen Bliss database');
is($launched->{live_database_path}, '/live/bliss.db', 'job retains the live Bliss path for later revalidation');
ok($launched->{_scan_inventory_task}, 'running job retains its cancellable inventory task');
Plugins::BetterCallBliss::Jobs::cancel('preview-6000-scan');
is($launched->{state}, 'cancelled', 'snapshot preparation can be cancelled through the job');

my $snapshot_dir = tempdir(CLEANUP => 1);
like(Plugins::BetterCallBliss::Jobs::compact_status({state => 'running',
    stage => 'Capturing library database snapshots', lastfm_state => 'preparing',
    options => {extension_mode => 'automatic'}}), qr/Capturing library database snapshots/,
    'live status identifies snapshot capture rather than Last.fm acquisition');
my $capture = bless {status => {state => 'running'}}, 'HistoryTestSnapshotProcess';
$Plugins::BetterCallBliss::ScanSnapshotProcess::next = $capture;
my $capture_job = Plugins::BetterCallBliss::Jobs::_create_deferred_sequence_job(
    'preview-6000-capture', 'Snapshot test', 2, {}, {});
@Slim::Utils::Timers::callbacks = ();
my ($continued_built, $continued_fields);
{
    no warnings 'redefine';
    local *Plugins::BetterCallBliss::Jobs::_start_preview_from_built = sub {
        (undef, undef, undef, $continued_built, $continued_fields) = @_;
    };
    Plugins::BetterCallBliss::Jobs::_start_scan_snapshot_phase('preview-6000-capture',
        $snapshot_dir, "$snapshot_dir/semantic.json", $handoff, {}, '/live/library.db');
    ok(!$continued_fields && $capture_job->{stage} =~ /snapshot/i,
        'snapshot capture starts without launching the optimizer');
    is($capture_job->{_history_optimizer_pid}, 987654,
        'snapshot worker PID is retained to protect active files after a restart');
    $capture->{status} = {state => 'completed', directory => $snapshot_dir,
        snapshots => {lyrion => 'frozen-library', bliss => 'frozen-bliss'}};
    my $timer = shift @Slim::Utils::Timers::callbacks;
    $timer->();
    is($continued_fields->{scan_snapshot}->{snapshots}->{bliss}, 'frozen-bliss',
        'completed snapshot is handed to preview preparation');
    is($continued_fields->{scan_snapshot_process}, $capture,
        'the process remains associated with the job for later cleanup');
}

my $cancel_capture = bless {status => {state => 'running'}}, 'HistoryTestSnapshotProcess';
$Plugins::BetterCallBliss::ScanSnapshotProcess::next = $cancel_capture;
my $cancel_capture_job = Plugins::BetterCallBliss::Jobs::_create_deferred_sequence_job(
    'preview-6000-capture-cancel', 'Snapshot cancel', 2, {}, {});
@Slim::Utils::Timers::callbacks = ();
Plugins::BetterCallBliss::Jobs::_start_scan_snapshot_phase('preview-6000-capture-cancel',
    $snapshot_dir, "$snapshot_dir/semantic.json", $handoff, {}, '/live/library.db');
Plugins::BetterCallBliss::Jobs::cancel('preview-6000-capture-cancel');
ok($cancel_capture->{cancelled}, 'job cancellation stops snapshot capture');
my $cancel_timer = shift @Slim::Utils::Timers::callbacks;
$cancel_timer->();
ok($cancel_capture->{cleaned}, 'cancelled snapshot capture is cleaned after worker exit');

my $automatic_capture = bless {status => {state => 'running'}}, 'HistoryTestSnapshotProcess';
$Plugins::BetterCallBliss::ScanSnapshotProcess::next = $automatic_capture;
my $live_fixture = "$snapshot_dir/live-bliss.db";
open my $live_file, '>', $live_fixture or die $!;
print {$live_file} 'live';
close $live_file;
my $live_handoff = {%$handoff,
    capability => {%{$handoff->{capability}}, database => $live_fixture},
    request => {%{$handoff->{request}}, artifacts => {database => {path => $live_fixture}}}};
my $automatic_job = Plugins::BetterCallBliss::Jobs::_create_deferred_sequence_job(
    'preview-6000-auto-capture', 'Snapshot start', 2, {}, {});
@Slim::Utils::Timers::callbacks = ();
{
    no warnings 'redefine';
    local *Plugins::BetterCallBliss::CandidateInventory::_lms_database_path = sub { '/live/library.db' };
    Plugins::BetterCallBliss::Jobs::_start_preview_from_built('preview-6000-auto-capture',
        $snapshot_dir, "$snapshot_dir/semantic.json", $live_handoff, {prepare_scan_snapshot => 1, playlist_title => 'Test'});
}
ok(Plugins::BetterCallBliss::Jobs::get('preview-6000-auto-capture')->{stage} =~ /snapshot/i,
    'snapshot-enabled preview starts the background capture phase');
Plugins::BetterCallBliss::Jobs::cancel('preview-6000-auto-capture');
my $automatic_timer = shift @Slim::Utils::Timers::callbacks;
$automatic_timer->() if $automatic_timer;

my $race_capture = bless {status => {state => 'running'}}, 'HistoryTestSnapshotProcess';
$Plugins::BetterCallBliss::ScanSnapshotProcess::next = $race_capture;
my $race_job = Plugins::BetterCallBliss::Jobs::_create_deferred_sequence_job(
    'preview-6000-scan-race', 'Scan race', 2, {}, {});
@Slim::Utils::Timers::callbacks = ();
my $race_ok;
{
    no warnings 'redefine';
    local $Slim::Music::Import::scanning = 1;
    local *Plugins::BetterCallBliss::CandidateInventory::_lms_database_path = sub { '/live/library.db' };
    $race_ok = eval { Plugins::BetterCallBliss::Jobs::_start_preview_from_built('preview-6000-scan-race',
        $snapshot_dir, "$snapshot_dir/semantic.json", $live_handoff, {playlist_title => 'Test'}); 1 };
}
ok($race_ok && Plugins::BetterCallBliss::Jobs::get('preview-6000-scan-race')->{stage} =~ /snapshot/i,
    'a scan starting after request capture triggers a snapshot rather than using live databases');
Plugins::BetterCallBliss::Jobs::cancel('preview-6000-scan-race');
my $race_timer = shift @Slim::Utils::Timers::callbacks;
$race_timer->() if $race_timer;

my $replacement_fields;
{
    no warnings 'redefine';
    local $Slim::Music::Import::scanning = 1;
    local *Plugins::BetterCallBliss::CandidateInventory::_lms_database_path = sub { '/live/library.db' };
    local *Plugins::BetterCallBliss::Jobs::_start_scan_snapshot_phase = sub { $replacement_fields = $_[4] };
    Plugins::BetterCallBliss::Jobs::_start_preview_from_built('preview-6000-race-inventory',
        $snapshot_dir, "$snapshot_dir/semantic.json", $live_handoff, {playlist_title => 'Test', prepared_candidate_inventory => {old => 1}});
}
ok($replacement_fields && !exists($replacement_fields->{prepared_candidate_inventory}),
    'a scan starting during candidate capture discards the old inventory before snapshotting');

my $failed_capture = bless {status => {state => 'running'}}, 'HistoryTestSnapshotProcess';
$Plugins::BetterCallBliss::ScanSnapshotProcess::next = $failed_capture;
my $failed_capture_job = Plugins::BetterCallBliss::Jobs::_create_deferred_sequence_job(
    'preview-6000-capture-fail', 'Snapshot failure', 2, {}, {});
@Slim::Utils::Timers::callbacks = ();
Plugins::BetterCallBliss::Jobs::_start_scan_snapshot_phase('preview-6000-capture-fail',
    $snapshot_dir, "$snapshot_dir/semantic.json", $handoff, {}, '/live/library.db');
$failed_capture->{status} = {state => 'failed', error => 'database unavailable'};
my $failed_timer = shift @Slim::Utils::Timers::callbacks;
$failed_timer->();
is($failed_capture_job->{state}, 'failed', 'snapshot failure marks the preview failed');
is($failed_capture_job->{error_code}, 'SNAPSHOT_PREPARATION_FAILED', 'snapshot failure has an explicit error code');
ok($failed_capture->{cleaned}, 'failed snapshot capture is cleaned after worker exit');

my $shutdown_capture = bless {status => {state => 'running'}}, 'HistoryTestSnapshotProcess';
$Plugins::BetterCallBliss::ScanSnapshotProcess::next = $shutdown_capture;
Plugins::BetterCallBliss::Jobs::_create_deferred_sequence_job(
    'preview-6000-capture-shutdown', 'Snapshot shutdown', 2, {}, {});
@Slim::Utils::Timers::callbacks = ();
Plugins::BetterCallBliss::Jobs::_start_scan_snapshot_phase('preview-6000-capture-shutdown',
    $snapshot_dir, "$snapshot_dir/semantic.json", $handoff, {}, '/live/library.db');
Plugins::BetterCallBliss::Jobs::shutdown();
ok($shutdown_capture->{cancelled}, 'server shutdown requests snapshot worker cancellation');

done_testing();
