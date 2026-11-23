use strict;
use warnings;
use FindBin;
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;
use DBI;
use POSIX qw(WNOHANG);
use Time::HiRes qw(time sleep);

use lib "$FindBin::Bin/..";
require Plugins::BetterCallBliss::ScanDatabaseSnapshot;

my $dir = tempdir(CLEANUP => 1);
my $source = File::Spec->catfile($dir, 'source.db');
my $snapshot = File::Spec->catfile($dir, 'snapshot.db');
my $writer = DBI->connect("dbi:SQLite:dbname=$source", '', '',
    { RaiseError => 1, PrintError => 0, AutoCommit => 1 });
$writer->do('PRAGMA journal_mode=WAL');
$writer->do('PRAGMA wal_autocheckpoint=0');
$writer->do('CREATE TABLE tracks (id INTEGER PRIMARY KEY, title TEXT)');
$writer->do(q{INSERT INTO tracks VALUES (1, 'before')});

Plugins::BetterCallBliss::ScanDatabaseSnapshot::capture($source, $snapshot);
$writer->do(q{UPDATE tracks SET title='after' WHERE id=1});
my $reader = DBI->connect("dbi:SQLite:dbname=$snapshot", '', '',
    { RaiseError => 1, PrintError => 0, sqlite_open_flags => 1 });
is($reader->selectrow_array('SELECT title FROM tracks WHERE id=1'), 'before',
    'snapshot includes committed WAL data and stays unchanged after source writes');
$reader->disconnect;

my $during_write = File::Spec->catfile($dir, 'during-write.db');
$writer->begin_work;
$writer->do(q{UPDATE tracks SET title='uncommitted' WHERE id=1});
Plugins::BetterCallBliss::ScanDatabaseSnapshot::capture($source, $during_write);
$writer->commit;
$reader = DBI->connect("dbi:SQLite:dbname=$during_write", '', '',
    { RaiseError => 1, PrintError => 0, sqlite_open_flags => 1 });
is($reader->selectrow_array('SELECT title FROM tracks WHERE id=1'), 'after',
    'a snapshot taken during a write transaction excludes uncommitted changes');
$reader->disconnect;

my $error = eval { Plugins::BetterCallBliss::ScanDatabaseSnapshot::capture($source, $snapshot); 1 };
ok(!$error, 'an existing snapshot is never overwritten');
my $missing = File::Spec->catfile($dir, 'missing.db');
my $invalid_output = File::Spec->catfile($dir, 'invalid.db');
$error = eval { Plugins::BetterCallBliss::ScanDatabaseSnapshot::capture($missing, $invalid_output); 1 };
ok(!$error && !-e $missing && !-e $invalid_output,
    'a missing source is rejected without creating source or destination');
my $corrupt = File::Spec->catfile($dir, 'corrupt.db');
open my $fh, '>', $corrupt or die $!;
print {$fh} 'not a SQLite database';
close $fh;
my $failed_snapshot = File::Spec->catfile($dir, 'failed.db');
$error = eval { Plugins::BetterCallBliss::ScanDatabaseSnapshot::capture($corrupt, $failed_snapshot); 1 };
ok(!$error && !-e $failed_snapshot, 'failed SQLite backup removes its incomplete snapshot');

my $pair_dir = File::Spec->catdir($dir, 'pair');
mkdir $pair_dir or die $!;
my $pair = Plugins::BetterCallBliss::ScanDatabaseSnapshot::capture_pair(
    $source, $source, $pair_dir,
);
is_deeply([sort keys %$pair], ['bliss', 'lyrion'], 'a pair identifies each source by role');
for my $role (qw(lyrion bliss)) {
    my $dbh = DBI->connect("dbi:SQLite:dbname=$pair->{$role}", '', '',
        { RaiseError => 1, PrintError => 0, sqlite_open_flags => 1 });
    is($dbh->selectrow_array('SELECT title FROM tracks WHERE id=1'), 'uncommitted',
        "$role snapshot contains the committed source data");
    $dbh->disconnect;
}

my $failure_dir = File::Spec->catdir($dir, 'failure');
mkdir $failure_dir or die $!;
$error = eval { Plugins::BetterCallBliss::ScanDatabaseSnapshot::capture_pair(
    $source, $corrupt, $failure_dir); 1 };
opendir my $dh, $failure_dir or die $!;
my @remaining = grep { $_ ne '.' && $_ ne '..' } readdir $dh;
closedir $dh;
ok(!$error && !@remaining, 'failure to capture the second database removes the first snapshot');

my $collision_dir = File::Spec->catdir($dir, 'collision');
mkdir $collision_dir or die $!;
my $existing = File::Spec->catfile($collision_dir, 'bliss-snapshot.db');
open my $existing_fh, '>', $existing or die $!;
print {$existing_fh} 'preserve this';
close $existing_fh;
$error = eval { Plugins::BetterCallBliss::ScanDatabaseSnapshot::capture_pair(
    $source, $source, $collision_dir); 1 };
open $existing_fh, '<', $existing or die $!;
my $existing_contents = do { local $/; <$existing_fh> };
close $existing_fh;
ok(!$error && $existing_contents eq 'preserve this'
    && !-e File::Spec->catfile($collision_dir, 'lyrion-snapshot.db'),
    'a destination collision preserves the existing file and removes only the new snapshot');

my $sentinel = File::Spec->catfile($pair_dir, 'unrelated.txt');
open my $sentinel_fh, '>', $sentinel or die $!;
print {$sentinel_fh} 'untouched';
close $sentinel_fh;
Plugins::BetterCallBliss::ScanDatabaseSnapshot::cleanup_pair($pair_dir);
ok(!-e $pair->{lyrion} && !-e $pair->{bliss} && -f $sentinel,
    'cleanup removes only the named job snapshots and preserves unrelated files');

SKIP: {
    skip 'requires fork and waitpid', 1 if $^O eq 'MSWin32';
    my $locked_source = File::Spec->catfile($dir, 'locked.db');
    my $locked_dest = File::Spec->catfile($dir, 'locked-snapshot.db');
    my $locker = DBI->connect("dbi:SQLite:dbname=$locked_source", '', '',
        { RaiseError => 1, PrintError => 0, AutoCommit => 1 });
    $locker->do('CREATE TABLE tracks (id INTEGER)');
    $locker->do('BEGIN EXCLUSIVE');
    my $pid = fork();
    die 'fork failed' unless defined $pid;
    unless ($pid) {
        $locker->{InactiveDestroy} = 1;
        eval { Plugins::BetterCallBliss::ScanDatabaseSnapshot::capture($locked_source, $locked_dest) };
        POSIX::_exit($@ ? 0 : 1);
    }
    my ($waited, $status) = (0, 0);
    my $deadline = time + 6;
    while (time < $deadline) {
        $waited = waitpid($pid, WNOHANG);
        if ($waited == $pid) { $status = $?; last }
        sleep 0.05;
    }
    if ($waited != $pid) { kill 'TERM', $pid; waitpid($pid, 0) }
    $locker->do('ROLLBACK');
    $locker->disconnect;
    ok($waited == $pid && $status == 0 && !-e $locked_dest,
        'an exclusively locked source fails within a bounded interval and leaves no snapshot');
}
$writer->disconnect;
done_testing;
