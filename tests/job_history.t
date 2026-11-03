use strict;
use warnings;
use FindBin;
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test::More;
use lib "$FindBin::Bin/..";

require "$FindBin::Bin/../BetterCallBliss/JobHistory.pm";

my $root = tempdir(CLEANUP => 1);
my $history = Plugins::BetterCallBliss::JobHistory->new($root);
my $active = 'preview-1000-active';
make_path("$root/$active");
for my $n (1 .. 10) {
    my $id = "preview-1000-$n";
    make_path("$root/$id");
    $history->save({
        id => $id, state => 'completed', started_at => $n, finished_at => $n + 1,
        playlist_title => "Playlist $n", playlist_id => 42,
        capability => { algorithm => 'adaptive', static_weight_sliders => {tempo => 4} },
        options => { ordering_policy => 'preserve_order', extension_mode => 'none',
            provider => { api_key => 'private', source => 'api_key' } },
        artifact => { artifact_kind => 'adaptive-route-v1', selected_track_ids => [1, 2] },
        final_track_ids => [1, 2], source_track_ids => [1, 2], track_urls => {}, labels => {},
    });
}
$history->prune({ $active => 1 });
ok(-d "$root/$active", 'active directory survives retention');
ok(!-d "$root/preview-1000-1" && !-d "$root/preview-1000-2", 'older completed directories removed');
my @restored = $history->load;
is(scalar @restored, 8, 'eight completed jobs restored');
is($restored[0]->{id}, 'preview-1000-10', 'latest job restored first');
is($restored[0]->{options}->{ordering_policy}, 'preserve_order', 'original job options survive restart');
is_deeply($restored[0]->{final_track_ids}, [1, 2], 'preview track order survives restart');
is($restored[0]->{capability}->{static_weight_sliders}->{tempo}, 4, 'captured weights survive restart');
is($restored[0]->{artifact}->{artifact_kind}, 'adaptive-route-v1', 'result survives restart');
ok(!exists $restored[0]->{options}->{provider}->{api_key}, 'provider credentials are never persisted');
is($restored[0]->{options}->{provider}->{source}, 'api_key', 'non-secret provider settings survive');
$restored[0]->{write_state} = 'completed';
$history->save($restored[0]);
my @updated = $history->load;
is($updated[0]->{write_state}, 'completed', 'accepted output state survives another restart');

make_path("$root/not-a-preview");
open my $fh, '>', "$root/not-a-preview/keep" or die $!;
print {$fh} 'keep'; close $fh;
$history->prune({});
ok(-f "$root/not-a-preview/keep", 'unrelated directories survive retention');

my $broken = 'preview-1000-broken';
make_path("$root/$broken");
open my $bad, '>', "$root/$broken/history.json" or die $!;
print {$bad} '{broken'; close $bad;
my @without_broken = $history->load;
is(scalar @without_broken, 8, 'a corrupt history file does not hide valid previews');
ok(-d "$root/$broken", 'unrecognized data is not deleted by retention');

my $pinned = 'preview-1000-3';
for my $n (11 .. 12) {
    my $id = "preview-1000-$n";
    make_path("$root/$id");
    $history->save({ id => $id, state => 'failed', started_at => $n, options => {} });
}
$history->prune({ $pinned => 1 });
ok(-d "$root/$pinned", 'an older directory still in use is protected');

my $custom_root = tempdir(CLEANUP => 1);
my $custom = Plugins::BetterCallBliss::JobHistory->new($custom_root);
for my $n (1 .. 12) {
    my $id = "preview-2000-$n";
    make_path("$custom_root/$id");
    $custom->save({ id => $id, state => 'failed', started_at => $n, options => {} });
}
$custom->prune({}, 10);
my @custom_jobs = $custom->load;
is(scalar(@custom_jobs), 10, 'configured retention keeps ten previews');
$custom->prune({}, 3);
@custom_jobs = $custom->load;
is(scalar(@custom_jobs), 3, 'reducing retention removes the oldest excess previews');

my $policy_root = tempdir(CLEANUP => 1);
my $policy_history = Plugins::BetterCallBliss::JobHistory->new($policy_root);
for my $n (1 .. 4) {
    my $id = "preview-3000-$n";
    make_path("$policy_root/$id");
    $policy_history->save({id => $id, state => 'failed', started_at => 1000 + $n, options => {}});
    open my $payload, '>', "$policy_root/$id/payload" or die $!;
    print {$payload} 'x' x 1000; close $payload;
}
$policy_history->prune({}, { count => undef, max_bytes => 100000, days => undef, now => 1005 });
my @policy_jobs = $policy_history->load;
is(scalar @policy_jobs, 4, 'empty count and age limits do not remove entries');
$policy_history->prune({}, { count => undef, max_bytes => 2500, days => undef, now => 1005 });
@policy_jobs = $policy_history->load;
is(scalar @policy_jobs, 2, 'byte limit removes oldest jobs until within budget');
is($policy_jobs[0]{id}, 'preview-3000-4', 'byte cleanup keeps newest jobs');
$policy_history->prune({}, { count => undef, max_bytes => 100000, days => 1, now => 1004 + 86401 });
@policy_jobs = $policy_history->load;
is(scalar @policy_jobs, 0, 'age limit removes expired jobs');

my $oversize_root = tempdir(CLEANUP => 1);
my $oversize_history = Plugins::BetterCallBliss::JobHistory->new($oversize_root);
make_path("$oversize_root/preview-4000-large");
$oversize_history->save({id => 'preview-4000-large', state => 'failed', started_at => 4000, options => {}});
open my $large, '>', "$oversize_root/preview-4000-large/payload" or die $!;
print {$large} 'x' x 2000; close $large;
$oversize_history->prune({}, {count => undef, max_bytes => 1000});
ok(!-d "$oversize_root/preview-4000-large", 'single oversized preview is removed to enforce the hard limit');
ok($oversize_history->last_oversized->{'preview-4000-large'}, 'oversized removal is reported to the caller');

done_testing();
