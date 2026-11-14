use strict;
use warnings;
use FindBin;
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;
use DBI;
use JSON::XS;
use Time::HiRes ();

BEGIN {
    package main;
    sub ISWINDOWS () { 0 }

    package TestLog;
    our @info;
    sub info { push @info, $_[1] }
    sub warn { }

    package Slim::Control::Request;
    our ($listener, $subscriptions);
    sub subscribe { $listener = $_[0]; $subscriptions++ }
    $INC{'Slim/Control/Request.pm'} = __FILE__;

    package Slim::Utils::OSDetect;
    sub dirsFor { return $Slim::Utils::Prefs::cache }
    $INC{'Slim/Utils/OSDetect.pm'} = __FILE__;

    package Slim::Utils::Log;
    sub logger { return bless {}, 'TestLog' }
    $INC{'Slim/Utils/Log.pm'} = __FILE__;

    package Slim::Music::Import;
    our $scan = 12345;
    sub lastScanTime { return $scan }
    $INC{'Slim/Music/Import.pm'} = __FILE__;

    package Slim::Music::VirtualLibraries;
    our $available = 1;
    sub getRealId { return $available && $_[1] eq '4d2ba37f' ? $_[1] : undef }
    $INC{'Slim/Music/VirtualLibraries.pm'} = __FILE__;

    package TestServerPrefs;
    sub get { return $Slim::Utils::Prefs::cache }
    package Slim::Utils::Prefs;
    our $cache;
    sub preferences { return bless {}, 'TestServerPrefs' }
    sub dir { return $cache }
    $INC{'Slim/Utils/Prefs.pm'} = __FILE__;

    package Slim::Schema;
    our $dbh;
    sub dbh { return $dbh }
    $INC{'Slim/Schema.pm'} = __FILE__;

    package Slim::Utils::Misc;
    sub getMediaDirs { return ['/music'] }
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

    package Slim::Utils::Timers;
    our @pending;
    sub setTimer { push @pending, $_[2] }
    $INC{'Slim/Utils/Timers.pm'} = __FILE__;
}

use lib "$FindBin::Bin/..";
require Plugins::BetterCallBliss::CandidateInventory;

my $root = tempdir(CLEANUP => 1);
$Slim::Utils::Prefs::cache = $root;
my $lms_path = File::Spec->catfile($root, 'library.db');
my $bliss_path = File::Spec->catfile($root, 'bliss.db');

$Slim::Schema::dbh = DBI->connect(
    "dbi:SQLite:dbname=$lms_path", '', '', {RaiseError => 1},
);
$Slim::Schema::dbh->do(
    'CREATE TABLE tracks (id INTEGER PRIMARY KEY, url TEXT, tracknum INTEGER, remote INTEGER, audio INTEGER, musicbrainz_id TEXT, primary_artist INTEGER)'
);
$Slim::Schema::dbh->do(
    'CREATE TABLE contributors (id INTEGER PRIMARY KEY, musicbrainz_id TEXT, name TEXT)'
);
$Slim::Schema::dbh->do(
    'CREATE TABLE contributor_track (role INTEGER, contributor INTEGER, track INTEGER)'
);
$Slim::Schema::dbh->do(
    'CREATE TABLE library_track (library TEXT, track INTEGER)'
);
$Slim::Schema::dbh->do(
    q{INSERT INTO tracks VALUES (1, 'file:///music/allowed.flac', 1, 0, 1, '11111111-1111-4111-8111-111111111111', 10)}
);
$Slim::Schema::dbh->do(
    q{INSERT INTO tracks VALUES (2, 'file:///music/outside.flac', 2, 0, 1, NULL, 20)}
);
$Slim::Schema::dbh->do(
    q{INSERT INTO contributors VALUES (10, '22222222-2222-4222-8222-222222222222', 'Queen')}
);
$Slim::Schema::dbh->do(q{INSERT INTO contributors VALUES (20, 'not-an-mbid', 'Outside')});
$Slim::Schema::dbh->do(q{INSERT INTO contributor_track VALUES (1, 10, 1)});
$Slim::Schema::dbh->do(q{INSERT INTO contributor_track VALUES (1, 20, 2)});
$Slim::Schema::dbh->do(
    q{INSERT INTO library_track VALUES ('4d2ba37f', 1)}
);
$Slim::Schema::dbh->do('ALTER TABLE tracks ADD COLUMN urlmd5 TEXT');
$Slim::Schema::dbh->do(q{UPDATE tracks SET urlmd5 = 'allowed' WHERE id = 1});
$Slim::Schema::dbh->do(q{UPDATE tracks SET urlmd5 = 'outside' WHERE id = 2});
$Slim::Schema::dbh->do('ALTER TABLE tracks ADD COLUMN secs REAL');
$Slim::Schema::dbh->do(q{UPDATE tracks SET secs = 234.567 WHERE id = 1});
$Slim::Schema::dbh->do(
    'CREATE TABLE tracks_persistent (urlmd5 TEXT PRIMARY KEY, playcount INTEGER)'
);
$Slim::Schema::dbh->do(q{INSERT INTO tracks_persistent VALUES ('allowed', 7)});

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

if ($ENV{BLISS_PRELOAD_LAB} && $ENV{BLISS_LAB_SOURCE}) {
    $INC{'Plugins/BlissMixerLab/RepeatIdentitySnapshot.pm'} = __FILE__;
    my $lab_module = File::Spec->catfile($ENV{BLISS_LAB_SOURCE}, 'BlissMixerLab', 'CandidateLibrarySnapshot.pm');
    require $lab_module;
    ok(eval { Plugins::BlissMixerLab::CandidateLibrarySnapshot::init_shared_refresh(); 1 },
        'Lab can register the shared component before Better Call Bliss');
}
Plugins::BetterCallBliss::CandidateInventory::init($root);
my $capability = {database => $bliss_path, music_roots => ['/music']};
my $library = {
    id => '4d2ba37f',
    name => 'All Music without Audiobooks',
    virtual => 1,
};
{
    no warnings 'redefine';
    my $error;
    local *Plugins::BetterCallBliss::CandidateInventory::_register_shared_bundle = sub { die 'incompatible bundle' };
    local *Plugins::BetterCallBliss::CandidateInventory::_start_next_async_prepare = sub {};
    Plugins::BetterCallBliss::CandidateInventory::prepare_async($capability, 'bliss-fixture-v1', $library,
        sub {}, sub { $error = shift });
    like($error || '', qr/incompatible bundle/, 'preview refuses incompatible shared code before starting a worker');
    Plugins::BetterCallBliss::CandidateInventory::shutdown();
}
my $shared_dir = File::Spec->catdir($root, 'shared-inventory');
mkdir $shared_dir or die $!;
my $shared = eval { Plugins::BetterCallBliss::CandidateInventory::_shared_candidate_rows(
    $capability, $library, $shared_dir, sub { $_[0] eq '4d2ba37f' },
) };
is_deeply($shared && $shared->{inventory}->{row_ids}, [1], 'shared inventory selects only the frozen virtual-library rows');
my ($shared_again, $fingerprint_passes);
{
    no warnings 'redefine';
    my $original_pass = \&Plugins::BlissLibrary::SourceIdentity::_pass;
    local *Plugins::BlissLibrary::SourceIdentity::_pass = sub { $fingerprint_passes++; $original_pass->(@_) };
    $shared_again = eval { Plugins::BetterCallBliss::CandidateInventory::_shared_candidate_rows(
        $capability, $library, $shared_dir, sub { $_[0] eq '4d2ba37f' },
    ) };
}
is($shared_again && $shared_again->{state}, 'cached', 'Better Call Bliss reuses the shared inventory');
is($fingerprint_passes, 4, 'one preview worker fingerprints each database only once per validation session');
my $missing_shared = eval { Plugins::BetterCallBliss::CandidateInventory::_shared_candidate_rows(
    $capability, $library, $shared_dir, sub { 0 },
); 1 };
ok(!$missing_shared, 'shared inventory refuses an unavailable library');
my $agrees = eval { Plugins::BetterCallBliss::CandidateInventory::_assert_shared_rows($shared->{inventory}, [1]); 1 };
ok($agrees, 'host metadata accepts the same allowed rows as the shared inventory');
my $disagrees = eval { Plugins::BetterCallBliss::CandidateInventory::_assert_shared_rows($shared->{inventory}, [2]); 1 };
ok(!$disagrees, 'host metadata cannot silently use a different allowed set');
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
is_deeply(
    $first->{identities},
    [{
        candidate_id => 'bliss-row-1', row_id => 1, lms_track_id => 1,
        duration_ms => 234567,
        lms_urlmd5 => 'allowed',
        title => 'Allowed', artist => 'A',
        recording_mbid => '11111111-1111-4111-8111-111111111111',
        artist_mbid => '22222222-2222-4222-8222-222222222222',
    }],
    'the cached inventory exposes local identities for plugin-side guidance resolution',
);
is($first->{identity_artifact}->{schema_identity},
    'eligible-candidate-identities-v1',
    'the provider-facing identity artifact uses the optimizer schema identity');
open my $identity_file, '<:raw', $first->{identity_artifact}->{path} or die $!;
my $identity_json = do { local $/; <$identity_file> };
close $identity_file;
is(JSON::XS->new->decode($identity_json)->{candidates}->[0]->{duration_ms}, 234567,
    'the hash-bound optimizer identity artifact includes the candidate duration');
is($first->{identity_artifact}->{kind},
    'eligible-candidate-identities-v1',
    'the provider-facing identity artifact carries the native-provider kind');
ok(-r $first->{identity_artifact}->{path},
    'the provider-facing identity artifact is persisted separately from the allowlist');
open my $inventory_fh, '<:raw', $first->{artifact}->{path}
    or die "Cannot read $first->{artifact}->{path}: $!";
my $inventory_payload = JSON::XS->new->decode(do { local $/; <$inventory_fh> });
close $inventory_fh;
ok(!exists $inventory_payload->{candidate_identities},
    'the native allowlist stays compact and excludes the plugin-private identity index');
ok(-r $first->{identity_lookup_path},
    'candidate identities are persisted as an indexed sidecar');
my $identity_lookup = DBI->connect(
    'dbi:SQLite:dbname=' . $first->{identity_lookup_path}, '', '',
    {RaiseError => 1},
);
is($identity_lookup->selectrow_array(
    'SELECT COUNT(1) FROM candidate_identity'
), 1, 'the identity sidecar indexes every eligible candidate');
is($identity_lookup->selectrow_array(
    'SELECT recording_artist FROM candidate_identity LIMIT 1'
), 'a', 'the identity sidecar stores normalized lookup keys');
$identity_lookup->disconnect;
ok(-r $first->{track_identity_artifact}->{path},
    'the complete stable artist-identity snapshot is persisted');
is($first->{track_identity_artifact}->{schema_identity},
    'lyrion-track-identities-v1',
    'the repeat-identity artifact uses the shared native schema');
my $repeat_identity = DBI->connect(
    'dbi:SQLite:dbname=' . $first->{track_identity_artifact}->{path}, '', '',
    {RaiseError => 1, sqlite_open_flags => 1},
);
like($repeat_identity->selectrow_array(
    q{SELECT value FROM metadata WHERE key='media_roots_identity'}
), qr/^[0-9a-f]{64}$/,
    'the repeat-identity artifact is bound to the media-root mapping');
is($repeat_identity->selectrow_array(
    q{SELECT canonical_key FROM track_artist_identity WHERE database_file='allowed.flac'}
), 'artist-mbid:22222222-2222-4222-8222-222222222222',
    'artist MBID is the preferred repeat identity');
is($repeat_identity->selectrow_array(
    q{SELECT canonical_key FROM track_artist_identity WHERE database_file='outside.flac'}
), 'lms-contributor:20',
    'a malformed artist MBID falls back to the Lyrion contributor identity');
is($repeat_identity->selectrow_array(
    q{SELECT legacy_artist_credit FROM track_identity WHERE database_file='allowed.flac'}
), 'A', 'the snapshot retains the exact Bliss credit for compatibility mode');
$repeat_identity->disconnect;
my $cached = Plugins::BetterCallBliss::CandidateInventory::prepare(
    $capability, 'bliss-fixture-v1', $library,
);
is($cached->{status}->{cache_state}, 'memory',
    'unchanged candidate inventory is reused from memory');
is_deeply($cached->{identities}, $first->{identities},
    'a cache hit preserves the provider-resolution identity index');

Plugins::BetterCallBliss::CandidateInventory::init($root);
my $disk_cached = Plugins::BetterCallBliss::CandidateInventory::prepare(
    $capability, 'bliss-fixture-v1', $library,
);
is($disk_cached->{status}->{cache_state}, 'hit',
    'a simulated LMS restart reuses the persisted inventory');
is_deeply($disk_cached->{identities}, [],
    'a persisted cache hit avoids decoding the large legacy identity JSON');
is($disk_cached->{identity_lookup_path}, $first->{identity_lookup_path},
    'a persisted cache hit exposes the indexed identity sidecar');
is_deeply($disk_cached->{identity_artifact}, $first->{identity_artifact},
    'a persisted cache hit retains the hash-bound provider identity artifact');
is_deeply($disk_cached->{track_identity_artifact}, $first->{track_identity_artifact},
    'a persisted cache hit retains the hash-bound repeat identity artifact');

my $all_tracks = {id => '', name => 'All tracks', virtual => 0};
my ($all_result, $snapshot_rebuilds);
{
    no warnings 'redefine';
    my $original = \&Plugins::BetterCallBliss::CandidateInventory::_new_repeat_identity_snapshot;
    local *Plugins::BetterCallBliss::CandidateInventory::_new_repeat_identity_snapshot = sub {
        $snapshot_rebuilds++;
        return $original->(@_);
    };
    $all_result = Plugins::BetterCallBliss::CandidateInventory::prepare(
        $capability, 'bliss-fixture-v1', $all_tracks,
    );
}
is($snapshot_rebuilds || 0, 0,
    'building another library does not rescan and rebuild global artist identities');
is($all_result->{status}->{allowed_row_count}, 2,
    'All tracks admits both matching local Bliss rows');
is($all_result->{identities}->[0]->{duration_ms}, 234567,
    'a newly scoped library retains track duration when reusing the shared identity snapshot');
Plugins::BetterCallBliss::CandidateInventory::init($root);
my $again_virtual = Plugins::BetterCallBliss::CandidateInventory::prepare(
    $capability, 'bliss-fixture-v1', $library,
);
is($again_virtual->{status}->{cache_state}, 'hit',
    'the virtual-library cache survives an All tracks job and restart');
is($again_virtual->{status}->{allowed_row_count}, 1,
    'switching back never exposes candidates outside the requested library');
is_deeply($all_result->{track_identity_artifact}, $first->{track_identity_artifact},
    'different candidate libraries reuse the same library-wide identity snapshot');

my $state_path = Plugins::BetterCallBliss::CandidateInventory::_manifest_path_for_key(
    join('|', 'bliss-fixture-v1', 12345,
        Plugins::BetterCallBliss::CandidateInventory::_media_roots_identity(['/music']),
        Plugins::BlissLibrary::SourceIdentity::database_fingerprint($lms_path),
        '4d2ba37f', 1),
);
open my $state_fh, '<:raw', $state_path or die "Cannot read $state_path: $!";
my $state = JSON::XS->new->decode(do { local $/; <$state_fh> });
close $state_fh;
$state->{cache_key} = 'stale-media-root-binding';
open $state_fh, '>:raw', $state_path or die "Cannot write $state_path: $!";
print {$state_fh} JSON::XS->new->canonical->pretty->encode($state);
close $state_fh;
Plugins::BetterCallBliss::CandidateInventory::init($root);
my $root_rebound = Plugins::BetterCallBliss::CandidateInventory::prepare(
    $capability, 'bliss-fixture-v1', $library,
);
is($root_rebound->{status}->{cache_state}, 'miss',
    'a changed media-root cache identity rebuilds the persisted snapshot');

{
    $Slim::Schema::dbh->do(q{UPDATE contributors SET name='Changed Artist' WHERE id=10});
    $Slim::Schema::dbh->do(q{INSERT INTO library_track VALUES ('newscope', 1)});
    my $changed_scope = {id => 'newscope', name => 'New scope', virtual => 1};
    my $changed_artist = Plugins::BetterCallBliss::CandidateInventory::prepare(
        $capability, 'bliss-fixture-v1', $changed_scope,
    );
    my $snapshot = DBI->connect('dbi:SQLite:dbname=' . $changed_artist->{track_identity_artifact}{path}, '', '', {RaiseError => 1});
    my ($name) = $snapshot->selectrow_array(q{SELECT primary_artist_name FROM track_identity WHERE database_file='allowed.flac'});
    is($name, 'Changed Artist', 'another scope does not reuse artist identities after a Lyrion change within the same scan');
    $snapshot->disconnect;
    my $same_scope = Plugins::BetterCallBliss::CandidateInventory::prepare(
        $capability, 'bliss-fixture-v1', $library,
    );
    $snapshot = DBI->connect('dbi:SQLite:dbname=' . $same_scope->{track_identity_artifact}{path}, '', '', {RaiseError => 1});
    ($name) = $snapshot->selectrow_array(q{SELECT primary_artist_name FROM track_identity WHERE database_file='allowed.flac'});
    is($name, 'Changed Artist', 'the same scope also invalidates its persisted cache after a Lyrion change');
    $snapshot->disconnect;
    $Slim::Schema::dbh->do(q{UPDATE contributors SET name='Queen' WHERE id=10});
    $Slim::Schema::dbh->do(q{DELETE FROM library_track WHERE library='newscope'});
}

$Slim::Schema::dbh->do(q{UPDATE library_track SET track = 2 WHERE library = '4d2ba37f'});
my $same_count = Plugins::BetterCallBliss::CandidateInventory::prepare(
    $capability, 'bliss-fixture-v1', $library,
);
is($same_count->{status}->{cache_state}, 'miss',
    'replacing a virtual-library member invalidates the cache even when its count is unchanged');
is($same_count->{status}->{allowed_row_count}, 1,
    'the replacement snapshot contains only the currently eligible track');
$Slim::Schema::dbh->do(q{UPDATE library_track SET track = 1 WHERE library = '4d2ba37f'});

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

ok(!Plugins::BetterCallBliss::CandidateInventory->can('prepare_playcounts'),
    'the plugin no longer exposes a full-library play-count artifact collector');
ok(!Plugins::BetterCallBliss::CandidateInventory->can('prepare_playcounts_async'),
    'preview preparation no longer schedules full-library play-count collection');

$Slim::Utils::Prefs::cache = $root;
my ($async_result, $async_error, $finished);
Plugins::BetterCallBliss::CandidateInventory::prepare_async($capability, 'bliss-fixture-v1', $library,
    sub { $async_result = shift; $finished = 1 }, sub { $async_error = shift; $finished = 1 });
my $deadline = Time::HiRes::time() + 30;
while (!$finished && Time::HiRes::time() < $deadline) {
    my $timer = shift @Slim::Utils::Timers::pending;
    $timer->() if $timer;
    Time::HiRes::sleep(0.02);
}
ok($finished && !$async_error && $async_result, 'asynchronous Better Call Bliss preparation completes');
my @shared_indices = glob File::Spec->catfile($root, 'bliss-library', 'candidate-inventory', 'index-*.txt');
ok(@shared_indices, 'background preview preparation publishes a reusable shared inventory');
ok($Slim::Control::Request::listener, 'preview host subscribes to scan completion');
my @scope_records = glob File::Spec->catfile($root, 'bliss-library', 'candidate-inventory', 'scope-*.json');
is(scalar @scope_records, 1, 'successful preview library is remembered for future refresh');
is($async_result && $async_result->{status}->{allowed_row_count}, 2, 'shared preview keeps the host audit and eligible count');
ok(scalar(grep { $_ eq 'candidate_inventory stage=CacheHit allowed=2 unmatched=1 audit=' . $root . '/non-lms-bliss-rows.json' } @TestLog::info),
    'background completion retains the existing complete cache-hit log message');
{
    no warnings 'redefine';
    local *Plugins::BetterCallBliss::CandidateInventory::_candidate_library_membership = sub {
        die 'unexpected duplicate host membership scan';
    };
    my ($warm_result, $warm_error, $warm_done);
    Plugins::BetterCallBliss::CandidateInventory::prepare_async($capability, 'bliss-fixture-v1', $library,
        sub { $warm_result = shift; $warm_done = 1 }, sub { $warm_error = shift; $warm_done = 1 });
    my $warm_deadline = Time::HiRes::time() + 30;
    while (!$warm_done && Time::HiRes::time() < $warm_deadline) {
        my $timer = shift @Slim::Utils::Timers::pending;
        $timer->() if $timer;
        Time::HiRes::sleep(0.02);
    }
    ok($warm_done && !$warm_error && $warm_result,
        'a warm shared preview does not repeat the host membership scan');
    diag($warm_error) if $warm_error;
}
{
    no warnings 'redefine';
    local *Plugins::BlissLibrary::Builder::capture_source_verified = sub {
        die 'unexpected warm membership scan';
    };
    my ($result, $error, $done);
    my $started = eval {
        Plugins::BetterCallBliss::CandidateInventory::prepare_async($capability, 'bliss-fixture-v1', $library,
            sub { $result = shift; $done = 1 }, sub { $error = shift; $done = 1 });
        1;
    };
    my $until = Time::HiRes::time() + 5;
    while ($started && !$done && Time::HiRes::time() < $until) {
        my $timer = shift @Slim::Utils::Timers::pending;
        $timer->() if $timer;
        Time::HiRes::sleep(0.02);
    }
    ok($started && $done && !$error && $result,
        'an unchanged warm preview reuses verified process state without another membership scan');
}
{
    my $parent_pid = $$;
    my $parent_rebuilds = 0;
    my $original = \&Plugins::BetterCallBliss::CandidateInventory::_write_identity_lookup;
    unlink $async_result->{identity_lookup_path} or die $!;
    no warnings 'redefine';
    local *Plugins::BetterCallBliss::CandidateInventory::_write_identity_lookup = sub {
        if ($$ == $parent_pid) { $parent_rebuilds++; die 'identity index rebuilt on the event loop' }
        goto &$original;
    };
    my ($result, $error, $done);
    Plugins::BetterCallBliss::CandidateInventory::prepare_async($capability, 'bliss-fixture-v1', $library,
        sub { $result = shift; $done = 1 }, sub { $error = shift; $done = 1 });
    my $until = Time::HiRes::time() + 30;
    while (!$done && Time::HiRes::time() < $until) {
        my $timer = shift @Slim::Utils::Timers::pending;
        $timer->() if $timer;
        Time::HiRes::sleep(0.02);
    }
    ok($done && !$error && $result && -r $result->{identity_lookup_path},
        'a missing warm identity index is repaired by a worker, not the event loop');
    is($parent_rebuilds, 0, 'the event loop never attempts the expensive index rebuild');
    diag($error) if $error;
}
{
    local $Slim::Music::VirtualLibraries::available = 0;
    my ($result, $error, $done);
    Plugins::BetterCallBliss::CandidateInventory::prepare_async($capability, 'bliss-fixture-v1', $library,
        sub { $result = shift; $done = 1 }, sub { $error = shift; $done = 1 });
    my $until = Time::HiRes::time() + 30;
    while (!$done && Time::HiRes::time() < $until) {
        my $timer = shift @Slim::Utils::Timers::pending;
        $timer->() if $timer;
        Time::HiRes::sleep(0.02);
    }
    ok($done && $error && !$result, 'a deleted virtual library cannot reuse an in-process warm snapshot');
}
{
    my ($result, $error, $done);
    Plugins::BetterCallBliss::CandidateInventory::prepare_async($capability, 'bliss-fixture-removed', $library,
        sub { $result = shift; $done = 1 }, sub { $error = shift; $done = 1 });
    local $Slim::Music::VirtualLibraries::available = 0;
    my $until = Time::HiRes::time() + 30;
    while (!$done && Time::HiRes::time() < $until) {
        my $timer = shift @Slim::Utils::Timers::pending;
        $timer->() if $timer;
        Time::HiRes::sleep(0.02);
    }
    ok($done && $error && !$result, 'a library deleted during preparation cannot return a worker result');
}
{
    open my $fh, '>:raw', $async_result->{artifact}->{path} or die $!;
    print {$fh} '{"corrupt":true}'; close $fh;
    my ($recovered, $error, $done);
    Plugins::BetterCallBliss::CandidateInventory::prepare_async($capability, 'bliss-fixture-v1', $library,
        sub { $recovered = shift; $done = 1 }, sub { $error = shift; $done = 1 });
    my $until = Time::HiRes::time() + 30;
    while (!$done && Time::HiRes::time() < $until) {
        my $timer = shift @Slim::Utils::Timers::pending;
        $timer->() if $timer;
        Time::HiRes::sleep(0.02);
    }
    ok($recovered && !$error && $recovered->{status}->{allowed_row_count} == 2,
        'a damaged warm preview artifact is rebuilt rather than reused');
    diag($error) if $error;
}
{
    my ($stale_result, $stale_error, $stale_done);
    Plugins::BetterCallBliss::CandidateInventory::prepare_async($capability, 'bliss-fixture-stale', $library,
        sub { $stale_result = shift; $stale_done = 1 }, sub { $stale_error = shift; $stale_done = 1 });
    $Slim::Music::Import::scan = 12346;
    my $until = Time::HiRes::time() + 30;
    while (!$stale_done && Time::HiRes::time() < $until) {
        my $timer = shift @Slim::Utils::Timers::pending;
        $timer->() if $timer;
        Time::HiRes::sleep(0.02);
    }
    like($stale_error || '', qr/changed while the worker was running/,
        'a scan change while a worker runs is rejected before returning its result');
    ok(!$stale_result, 'a stale worker result is not returned as a valid preview inventory');
    $Slim::Music::Import::scan = 12345;
}
SKIP: {
    skip 'set BLISS_LAB_SOURCE to run the cross-host integration test', 5 unless $ENV{BLISS_LAB_SOURCE};
    $INC{'Plugins/BlissMixerLab/RepeatIdentitySnapshot.pm'} = __FILE__;
    my $lab_module = File::Spec->catfile($ENV{BLISS_LAB_SOURCE}, 'BlissMixerLab', 'CandidateLibrarySnapshot.pm');
    require $lab_module;
    my ($lab_snapshot, $lab_error, $lab_done);
    Plugins::BlissMixerLab::CandidateLibrarySnapshot::prepare_async(undef, '4d2ba37f', $bliss_path,
        sub { ($lab_snapshot, $lab_error) = @_; $lab_done = 1 });
    my $lab_deadline = Time::HiRes::time() + 30;
    while (!$lab_done && Time::HiRes::time() < $lab_deadline) {
        my $timer = shift @Slim::Utils::Timers::pending;
        $timer->() if $timer;
        Time::HiRes::sleep(0.02);
    }
    ok($lab_done && !$lab_error && $lab_snapshot, 'Lab can use the same shared cache after preview preparation');
    my $lab_files;
    if ($lab_snapshot) {
        open my $fh, '<:raw', $lab_snapshot->filename or die $!;
        $lab_files = JSON::XS->new->utf8->decode(do { local $/; <$fh> });
        close $fh;
    }
    is_deeply($lab_files, ['allowed.flac', 'outside.flac'], 'both hosts use the same current library membership');
    my @after_lab = glob File::Spec->catfile($root, 'bliss-library', 'candidate-inventory', 'index-*.txt');
    is(scalar @after_lab, scalar @shared_indices, 'Lab reuses the existing source generation rather than creating another inventory');
    is($async_result->{status}->{unmatched_row_count}, 1, 'sharing preserves Better Call Bliss unmatched-row audit');
    is($Slim::Control::Request::subscriptions, 1, 'both hosts share one scan-complete subscription');
}

{
    no warnings 'redefine';
    local *Plugins::BetterCallBliss::CandidateInventory::_parent_source_state = sub { 'unchanged-stat-fixture' };
    my ($changed_result, $changed_error, $changed_done);
    Plugins::BetterCallBliss::CandidateInventory::prepare_async($capability, 'bliss-fixture-observer', $library,
        sub { $changed_result = shift; $changed_done = 1 }, sub { $changed_error = shift; $changed_done = 1 });
    $Slim::Schema::dbh->do(q{DELETE FROM library_track WHERE library = '4d2ba37f' AND track = 2});
    my $until = Time::HiRes::time() + 30;
    while (!$changed_done && Time::HiRes::time() < $until) {
        my $timer = shift @Slim::Utils::Timers::pending;
        $timer->() if $timer;
        Time::HiRes::sleep(0.02);
    }
    ok($changed_done && $changed_error && !$changed_result,
        'same-connection membership changes invalidate a worker even when file metadata appears unchanged');
    $Slim::Schema::dbh->do(q{INSERT INTO library_track VALUES ('4d2ba37f', 2)});
}

$Slim::Schema::dbh->do(q{DELETE FROM library_track WHERE library = '4d2ba37f' AND track = 2});
my ($invalidated_result, $invalidated_error, $invalidated_done);
Plugins::BetterCallBliss::CandidateInventory::prepare_async($capability, 'bliss-fixture-v1', $library,
    sub { $invalidated_result = shift; $invalidated_done = 1 }, sub { $invalidated_error = shift; $invalidated_done = 1 });
my $invalidated_until = Time::HiRes::time() + 30;
while (!$invalidated_done && Time::HiRes::time() < $invalidated_until) {
    my $timer = shift @Slim::Utils::Timers::pending;
    $timer->() if $timer;
    Time::HiRes::sleep(0.02);
}
ok($invalidated_result && $invalidated_result->{status}->{allowed_row_count} == 1,
    'a database write invalidates the in-process warm snapshot before the next preview');
diag($invalidated_error) if $invalidated_error;
$Slim::Schema::dbh->do(q{INSERT INTO library_track VALUES ('4d2ba37f', 2)});

$Slim::Schema::dbh->do(q{INSERT INTO tracks (id, url, tracknum, remote, audio) VALUES (99, 'http://example.invalid/stream', 0, 1, 1)});
$Slim::Schema::dbh->do(q{INSERT INTO library_track VALUES ('4d2ba37f', 99)});
for my $attempt (1..2) {
    my ($result, $error, $done);
    Plugins::BetterCallBliss::CandidateInventory::prepare_async($capability, 'bliss-fixture-v1', $library,
        sub { $result = shift; $done = 1 }, sub { $error = shift; $done = 1 });
    my $until = Time::HiRes::time() + 30;
    while (!$done && Time::HiRes::time() < $until) {
        my $timer = shift @Slim::Utils::Timers::pending;
        $timer->() if $timer;
        Time::HiRes::sleep(0.02);
    }
    ok($done && !$error && $result && $result->{status}->{allowed_row_count} == 2,
        "preview $attempt handles library members that are not local audio tracks");
    diag($error) if $error;
}

$Slim::Schema::dbh->do(q{INSERT INTO tracks (id, url, tracknum, remote, audio, primary_artist, urlmd5, secs) VALUES (101, 'file:///music/nested/child.flac', 0, 0, 1, 10, 'nested', 120)});
$Slim::Schema::dbh->do(q{INSERT INTO library_track VALUES ('4d2ba37f', 101)});
my $alias_db = DBI->connect("dbi:SQLite:dbname=$bliss_path", '', '', {RaiseError => 1});
$alias_db->do(q{INSERT INTO TracksV2 VALUES ('child.flac', 'Child', 'A', 'Album', 0)});
$alias_db->do(q{INSERT INTO TracksV2 VALUES ('nested/child.flac', 'Child', 'A', 'Album', 0)});
$alias_db->disconnect;
my $nested_capability = {database => $bliss_path, music_roots => ['/music', '/music/nested']};
my ($nested_result, $nested_error, $nested_done);
Plugins::BetterCallBliss::CandidateInventory::prepare_async($nested_capability, 'bliss-fixture-nested', $library,
    sub { $nested_result = shift; $nested_done = 1 }, sub { $nested_error = shift; $nested_done = 1 });
my $nested_until = Time::HiRes::time() + 30;
while (!$nested_done && Time::HiRes::time() < $nested_until) {
    my $timer = shift @Slim::Utils::Timers::pending;
    $timer->() if $timer;
    Time::HiRes::sleep(0.02);
}
is($nested_result && $nested_result->{status}->{allowed_row_count}, 4,
    'overlapping roots admit both valid Bliss identities for the same local track');
diag($nested_error) if $nested_error;
($nested_result, $nested_error, $nested_done) = (undef, undef, 0);
Plugins::BetterCallBliss::CandidateInventory::prepare_async($nested_capability, 'bliss-fixture-nested', $library,
    sub { $nested_result = shift; $nested_done = 1 }, sub { $nested_error = shift; $nested_done = 1 });
$nested_until = Time::HiRes::time() + 30;
while (!$nested_done && Time::HiRes::time() < $nested_until) {
    my $timer = shift @Slim::Utils::Timers::pending;
    $timer->() if $timer;
    Time::HiRes::sleep(0.02);
}
ok($nested_result && $nested_result->{status}->{allowed_row_count} == 4
    && $nested_result->{status}->{candidate_library_track_count} == 3,
    'a warm overlapping-root snapshot counts each local track once');
diag($nested_error) if $nested_error;
$Slim::Schema::dbh->do(q{INSERT INTO tracks (id, url, tracknum, remote, audio) VALUES (103, 'file:///music/missing.flac', 0, 0, 1), (104, 'file:///music/nested/missing.flac', 0, 0, 1)});
($nested_result, $nested_error, $nested_done) = (undef, undef, 0);
Plugins::BetterCallBliss::CandidateInventory::prepare_async($nested_capability, 'bliss-fixture-nested', $library,
    sub { $nested_result = shift; $nested_done = 1 }, sub { $nested_error = shift; $nested_done = 1 });
$nested_until = Time::HiRes::time() + 30;
while (!$nested_done && Time::HiRes::time() < $nested_until) {
    my $timer = shift @Slim::Utils::Timers::pending;
    $timer->() if $timer;
    Time::HiRes::sleep(0.02);
}
ok($nested_result && !$nested_error && $nested_result->{status}->{allowed_row_count} == 4,
    'colliding local identities absent from Bliss do not block an unrelated library');
diag($nested_error) if $nested_error;
if ($nested_result) {
    my $snapshot = DBI->connect('dbi:SQLite:dbname=' . $nested_result->{track_identity_artifact}{path}, '', '', {RaiseError => 1});
    my ($incomplete) = $snapshot->selectrow_array(q{SELECT value FROM metadata WHERE key='incomplete_aliases'});
    is($incomplete, 1, 'a snapshot omitting a duplicate local identity is marked incomplete');
    $snapshot->disconnect;
    my $reused = Plugins::BetterCallBliss::CandidateInventory::_open_shared_repeat_identity_snapshot(
        12345, 'bliss-fixture-nested',
        Plugins::BetterCallBliss::CandidateInventory::_media_roots_identity(['/music', '/music/nested']),
        Plugins::BlissLibrary::SourceIdentity::database_fingerprint($lms_path),
    );
    ok(!$reused, 'incomplete artist identities are not reused to construct another scope');
}
$Slim::Schema::dbh->do(q{INSERT INTO tracks (id, url, tracknum, remote, audio) VALUES (102, 'file:///music/child.flac', 0, 0, 1)});
($nested_result, $nested_error, $nested_done) = (undef, undef, 0);
Plugins::BetterCallBliss::CandidateInventory::prepare_async($nested_capability, 'bliss-fixture-nested', $library,
    sub { $nested_result = shift; $nested_done = 1 }, sub { $nested_error = shift; $nested_done = 1 });
$nested_until = Time::HiRes::time() + 30;
while (!$nested_done && Time::HiRes::time() < $nested_until) {
    my $timer = shift @Slim::Utils::Timers::pending;
    $timer->() if $timer;
    Time::HiRes::sleep(0.02);
}
like($nested_error || '', qr/Ambiguous media-root identity/,
    'conflicting local tracks sharing one Bliss file identity fail closed');
ok(!$nested_result, 'an ambiguous identity cannot enter the optimizer candidate pool');

$Slim::Schema::dbh->disconnect;
done_testing();
