use strict;
use warnings;
use FindBin;
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;
use lib "$FindBin::Bin/..";
use Plugins::BetterCallBliss::ScanJobBinding;

my $dir = tempdir(CLEANUP => 1);
my $snapshot = File::Spec->catfile($dir, 'bliss-snapshot.db');
open my $fh, '>', $snapshot or die $!;
print {$fh} 'snapshot';
close $fh;
my $built = {
    capability => {database => '/live/bliss.db', music_roots => ['/music']},
    request => {artifacts => {database => {path => '/live/bliss.db', schema_identity => 'TracksV2'}}},
};
my $bound = Plugins::BetterCallBliss::ScanJobBinding::bind($built, {
    directory => $dir, snapshots => {bliss => $snapshot},
});
is($bound->{capability}->{database}, $snapshot, 'bridge resolver uses the frozen Bliss database');
is($bound->{request}->{artifacts}->{database}->{path}, $snapshot, 'optimizer uses the same frozen Bliss database');
is($bound->{live_database_path}, '/live/bliss.db', 'the live database path remains available for revalidation');
is($built->{capability}->{database}, '/live/bliss.db', 'binding does not modify the original request');
my $bad = eval { Plugins::BetterCallBliss::ScanJobBinding::bind($built, {
    directory => $dir, snapshots => {bliss => '/live/bliss.db'},
}); 1 };
ok(!$bad, 'a database outside the job snapshot directory is rejected');
my $mismatch = {%$built, request => {artifacts => {database => {path => '/different.db'}}}};
$bad = eval { Plugins::BetterCallBliss::ScanJobBinding::bind($mismatch, {
    directory => $dir, snapshots => {bliss => $snapshot},
}); 1 };
ok(!$bad, 'an inconsistent original optimizer and capability database is rejected');
my $live_job = {scan_generation => 100};
ok(Plugins::BetterCallBliss::ScanJobBinding::validate_scan_state($live_job, 0, 100),
    'a live-database job remains valid when no scan occurred');
$bad = eval { Plugins::BetterCallBliss::ScanJobBinding::validate_scan_state($live_job, 1, 100); 1 };
ok(!$bad && $@ =~ /LIBRARY_SCAN_STARTED/, 'a scan starting during a live-database job is rejected');
$bad = eval { Plugins::BetterCallBliss::ScanJobBinding::validate_scan_state($live_job, 0, 101); 1 };
ok(!$bad && $@ =~ /LIBRARY_SCAN_STARTED/, 'a scan that started and finished during a live-database job is rejected');
ok(Plugins::BetterCallBliss::ScanJobBinding::validate_scan_state({live_database_path => '/live/db'}, 1, 101),
    'a snapshot-backed job can proceed while the live library is scanning');
done_testing;
