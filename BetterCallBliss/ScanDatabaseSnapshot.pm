package Plugins::BetterCallBliss::ScanDatabaseSnapshot;

use strict;
use warnings;
use DBI;
use Fcntl qw(O_CREAT O_EXCL O_WRONLY);
use File::Spec;

sub capture {
    my ($source, $destination) = @_;
    die 'Snapshot source is unavailable' unless defined($source) && -f $source && -r _;
    die 'Snapshot destination is missing' unless defined($destination) && length($destination);
    sysopen(my $reserved, $destination, O_CREAT | O_EXCL | O_WRONLY, 0600)
        or die "Cannot create database snapshot: $!";
    unless (close($reserved)) {
        my $error = $!;
        unlink $destination;
        die "Cannot close database snapshot: $error";
    }
    my $dbh;
    my $ok = eval {
        $dbh = DBI->connect("dbi:SQLite:dbname=$source", '', '', {
            RaiseError => 1, PrintError => 0, AutoCommit => 1, sqlite_open_flags => 1,
        }) or die 'Cannot open snapshot source';
        $dbh->sqlite_busy_timeout(2000);
        $dbh->sqlite_backup_to_file($destination);
        $dbh->disconnect;
        undef $dbh;
        1;
    };
    my $error = $@;
    eval { $dbh->disconnect if $dbh };
    unless ($ok) {
        unlink $destination;
        die $error || 'Could not create database snapshot';
    }
    return $destination;
}

sub capture_pair {
    my ($lyrion_source, $bliss_source, $directory) = @_;
    die 'Snapshot directory is unavailable' unless defined($directory) && -d $directory;
    my $lyrion = File::Spec->catfile($directory, 'lyrion-snapshot.db');
    my $bliss = File::Spec->catfile($directory, 'bliss-snapshot.db');
    capture($lyrion_source, $lyrion);
    my $ok = eval { capture($bliss_source, $bliss); 1 };
    my $error = $@;
    unless ($ok) {
        unlink $lyrion;
        die $error || 'Could not capture database pair';
    }
    return {lyrion => $lyrion, bliss => $bliss};
}

# Only call after the worker has exited, with a private directory owned by
# this job. Never remove the directory or any unrelated job artifacts.
sub cleanup_pair {
    my ($directory) = @_;
    die 'Snapshot directory is unavailable' unless defined($directory) && -d $directory && !-l $directory;
    for my $name (qw(lyrion-snapshot.db bliss-snapshot.db)) {
        for my $suffix ('', '-journal', '-wal', '-shm') {
            my $path = File::Spec->catfile($directory, $name . $suffix);
            next unless -e $path || -l $path;
            unlink($path) or die "Cannot remove job database snapshot: $!";
        }
    }
    return 1;
}

1;
