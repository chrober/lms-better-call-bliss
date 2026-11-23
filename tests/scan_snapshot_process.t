use strict;
use warnings;
use FindBin;
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;
use Time::HiRes qw(time sleep);
use DBI;
use lib "$FindBin::Bin/..", "$FindBin::Bin/../BetterCallBliss/SharedInventory/lib";
use Plugins::BetterCallBliss::ScanSnapshotProcess;

my $root = tempdir(CLEANUP => 1);
my $source = File::Spec->catfile($root, 'source.db');
my $dbh = DBI->connect("dbi:SQLite:dbname=$source", '', '', {RaiseError => 1});
$dbh->do('CREATE TABLE tracks (id INTEGER)');
$dbh->do('INSERT INTO tracks VALUES (42)');
my $process;
{
    local $ENV{PERL5LIB} = '';
    $process = Plugins::BetterCallBliss::ScanSnapshotProcess->start(
        parent_dir => $root, lyrion_path => $source, bliss_path => $source,
        timeout_seconds => 10,
    );
}
my $start = time;
ok($process->pid && $process->pid =~ /^\d+$/, 'snapshot worker exposes its process identity for restart protection');
my $state = $process->poll;
ok(time - $start < 1, 'poll returns promptly without waiting for database capture');
my $deadline = time + 15;
while ($state->{state} eq 'running' && time < $deadline) {
    sleep 0.05;
    $state = $process->poll;
}
is($state->{state}, 'completed', 'successful worker returns a completed state');
ok(-f ($state->{snapshots}->{lyrion} || '') && -f ($state->{snapshots}->{bliss} || ''),
    'completed state supplies both snapshot files');
my $dir = $state->{directory};
$dbh->do('INSERT INTO tracks VALUES (43)');
my $artifact_dir = File::Spec->catdir($dir, 'candidate-inventory');
mkdir $artifact_dir or die $!;
my $retained = File::Spec->catfile($artifact_dir, 'retained.json');
open my $artifact, '>', $retained or die $!;
print {$artifact} '{}';
close $artifact;
$process->cleanup;
ok(-f $retained && !-e $state->{snapshots}->{lyrion} && !-e $state->{snapshots}->{bliss} && -f $source,
    'cleanup removes databases without removing retained job artifacts or touching source');

my $bad = Plugins::BetterCallBliss::ScanSnapshotProcess->start(
    parent_dir => $root, lyrion_path => $source,
    bliss_path => File::Spec->catfile($root, 'missing.db'), timeout_seconds => 10,
);
$deadline = time + 15;
$state = $bad->poll;
while ($state->{state} eq 'running' && time < $deadline) {
    sleep 0.05;
    $state = $bad->poll;
}
is($state->{state}, 'failed', 'failed worker reports a failed state');
like($state->{error} || '', qr/source is unavailable/i, 'failure explains the missing source');
$bad->cleanup;

my $discard = Plugins::BetterCallBliss::ScanSnapshotProcess->start(
    parent_dir => $root, lyrion_path => $source, bliss_path => $source, timeout_seconds => 10,
);
$deadline = time + 15;
$state = $discard->poll;
while ($state->{state} eq 'running' && time < $deadline) { sleep 0.05; $state = $discard->poll }
is($state->{state}, 'completed', 'cleanup fixture snapshot completes');
my $inventory_dir = File::Spec->catdir($state->{directory}, 'candidate-inventory');
mkdir $inventory_dir or die $!;
my $generated = File::Spec->catfile($inventory_dir, 'inventory-' . ('a' x 64) . '.json');
my $unknown = File::Spec->catfile($inventory_dir, 'user-data.txt');
for my $file ($generated, $unknown) { open my $out, '>', $file or die $!; print {$out} 'x'; close $out }
$discard->cleanup(discard_inventory => 1);
ok(!-e $generated && -f $unknown, 'terminal cleanup removes only known generated inventory artifacts');

SKIP: {
    skip 'requires Unix waitpid', 3 if $^O eq 'MSWin32';
    my $reaped = Plugins::BetterCallBliss::ScanSnapshotProcess->start(
        parent_dir => $root, lyrion_path => $source, bliss_path => $source, timeout_seconds => 10,
    );
    waitpid($reaped->{worker}->{proc}->pid, 0);
    my $result = $reaped->poll;
    is($result->{state}, 'completed', 'valid completed snapshots survive another child reaper');
    ok($result->{snapshots} && -f $result->{snapshots}->{bliss}, 'reaped worker descriptor is validated');
    $reaped->cleanup;
    my $failed_reaped = Plugins::BetterCallBliss::ScanSnapshotProcess->start(
        parent_dir => $root, lyrion_path => $source,
        bliss_path => File::Spec->catfile($root, 'missing-reaped.db'), timeout_seconds => 10,
    );
    waitpid($failed_reaped->{worker}->{proc}->pid, 0);
    is($failed_reaped->poll->{state}, 'failed', 'a reaped failed worker is never treated as successful');
    $failed_reaped->cleanup;
}

SKIP: {
    skip 'requires Unix process signals', 5 if $^O eq 'MSWin32';
    my $locked = File::Spec->catfile($root, 'locked.db');
    my $lock = DBI->connect("dbi:SQLite:dbname=$locked", '', '', {RaiseError => 1});
    $lock->do('CREATE TABLE tracks (id INTEGER)');
    $lock->do('BEGIN EXCLUSIVE');
    my $slow = Plugins::BetterCallBliss::ScanSnapshotProcess->start(
        parent_dir => $root, lyrion_path => $locked, bliss_path => $source, timeout_seconds => 30,
    );
    my $cleanup_ok = eval { $slow->cleanup; 1 };
    ok(!$cleanup_ok, 'cleanup refuses to remove a running worker directory');
    $slow->cancel;
    $deadline = time + 10;
    $state = $slow->poll;
    while ($state->{state} eq 'running' && time < $deadline) { sleep 0.05; $state = $slow->poll }
    is($state->{state}, 'cancelled', 'cancel reports cancellation after worker exit');
    ok(eval { $slow->cleanup; 1 }, 'cancelled worker can be cleaned up safely');
    my $timed = Plugins::BetterCallBliss::ScanSnapshotProcess->start(
        parent_dir => $root, lyrion_path => $locked, bliss_path => $source, timeout_seconds => 1,
    );
    $deadline = time + 10;
    $state = $timed->poll;
    while ($state->{state} eq 'running' && time < $deadline) { sleep 0.05; $state = $timed->poll }
    is($state->{state}, 'failed', 'a worker exceeding its deadline fails');
    like($state->{error} || '', qr/timed out/i, 'timeout explains the reason');
    $timed->cleanup;
    $lock->do('ROLLBACK');
    $lock->disconnect;
}
$dbh->disconnect;
done_testing;
