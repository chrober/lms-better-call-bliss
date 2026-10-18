use strict;
use warnings;
use FindBin;
use Test::More;

sub slurp {
    my $path = shift;
    open my $fh, '<:raw', $path or die "Cannot read $path: $!";
    local $/;
    return <$fh>;
}

my $request_builder = slurp(
    "$FindBin::Bin/../BetterCallBliss/RequestBuilder.pm",
);
my $candidate_inventory = slurp(
    "$FindBin::Bin/../BetterCallBliss/CandidateInventory.pm",
);
my $jobs = slurp("$FindBin::Bin/../BetterCallBliss/Jobs.pm");
my $web = slurp("$FindBin::Bin/../BetterCallBliss/Web.pm");
my $extras = slurp(
    "$FindBin::Bin/../BetterCallBliss/HTML/EN/plugins/BetterCallBliss/index.html",
);

like(
    $request_builder,
    qr/sub build_reorder_request.*?\$track_resultset->can\('next'\).*?while \(my \$track = \$track_resultset->next\).*?_yield_to_lms\(\)/s,
    'saved-playlist capture returns to the LMS event loop between tracks',
);
like(
    $request_builder,
    qr/sub _track_bundle.*?for my \$track \(\@\$tracks\).*?_yield_to_lms\(\)/s,
    'source metadata capture returns to the LMS event loop between tracks',
);
like(
    $candidate_inventory,
    qr/sub _sha256_file.*?read\(\$fh, my \$buffer, 1024 \* 1024\).*?_yield_to_lms_if_due/s,
    'large cache validation hashes in bounded chunks with LMS yields',
);
like(
    $candidate_inventory,
    qr/my \(\$track_identity_path_sha256\).*?unless \$track_identity_path_sha256.*?eq \(\$state->\{track_identity_sha256\}/s,
    'cold cache loading trusts the atomically published content-addressed identity snapshot',
);
like(
    $candidate_inventory,
    qr/sub _write_identity_lookup.*?_yield_to_lms_if_due/s,
    'candidate identity persistence yields during large cache rebuilds',
);
like(
    $candidate_inventory,
    qr/sub _start_next_async_prepare.*?fork\(\).*?setpriority\(0, 0, 10\).*?ionice.*?BackgroundRebuildStarted.*?sub _poll_async_prepare.*?BackgroundRebuildFinished.*?sub prepare_async/s,
    'cold candidate-library rebuilds run with low CPU and idle I/O priority',
);
like(
    $candidate_inventory,
    qr/Rebuilding candidate library: scanning local LMS tracks.*?Rebuilding candidate library: matching Bliss rows.*?Rebuilding candidate library: publishing candidate artifacts/s,
    'the background inventory worker reports meaningful preparation phases',
);
like(
    $jobs,
    qr/sub _fail_deferred_route_job.*?UserNotification::route_failure/s,
    'deferred route-start failures reach the Material error notification path',
);
like(
    $jobs,
    qr/if \(\$job->\{state\} eq 'failed'\).*?UserNotification::route_failure/s,
    'native route failures reach the Material error notification path',
);
like(
    $web,
    qr/sub _playlists.*?getPlaylistIdsSQL.*?JOIN playlist_track.*?fetchrow_array/s,
    'the cold playlist selector uses one SQL result stream instead of inflating every playlist object',
);
unlike(
    $web,
    qr/getPlaylists\('all'\)->all/,
    'the cold playlist selector no longer inflates the complete playlist ORM result',
);
like(
    $extras,
    qr/encoded\.set\('ajax_preview', '1'\).*?fetch\(mainForm\.action/s,
    'AJAX preview submission identifies the lightweight response path',
);
like(
    $web,
    qr/if \(\$params->\{ajax_preview\}.*?finish_web_response\(\).*?my \$ajax_content.*?return \\\$ajax_content/s,
    'AJAX preview start returns an LMS-compatible scalar reference before rebuilding the complete Extras view',
);
like(
    $jobs,
    qr/sub _deprioritize_optimizer.*?setpriority\(0, \$pid, 10\).*?sub _launch_optimizer.*?_deprioritize_optimizer\(\$process\)/s,
    'the native optimizer runs at lower OS priority than the LMS event loop',
);
like(
    $jobs,
    qr/sub _background_parallel_workers.*?\$processors - 2.*?RAYON_NUM_THREADS.*?_background_parallel_workers/s,
    'Linux optimizer jobs reserve two logical CPUs for LMS and playback',
);
like(
    $jobs,
    qr/sub _schedule_poll.*?return if \$job->\{poll_scheduled\}.*?\$job->\{poll_scheduled\} = 1.*?\$current->\{poll_scheduled\} = 0.*?_poll\(\$job_id\)/s,
    'each running job has at most one pending native-process poll timer',
);
like(
    $jobs,
    qr/sub get \{\s+my \$job_id = shift;\s+return \$jobs\{\$job_id\};\s+\}\s+sub all \{\s+return sort/s,
    'read-only job status requests rely on the single background poll timer',
);
like(
    $jobs,
    qr/CandidateInventory::prepare_async\(.*?prepared_candidate_inventory.*?_start_preview_from_built/s,
    'preview startup continues asynchronously after candidate-library capture',
);

done_testing();
