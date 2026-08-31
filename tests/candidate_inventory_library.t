use strict;
use warnings;
use FindBin;
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;
use DBI;

BEGIN {
    package TestLog;
    sub info { }

    package Slim::Utils::Log;
    sub logger { return bless {}, 'TestLog' }
    $INC{'Slim/Utils/Log.pm'} = __FILE__;

    package Slim::Music::Import;
    sub lastScanTime { return 12345 }
    $INC{'Slim/Music/Import.pm'} = __FILE__;

    package Slim::Schema;
    our $dbh;
    sub dbh { return $dbh }
    $INC{'Slim/Schema.pm'} = __FILE__;

    package Slim::Utils::Misc;
    sub fileURLFromPath {
        my $path = $_[0];
        $path =~ s{\\}{/}g;
        return 'file://' . $path;
    }
    sub pathFromFileURL {
        my $url = $_[0];
        $url =~ s{^file://}{};
        return $url;
    }
    $INC{'Slim/Utils/Misc.pm'} = __FILE__;

    package Slim::Utils::Unicode;
    sub utf8decode_locale { return $_[0] }
    sub utf8encode_locale { return $_[0] }
    $INC{'Slim/Utils/Unicode.pm'} = __FILE__;
}

use lib "$FindBin::Bin/..";
require Plugins::BetterCallBliss::CandidateInventory;

my $root = tempdir(CLEANUP => 1);
my $lms_path = File::Spec->catfile($root, 'library.db');
my $bliss_path = File::Spec->catfile($root, 'bliss.db');

$Slim::Schema::dbh = DBI->connect(
    "dbi:SQLite:dbname=$lms_path", '', '', {RaiseError => 1},
);
$Slim::Schema::dbh->do(
    'CREATE TABLE tracks (id INTEGER PRIMARY KEY, url TEXT, tracknum INTEGER, remote INTEGER, audio INTEGER)'
);
$Slim::Schema::dbh->do(
    'CREATE TABLE library_track (library TEXT, track INTEGER)'
);
$Slim::Schema::dbh->do(
    q{INSERT INTO tracks VALUES (1, 'file:///music/allowed.flac', 1, 0, 1)}
);
$Slim::Schema::dbh->do(
    q{INSERT INTO tracks VALUES (2, 'file:///music/outside.flac', 2, 0, 1)}
);
$Slim::Schema::dbh->do(
    q{INSERT INTO library_track VALUES ('4d2ba37f', 1)}
);

my $bliss = DBI->connect(
    "dbi:SQLite:dbname=$bliss_path", '', '', {RaiseError => 1},
);
$bliss->do(
    'CREATE TABLE TracksV2 (File TEXT, Title TEXT, Artist TEXT, Album TEXT, Ignore INTEGER)'
);
$bliss->do(q{INSERT INTO TracksV2 VALUES ('allowed.flac', 'Allowed', 'A', 'One', 0)});
$bliss->do(q{INSERT INTO TracksV2 VALUES ('outside.flac', 'Outside', 'B', 'Two', 0)});
$bliss->do(q{INSERT INTO TracksV2 VALUES ('stale.flac', 'Stale', 'C', 'Three', 0)});
$bliss->disconnect;

Plugins::BetterCallBliss::CandidateInventory::init($root);
my $capability = {database => $bliss_path, music_roots => ['/music']};
my $library = {
    id => '4d2ba37f',
    name => 'All Music without Audiobooks',
    virtual => 1,
};
my $first = Plugins::BetterCallBliss::CandidateInventory::prepare(
    $capability, 'bliss-fixture-v1', $library,
);
is($first->{status}->{allowed_row_count}, 1,
    'only the Bliss row inside the selected virtual library is allowed');
is($first->{status}->{virtual_library_excluded_bliss_row_count}, 1,
    'an LMS-matched Bliss row outside the virtual library is counted separately');
is($first->{status}->{unmatched_row_count}, 1,
    'a genuinely stale Bliss row remains in the non-LMS audit');
is($first->{status}->{candidate_library_name}, 'All Music without Audiobooks',
    'the frozen candidate-library name is retained for UX and logs');

$Slim::Schema::dbh->do(
    q{INSERT INTO library_track VALUES ('4d2ba37f', 2)}
);
my $second = Plugins::BetterCallBliss::CandidateInventory::prepare(
    $capability, 'bliss-fixture-v1', $library,
);
is($second->{status}->{allowed_row_count}, 2,
    'changed virtual-library membership invalidates the cached allowlist');
is($second->{status}->{cache_state}, 'miss',
    'membership changes force a fresh inventory even without an LMS scan');

$Slim::Schema::dbh->disconnect;
done_testing();
