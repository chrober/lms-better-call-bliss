use strict;
use warnings;
use FindBin;
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;
use Time::HiRes qw(time sleep);
use DBI;
use JSON::XS;

use lib "$FindBin::Bin/../BetterCallBliss/SharedInventory/lib";
use lib "$FindBin::Bin/..";
use Plugins::BlissLibrary::Worker;
use Plugins::BetterCallBliss::ScanDatabaseSnapshot;

my $root = tempdir(CLEANUP => 1);
my $source = File::Spec->catfile($root, 'source.db');
my $dbh = DBI->connect("dbi:SQLite:dbname=$source", '', '', {RaiseError => 1});
$dbh->do('CREATE TABLE tracks (id INTEGER)');
$dbh->do('INSERT INTO tracks VALUES (42)');
my $output_dir = File::Spec->catdir($root, 'job');
mkdir $output_dir or die $!;
my $stdout = File::Spec->catfile($root, 'stdout');
my $stderr = File::Spec->catfile($root, 'stderr');
my $script = File::Spec->catfile($FindBin::Bin, '..', 'BetterCallBliss', 'scan-snapshot-worker.pl');
my $worker = Plugins::BlissLibrary::Worker->start(
    command => [$^X, $script, $source, $source, $output_dir],
    stdout_path => $stdout, stderr_path => $stderr,
);
my $deadline = time + 20;
my $result;
do {
    $result = $worker->poll;
    sleep 0.05 if $result->{state} eq 'running';
} while ($result->{state} eq 'running' && time < $deadline);
is($result->{state}, 'completed', 'worker captures databases in a separate process');
open my $output, '<:raw', $stdout or die $!;
my $bytes = do { local $/; <$output> };
close $output;
my $paths = eval { JSON::XS->new->utf8->decode($bytes) };
ok(ref($paths) eq 'HASH' && -f ($paths->{lyrion} || '') && -f ($paths->{bliss} || ''),
    'worker returns paths to both completed job-local snapshots');

SKIP: {
    skip 'requires Unix process signals', 2 if $^O eq 'MSWin32';
    my $locked = File::Spec->catfile($root, 'locked.db');
    my $lock = DBI->connect("dbi:SQLite:dbname=$locked", '', '', {RaiseError => 1});
    $lock->do('CREATE TABLE tracks (id INTEGER)');
    $lock->do('BEGIN EXCLUSIVE');
    my $cancel_dir = File::Spec->catdir($root, 'cancelled');
    mkdir $cancel_dir or die $!;
    my $cancel_worker = Plugins::BlissLibrary::Worker->start(
        command => [$^X, $script, $locked, $source, $cancel_dir],
        stdout_path => File::Spec->catfile($root, 'cancel-stdout'),
        stderr_path => File::Spec->catfile($root, 'cancel-stderr'),
    );
    sleep 0.2;
    $cancel_worker->cancel;
    my $cancel_deadline = time + 10;
    my $state;
    do {
        $state = $cancel_worker->poll;
        sleep 0.05 if $state->{state} eq 'cancelling';
    } while ($state->{state} eq 'cancelling' && time < $cancel_deadline);
    is($state->{state}, 'cancelled', 'cancellation stops an active snapshot worker');
    Plugins::BetterCallBliss::ScanDatabaseSnapshot::cleanup_pair($cancel_dir);
    opendir my $dh, $cancel_dir or die $!;
    my @left = grep { $_ ne '.' && $_ ne '..' } readdir $dh;
    closedir $dh;
    is_deeply(\@left, [], 'cancelled worker snapshots can be cleaned up after exit');
    $lock->do('ROLLBACK');
    $lock->disconnect;
}
$dbh->disconnect;
done_testing;
