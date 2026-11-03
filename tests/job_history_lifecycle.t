use strict;
use warnings;
use FindBin;
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
    package HistoryTestProcess;
    sub alive { $_[0]->{alive} }
    sub die { 0 }
    sub exit_code { 0 }
    package Plugins::BetterCallBliss::CandidateInventory;
    sub init {} sub shutdown {}
    package Plugins::BetterCallBliss::UserNotification;
    sub route_failure {}
    package Plugins::BetterCallBliss::GuidanceProviderDiscovery;
    sub dispatch_native_diagnostics {}
    package Plugins::BetterCallBliss::CandidateGuidance;
    sub native_provider_state { undef }
    for my $module (qw(
        Proc/Background.pm Slim/Music/Import.pm Slim/Utils/Log.pm
        Slim/Utils/Misc.pm Slim/Utils/Prefs.pm Slim/Utils/Timers.pm
        Slim/Utils/Unicode.pm Slim/Player/Client.pm Slim/Player/Playlist.pm
        Slim/Player/Source.pm Plugins/BetterCallBliss/BlissCompatibility.pm
        Plugins/BetterCallBliss/BridgeResolver.pm Plugins/BetterCallBliss/CandidateInventory.pm
        Plugins/BetterCallBliss/CandidateGuidance.pm Plugins/BetterCallBliss/DurationTarget.pm
        Plugins/BetterCallBliss/GuidanceProviderDiscovery.pm Plugins/BetterCallBliss/AlbumDestination.pm
        Plugins/BetterCallBliss/JobOptions.pm Plugins/BetterCallBliss/LogDiagnostics.pm
        Plugins/BetterCallBliss/RequestBuilder.pm Plugins/BetterCallBliss/PlaylistWriter.pm
        Plugins/BetterCallBliss/QueueWriter.pm Plugins/BetterCallBliss/RepeatConflicts.pm
        Plugins/BetterCallBliss/RouteMode.pm Plugins/BetterCallBliss/UserNotification.pm
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

done_testing();
