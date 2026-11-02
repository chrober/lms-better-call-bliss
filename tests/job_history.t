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

done_testing();
