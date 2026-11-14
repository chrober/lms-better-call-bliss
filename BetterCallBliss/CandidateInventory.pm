package Plugins::BetterCallBliss::CandidateInventory;

use strict;
use DBI;
use Digest::SHA qw(sha256_hex);
use Encode qw(decode encode_utf8 FB_CROAK);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Spec;
use File::Slurp qw(read_file write_file);
use File::Spec::Functions qw(catfile);
use JSON::XS;
use POSIX qw(WNOHANG);
use Slim::Music::Import;
use Slim::Schema;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Timers;
use Slim::Utils::Unicode;
use Time::HiRes qw(time);
use Unicode::Normalize qw(NFKC);
use Plugins::BetterCallBliss::CandidateIdentity;
use Plugins::BetterCallBliss::RepeatIdentity;

my $log = Slim::Utils::Log::logger('plugin.bettercallbliss');
use constant BUILDER_REVISION => 11;
my (
    $inventory_root, $audit_path, $state_path,
    $cached_key, $cached_result, $last_status,
);
my ($lms_dbh_override, $worker_child, $worker_progress_path, $worker_membership_count);
my (@async_prepare_queue, $async_prepare_worker);
my ($fast_memo, $async_generation);

use constant ASYNC_CHUNK_ROWS => 250;
use constant ASYNC_RESUME_DELAY => 0.02;
use constant YIELD_INTERVAL_SECONDS => 0.02;

sub _yield_to_lms {
    return if $worker_child;
    main::idleStreams() if defined &main::idleStreams;
}

sub _lms_dbh {
    return $lms_dbh_override || Slim::Schema->dbh;
}

sub _worker_progress {
    my $message = shift;
    return unless $worker_progress_path;
    eval {
        _write_atomic(
            $worker_progress_path,
            _json()->encode({message => $message, updated_at => time()}),
        );
        1;
    };
}

sub _yield_to_lms_if_due {
    my $last_yield_ref = shift;
    my $now = time();
    return if defined $$last_yield_ref
        && $now - $$last_yield_ref < YIELD_INTERVAL_SECONDS;
    _yield_to_lms();
    $$last_yield_ref = $now;
}

sub _database_text {
    my $value = shift;
    return unless defined $value;
    return $value if utf8::is_utf8($value);
    my $bytes = $value;
    my $decoded = eval { decode('UTF-8', $bytes, FB_CROAK) };
    return $decoded unless $@;
    return Slim::Utils::Unicode::utf8decode_locale($value);
}

sub init {
    my $cache_root = shift;
    $inventory_root = $cache_root . '/candidate-inventory';
    $audit_path = $cache_root . '/non-lms-bliss-rows.json';
    $state_path = $inventory_root . '/current.json';
    ($cached_key, $cached_result, $last_status) = (undef, undef, undef);
    $fast_memo = undef;
    $async_generation++;
    make_path($inventory_root) unless -d $inventory_root;
    eval { _init_shared_refresh() };
    $log->warn("Could not initialize shared candidate refresh: $@") if $@;
}

sub _json {
    return JSON::XS->new->utf8->canonical->pretty;
}

sub _manifest_path_for_key {
    my $key = shift;
    return $inventory_root . '/state-' . sha256_hex(encode_utf8($key)) . '.json';
}

sub _write_atomic {
    my ($path, $bytes) = @_;
    my $temporary = $path . '.tmp-' . $$;
    write_file($temporary, {binmode => ':raw'}, $bytes);
    rename($temporary, $path) or die "Could not publish '$path': $!";
}

sub _sha256_file {
    my $path = shift;
    open my $fh, '<:raw', $path or die "Could not read '$path': $!";
    my $digest = Digest::SHA->new(256);
    my $last_yield = time();
    while (1) {
        my $bytes_read = read($fh, my $buffer, 1024 * 1024);
        die "Could not read '$path': $!" unless defined $bytes_read;
        last unless $bytes_read;
        $digest->add($buffer);
        _yield_to_lms_if_due(\$last_yield);
    }
    close $fh;
    return $digest->hexdigest;
}

sub _media_roots_identity {
    my $roots = shift || [];
    my @normalized = sort map {
        my $root = defined $_ ? NFKC($_) : '';
        $root =~ s{\\}{/}g;
        $root =~ s{/+$}{};
        $root;
    } @$roots;
    return sha256_hex(encode_utf8(join("\0", @normalized)));
}

sub _new_repeat_identity_snapshot {
    my $temporary = $inventory_root . '/track-identities.tmp-' . $$ . '.sqlite';
    unlink $temporary if -e $temporary;
    my $dbh = DBI->connect(
        "dbi:SQLite:dbname=$temporary", '', '',
        {RaiseError => 1, PrintError => 0, AutoCommit => 1, sqlite_unicode => 1},
    );
    $dbh->do('PRAGMA synchronous = OFF');
    $dbh->do('PRAGMA journal_mode = OFF');
    $dbh->do('CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    $dbh->do(
        'CREATE TABLE track_identity ('
        . 'database_file TEXT PRIMARY KEY, lms_track_id INTEGER NOT NULL, '
        . 'lms_urlmd5 TEXT, recording_mbid TEXT, primary_contributor_id INTEGER, '
        . 'primary_artist_mbid TEXT, primary_artist_name TEXT, '
        . 'legacy_artist_credit TEXT NOT NULL)'
    );
    $dbh->do(
        'CREATE TABLE track_artist_identity ('
        . 'database_file TEXT NOT NULL, role TEXT NOT NULL, canonical_key TEXT NOT NULL, '
        . 'contributor_id INTEGER, artist_mbid TEXT, artist_name TEXT NOT NULL, '
        . 'PRIMARY KEY (database_file, role, canonical_key))'
    );
    $dbh->begin_work;
    $dbh->do("INSERT INTO metadata VALUES ('schema_identity', 'lyrion-track-identities-v1')");
    return {
        path => $temporary,
        dbh => $dbh,
        insert_track => $dbh->prepare(
            'INSERT INTO track_identity VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
        ),
        insert_artist => $dbh->prepare(
            'INSERT OR IGNORE INTO track_artist_identity VALUES (?, ?, ?, ?, ?, ?)'
        ),
        update_credit => $dbh->prepare(
            'UPDATE track_identity SET legacy_artist_credit = ? WHERE database_file = ?'
        ),
    };
}

sub _publish_repeat_identity_snapshot {
    my ($snapshot, $scan_time, $database_identity, $media_roots_identity, $lyrion_identity, $incomplete_aliases) = @_;
    my $dbh = $snapshot->{dbh};
    my $metadata = $dbh->prepare('INSERT INTO metadata VALUES (?, ?)');
    $metadata->execute('lms_scan_time', int($scan_time));
    $metadata->execute('database_cache_identity', $database_identity);
    $metadata->execute('media_roots_identity', $media_roots_identity);
    $metadata->execute('lyrion_identity', $lyrion_identity);
    $metadata->execute('incomplete_aliases', $incomplete_aliases ? 1 : 0);
    $dbh->do('CREATE INDEX track_artist_file_idx ON track_artist_identity(database_file)');
    $dbh->commit;
    $dbh->disconnect;
    my $sha256 = _sha256_file($snapshot->{path});
    my $path = $inventory_root . '/track-identities-' . $sha256 . '.sqlite';
    if (-r $path) {
        unlink $snapshot->{path};
    } else {
        rename($snapshot->{path}, $path)
            or die "Could not publish '$path': $!";
    }
    return ({
        path => $path,
        sha256 => $sha256,
        schema_identity => 'lyrion-track-identities-v1',
    }, $path, $sha256);
}

sub _open_shared_repeat_identity_snapshot {
    my ($scan_time, $database_identity, $media_roots_identity, $lyrion_identity) = @_;
    return unless $state_path && -r $state_path;
    my ($dbh, $result);
    eval {
        my $state = _json()->decode(scalar read_file($state_path, binmode => ':raw'));
        die 'invalid shared snapshot state' unless ref($state) eq 'HASH';
        die 'shared snapshot builder changed' unless ($state->{builder_revision} || 0) == BUILDER_REVISION;
        my $path = $state->{track_identity_path} || '';
        my ($digest) = $path =~ /^\Q$inventory_root\E\/track-identities-([0-9a-f]{64})\.sqlite$/;
        die 'invalid shared snapshot path' unless $digest && -r $path
            && $digest eq ($state->{track_identity_sha256} || '');
        die 'shared snapshot checksum changed' unless _sha256_file($path) eq $digest;
        $dbh = DBI->connect('dbi:SQLite:dbname=' . $path, '', '', {
            RaiseError => 1, PrintError => 0, AutoCommit => 1,
            sqlite_unicode => 1, sqlite_open_flags => 1,
        }) or die 'could not open shared snapshot';
        my $rows = $dbh->selectall_arrayref('SELECT key, value FROM metadata');
        my %metadata = map { $_->[0] => $_->[1] } @$rows;
        die 'shared snapshot identity changed'
            unless ($metadata{schema_identity} || '') eq 'lyrion-track-identities-v1'
                && ($metadata{database_cache_identity} || '') eq $database_identity
                && ($metadata{lyrion_identity} || '') eq $lyrion_identity
                && !($metadata{incomplete_aliases} || 0)
                && 0 + ($metadata{lms_scan_time} || 0) == $scan_time
                && ($metadata{media_roots_identity} || '') eq $media_roots_identity;
        $result = {dbh => $dbh, path => $path, sha256 => $digest};
        1;
    } or do {
        eval { $dbh->disconnect if $dbh };
        return;
    };
    return $result;
}

sub _relative_database_file {
    my ($path, $url, $tracknum, $roots) = @_;
    $path =~ s{\\}{/}g;
    for my $configured_root (sort { length($b) <=> length($a) } @$roots) {
        my $root = $configured_root;
        $root =~ s{\\}{/}g;
        $root =~ s{/+$}{};
        next unless index($path, $root . '/') == 0;
        my $relative = substr($path, length($root) + 1);
        $relative = _database_text($relative);
        $relative .= '.CUE_TRACK.' . $tracknum
            if $url =~ /#/ && $tracknum;
        return $relative;
    }
    return;
}

sub database_file_for_track {
    my ($track, $roots) = @_;
    return _relative_database_file(
        $track->path, $track->url, $track->tracknum, $roots,
    );
}

sub _unmatched_reason {
    my ($database_file, $roots) = @_;
    my $path = $database_file;
    my $cue_track = $path =~ s/\.CUE_TRACK\.([1-9][0-9]*)$// ? 0 + $1 : 0;
    $path =~ s{\\}{/}g;
    for my $root (@$roots) {
        my $absolute = catfile($root, split(m{/}, $path));
        my $encoded = Slim::Utils::Unicode::utf8encode_locale($absolute);
        return $cue_track ? 'cue_track_not_indexed_in_lms' : 'file_not_indexed_in_lms'
            if -e $absolute || -e $encoded;
    }
    return 'file_missing_from_configured_music_folders';
}

sub _load_ledger {
    return {schema_version => 1, rows => []} unless $audit_path && -r $audit_path;
    my $bytes = eval { scalar read_file($audit_path, binmode => ':raw') };
    my $ledger = defined $bytes ? eval { _json()->decode($bytes) } : undef;
    return ref($ledger) eq 'HASH' && ref($ledger->{rows}) eq 'ARRAY'
        ? $ledger : {schema_version => 1, rows => []};
}

sub _log_cache_hit {
    my ($status) = @_;
    $log->info(
        'candidate_inventory stage=CacheHit'
        . ' allowed=' . $status->{allowed_row_count}
        . ' unmatched=' . $status->{unmatched_row_count}
        . " audit=$audit_path"
    );
}

sub _load_cached_inventory {
    my ($key, $database_identity, $scan_time, $candidate_library,
        $membership_sha256, $membership_count, $no_repair) = @_;
    my $miss = sub {
        my $reason = shift;
        $log->info("candidate_inventory stage=CacheMiss reason=$reason");
        return;
    };
    my $keyed_state_path = _manifest_path_for_key($key);
    my $loaded_state_path = -r $keyed_state_path ? $keyed_state_path : $state_path;
    return $miss->('state_unreadable') unless $loaded_state_path && -r $loaded_state_path;
    my $state_bytes = eval { scalar read_file($loaded_state_path, binmode => ':raw') };
    my $state = defined $state_bytes
        ? eval { _json()->decode($state_bytes) } : undef;
    return $miss->('state_invalid') unless ref($state) eq 'HASH';
    return $miss->('builder_revision_changed')
        unless ($state->{builder_revision} || 0) == BUILDER_REVISION;
    return $miss->('cache_identity_changed')
        unless ($state->{cache_key} || '') eq $key;
    my $path = $state->{inventory_path} || '';
    return $miss->('artifact_path_invalid')
        unless $path =~ /^\Q$inventory_root\E\/inventory-[0-9a-f]{64}\.json$/;
    return $miss->('artifact_unreadable') unless -r $path;
    my $bytes = eval { read_file($path, binmode => ':raw') };
    return $miss->('artifact_read_failed') unless defined $bytes;
    my $sha256 = sha256_hex($bytes);
    return $miss->('artifact_hash_mismatch')
        unless $sha256 eq ($state->{inventory_sha256} || '');
    my $inventory = eval { _json()->decode($bytes) };
    return $miss->('artifact_json_invalid') unless ref($inventory) eq 'HASH';
    return $miss->('artifact_schema_changed')
        unless ($inventory->{schema_identity} || '')
            eq 'lms-local-candidate-inventory-v1';
    return $miss->('artifact_database_mismatch')
        unless ($inventory->{database_cache_identity} || '') eq $database_identity;
    return $miss->('artifact_scan_mismatch')
        unless 0 + ($inventory->{lms_scan_time} || 0) == $scan_time;
    return $miss->('candidate_library_changed')
        unless ($state->{candidate_library_id} || '')
            eq ($candidate_library->{id} || '');
    return $miss->('candidate_library_count_changed')
        if defined $membership_count
            && 0 + ($state->{membership_track_count} // $state->{candidate_library_track_count} // 0)
                != $membership_count;
    return $miss->('candidate_library_membership_changed')
        if defined $membership_sha256
            && ($state->{candidate_library_membership_sha256} || '')
                ne $membership_sha256;
    return $miss->('artifact_rows_invalid')
        unless ref($inventory->{allowed_row_ids}) eq 'ARRAY';
    my $identity_path = $state->{identity_path} || '';
    return $miss->('identity_path_invalid')
        unless $identity_path
            =~ /^\Q$inventory_root\E\/identities-[0-9a-f]{64}\.json$/;
    return $miss->('identity_index_unreadable') unless -r $identity_path;
    my $identity_lookup_path = $state->{identity_lookup_path} || '';
    my $track_identity_path = $state->{track_identity_path} || '';
    return $miss->('track_identity_path_invalid')
        unless $track_identity_path
            =~ /^\Q$inventory_root\E\/track-identities-[0-9a-f]{64}\.sqlite$/
            && -r $track_identity_path;
    my ($track_identity_path_sha256) =
        $track_identity_path =~ /track-identities-([0-9a-f]{64})\.sqlite$/;
    return $miss->('track_identity_hash_mismatch')
        unless $track_identity_path_sha256
            && $track_identity_path_sha256
                eq ($state->{track_identity_sha256} || '');
    my $identity_index;
    if ($identity_lookup_path
        !~ /^\Q$inventory_root\E\/identities-[0-9a-f]{64}\.sqlite$/
        || !-r $identity_lookup_path) {
        return $miss->('identity_lookup_unavailable') if $no_repair;
        my $identity_bytes = eval {
            read_file($identity_path, binmode => ':raw')
        };
        return $miss->('identity_index_read_failed')
            unless defined $identity_bytes;
        return $miss->('identity_index_hash_mismatch')
            unless sha256_hex($identity_bytes)
                eq ($state->{identity_sha256} || '');
        $identity_index = eval { _json()->decode($identity_bytes) };
        return $miss->('identity_index_invalid')
            unless ref($identity_index) eq 'HASH'
                && ($identity_index->{schema_identity} || '')
                    eq 'eligible-candidate-identities-v1'
                && ($identity_index->{database_cache_identity} || '')
                    eq $database_identity
                && 0 + ($identity_index->{lms_scan_time} || 0) == $scan_time
                && ($identity_index->{candidate_library_id} || '')
                    eq ($candidate_library->{id} || '')
                && ref($identity_index->{candidates}) eq 'ARRAY';
        $identity_lookup_path = $inventory_root . '/identities-'
            . ($state->{identity_sha256} || '') . '.sqlite';
        eval {
            _write_identity_lookup(
                $identity_lookup_path, $identity_index->{candidates},
            );
            $state->{identity_lookup_path} = $identity_lookup_path;
            _write_atomic($loaded_state_path, _json()->encode($state));
            1;
        } or return $miss->('identity_lookup_migration_failed');
    }
    if ($loaded_state_path ne $keyed_state_path) {
        eval { _write_atomic($keyed_state_path, _json()->encode($state)); 1 }
            or return $miss->('state_migration_failed');
    }
    my $ledger = _load_ledger();
    my $status = {
        ready => 1,
        database_cache_identity => $database_identity,
        lms_scan_time => $scan_time,
        lms_local_track_count => 0 + ($inventory->{lms_local_track_count} || 0),
        usable_bliss_row_count => 0 + ($inventory->{usable_bliss_row_count} || 0),
        allowed_row_count => scalar(@{$inventory->{allowed_row_ids}}),
        unmatched_row_count => 0 + ($ledger->{current_unmatched_count} || 0),
        candidate_library_id => $candidate_library->{id} || '',
        candidate_library_name => $candidate_library->{name} || 'All tracks',
        candidate_library_track_count => 0 + ($state->{candidate_library_track_count}
            // $membership_count // 0),
        candidate_library_membership_sha256 => $membership_sha256,
        virtual_library_excluded_lms_track_count =>
            0 + ($state->{virtual_library_excluded_lms_track_count} || 0),
        virtual_library_excluded_bliss_row_count =>
            0 + ($state->{virtual_library_excluded_bliss_row_count} || 0),
        inventory_path => $path,
        inventory_sha256 => $sha256,
        audit_path => $audit_path,
        cache_state => 'hit',
    };
    return {
        artifact => {
            path => $path,
            sha256 => $sha256,
            schema_identity => 'lms-local-candidate-inventory-v1',
        },
        status => $status,
        identities => $identity_index ? $identity_index->{candidates} : [],
        identity_artifact => {
            kind => 'eligible-candidate-identities-v1',
            path => $identity_path,
            sha256 => $state->{identity_sha256},
            schema_identity => 'eligible-candidate-identities-v1',
        },
        identity_lookup_path => $identity_lookup_path,
        track_identity_artifact => {
            path => $track_identity_path,
            sha256 => $state->{track_identity_sha256},
            schema_identity => 'lyrion-track-identities-v1',
        },
    };
}

sub _write_identity_lookup {
    my ($path, $identities) = @_;
    my $temporary = $path . '.tmp-' . $$;
    unlink $temporary if -e $temporary;
    my $dbh = DBI->connect(
        "dbi:SQLite:dbname=$temporary", '', '',
        {RaiseError => 1, AutoCommit => 1},
    );
    $dbh->do('PRAGMA synchronous = OFF');
    $dbh->do('PRAGMA journal_mode = OFF');
    $dbh->do(
        'CREATE TABLE candidate_identity ('
        . 'candidate_id TEXT PRIMARY KEY, recording_mbid TEXT, '
        . 'recording_artist TEXT, recording_title TEXT, '
        . 'artist_mbid TEXT, artist_name TEXT)'
    );
    my $insert = $dbh->prepare(
        'INSERT INTO candidate_identity VALUES (?, ?, ?, ?, ?, ?)'
    );
    $dbh->begin_work;
    my $last_yield = time();
    for my $identity (@$identities) {
        $insert->execute(
            $identity->{candidate_id},
            Plugins::BetterCallBliss::CandidateIdentity::normalize_mbid(
                $identity->{recording_mbid},
            ),
            Plugins::BetterCallBliss::CandidateIdentity::normalize_text(
                $identity->{artist},
            ),
            Plugins::BetterCallBliss::CandidateIdentity::normalize_text(
                $identity->{title},
            ),
            Plugins::BetterCallBliss::CandidateIdentity::normalize_mbid(
                $identity->{artist_mbid},
            ),
            Plugins::BetterCallBliss::CandidateIdentity::normalize_text(
                $identity->{artist},
            ),
        );
        _yield_to_lms_if_due(\$last_yield);
    }
    $dbh->commit;
    $dbh->do('CREATE INDEX recording_mbid_idx ON candidate_identity(recording_mbid)');
    $dbh->do('CREATE INDEX recording_name_idx ON candidate_identity(recording_artist, recording_title)');
    $dbh->do('CREATE INDEX artist_mbid_idx ON candidate_identity(artist_mbid)');
    $dbh->do('CREATE INDEX artist_name_idx ON candidate_identity(artist_name)');
    $dbh->disconnect;
    rename($temporary, $path) or die "Could not publish '$path': $!";
}

sub _candidate_library_membership {
    my $candidate_library = shift || {};
    my $id = $candidate_library->{id} || '';
    return ({}, 'all-local-tracks', undef) unless length $id;

    my %members;
    my $digest = Digest::SHA->new(256);
    $digest->add(encode_utf8($id), "\n");
    my $sth = _lms_dbh()->prepare(
        'SELECT track FROM library_track WHERE library = ? ORDER BY track'
    );
    $sth->execute($id);
    my $last_yield = time();
    while (my ($track_id) = $sth->fetchrow_array) {
        next unless defined $track_id;
        $members{0 + $track_id} = 1;
        $digest->add("$track_id\n");
        _yield_to_lms_if_due(\$last_yield);
    }
    $sth->finish;
    return (\%members, $digest->hexdigest, scalar keys %members);
}

sub _register_shared_bundle {
    my $bundle = File::Spec->catdir(dirname(__FILE__), 'SharedInventory');
    local @INC = (File::Spec->catdir($bundle, 'lib'), @INC);
    require Plugins::BlissLibrary::BundleGuard;
    Plugins::BlissLibrary::BundleGuard::register($bundle);
    return $bundle;
}

sub _init_shared_refresh {
    my $bundle = _register_shared_bundle();
    local @INC = (File::Spec->catdir($bundle, 'lib'), @INC);
    require Plugins::BlissLibrary::LyrionRefresh;
    Plugins::BlissLibrary::BundleGuard::register($bundle);
    return Plugins::BlissLibrary::LyrionRefresh::init($bundle);
}

sub _shared_candidate_rows {
    my ($capability, $candidate_library, $shared_dir, $library_exists) = @_;
    my $bundle = _register_shared_bundle();
    local @INC = (File::Spec->catdir($bundle, 'lib'), @INC);
    require Plugins::BlissLibrary::Builder;
    require Plugins::BlissLibrary::CachedBuild;
    require Plugins::BlissLibrary::FileIdentity;
    require Plugins::BlissLibrary::SourceIdentity;
    Plugins::BlissLibrary::BundleGuard::register($bundle);
    my $id = $candidate_library->{id} || '';
    my $scope = length($id) ? {kind => 'library', id => "$id"} : {kind => 'all'};
    my $roots = $capability->{music_roots} || [];
    my $scan = '' . (Slim::Music::Import->lastScanTime() || 0);
    my $lms_path = _lms_database_path();
    my $bliss_path = $capability->{database};
    local $Plugins::BlissLibrary::SourceIdentity::session =
        Plugins::BlissLibrary::SourceIdentity::begin_session([$lms_path, $bliss_path]);
    my $roots_identity = Plugins::BlissLibrary::SourceIdentity::media_roots_fingerprint($roots);
    my %build = (lyrion_path => $lms_path, bliss_path => $bliss_path, scope => $scope,
        source => {scan_generation => $scan, media_roots => $roots_identity},
        library_exists => $library_exists,
        file_for_track => Plugins::BlissLibrary::FileIdentity::make_alias_mapper($roots));
    my ($membership_count, $membership_digest);
    my %capture = %build;
    if (length $id) {
        $membership_count = 0;
        $membership_digest = Digest::SHA->new(256);
        $membership_digest->add(encode_utf8($id), "\n");
        $capture{on_member} = sub { $membership_count++; $membership_digest->add("$_[0]\n") };
    }
    my $source = Plugins::BlissLibrary::Builder::capture_source_verified(%capture);
    for my $attempt (1..31) {
        my $result = Plugins::BlissLibrary::CachedBuild::run(dir => $shared_dir, scope => $scope, source => $source,
            fresh => sub {
                return 0 unless '' . (Slim::Music::Import->lastScanTime() || 0) eq $scan;
                return $source->{lyrion_database} eq Plugins::BlissLibrary::SourceIdentity::database_fingerprint($lms_path)
                    && $source->{bliss_database} eq Plugins::BlissLibrary::SourceIdentity::database_fingerprint($bliss_path);
            },
            build => sub { Plugins::BlissLibrary::Builder::build_verified(%build) });
        if ($result->{state} ne 'busy') {
            $log->debug('shared inventory: scope=' . (length($id) ? $id : 'all')
                . ' state=' . $result->{state} . ' key='
                . Plugins::BlissLibrary::CandidateInventory::cache_key(scope => $scope, source => $source))
                if $log->is_debug;
            $result->{host_membership_sha256} = length($id) ? $membership_digest->hexdigest : 'all-local-tracks';
            $result->{host_membership_count} = $membership_count;
            return $result;
        }
        _worker_progress('Waiting for shared candidate library');
        Time::HiRes::sleep(2) if $attempt < 31;
    }
    die 'Shared candidate inventory remained busy';
}

sub _assert_shared_rows {
    my ($shared, $rows) = @_;
    die 'Shared candidate inventory is invalid' unless ref($shared) eq 'HASH'
        && ref($shared->{row_ids}) eq 'ARRAY' && ref($rows) eq 'ARRAY';
    die 'Shared candidate inventory disagrees with host identities' unless
        join(',', @{$shared->{row_ids}}) eq join(',', @$rows);
    return 1;
}

sub _assert_shared_artifact {
    my ($shared, $path) = @_;
    my $bytes = read_file($path, binmode => ':raw');
    my $value = _json()->decode($bytes);
    die 'Host candidate artifact is invalid' unless ref($value) eq 'HASH';
    return _assert_shared_rows($shared, $value->{allowed_row_ids});
}

sub _update_audit {
    my ($unmatched, $summary, $now) = @_;
    my $ledger = _load_ledger();
    my %history = map { ($_->{identity_key} || '') => $_ } @{$ledger->{rows}};
    my %active;
    for my $row (@$unmatched) {
        my $key = sha256_hex(encode_utf8($row->{database_file}));
        $active{$key} = 1;
        my $entry = $history{$key} ||= {
            identity_key => $key,
            database_file => $row->{database_file},
            first_seen => $now,
            observations => 0,
        };
        $entry->{row_id} = $row->{row_id};
        $entry->{title} = $row->{title};
        $entry->{artist} = $row->{artist};
        $entry->{album} = $row->{album};
        $entry->{reason} = $row->{reason};
        if (defined $row->{related_lms_database_file}) {
            $entry->{related_lms_database_file} =
                $row->{related_lms_database_file};
        } else {
            delete $entry->{related_lms_database_file};
        }
        $entry->{last_seen} = $now;
        $entry->{observations} = 0 + ($entry->{observations} || 0) + 1;
        $entry->{active} = JSON::XS::true;
        delete $entry->{resolved_at};
    }
    for my $key (keys %history) {
        next if $active{$key};
        my $entry = $history{$key};
        if ($entry->{active}) {
            $entry->{resolved_at} = $now;
        }
        $entry->{active} = JSON::XS::false;
    }
    $ledger = {
        schema_version => 1,
        schema_identity => 'non-lms-bliss-row-audit-v1',
        updated_at => $now,
        database_cache_identity => $summary->{database_cache_identity},
        lms_scan_time => $summary->{lms_scan_time},
        current_unmatched_count => scalar(@$unmatched),
        historical_row_count => scalar(keys %history),
        rows => [sort {
            ($b->{active} <=> $a->{active})
                || (($a->{database_file} || '') cmp ($b->{database_file} || ''))
        } values %history],
    };
    _write_atomic($audit_path, _json()->encode($ledger));
}

sub _lyrion_database_identity {
    my $bundle = _register_shared_bundle();
    local @INC = (File::Spec->catdir($bundle, 'lib'), @INC);
    require Plugins::BlissLibrary::SourceIdentity;
    return Plugins::BlissLibrary::SourceIdentity::database_fingerprint(_lms_database_path());
}

sub prepare {
    my ($capability, $database_identity, $candidate_library) = @_;
    die "Candidate inventory cache is not initialized" unless $inventory_root;
    $candidate_library ||= {id => '', name => 'All tracks'};
    my $scan_time_value = Slim::Music::Import->lastScanTime() || 0;
    my $scan_time = int($scan_time_value);
    my $roots = $capability->{music_roots} || [];
    my $media_roots_identity = _media_roots_identity($roots);
    my ($library_members, $membership_sha256, $membership_count);
    my $shared_inventory;
    if ($worker_child) {
        require Slim::Utils::Prefs;
        require Slim::Music::VirtualLibraries;
        my $cache = Slim::Utils::Prefs::preferences('server')->get('cachedir');
        die 'Lyrion cache directory is unavailable' unless defined($cache) && -d $cache;
        my $shared_dir = File::Spec->catdir($cache, 'bliss-library', 'candidate-inventory');
        make_path($shared_dir) unless -d $shared_dir;
        _worker_progress('Rebuilding candidate library: resolving shared membership');
        my $shared = _shared_candidate_rows($capability, $candidate_library, $shared_dir, sub {
            my $real = Slim::Music::VirtualLibraries->getRealId($_[0]);
            return defined($real) && $real eq $_[0];
        });
        $shared_inventory = $shared->{inventory};
        $membership_sha256 = $shared->{host_membership_sha256};
        $membership_count = $shared->{host_membership_count};
    } else {
        ($library_members, $membership_sha256, $membership_count) =
            _candidate_library_membership($candidate_library);
    }
    my $lyrion_identity;
    if ($shared_inventory) {
        $lyrion_identity = $shared_inventory->{source}->{lyrion_database};
    } else {
        $lyrion_identity = _lyrion_database_identity();
    }
    die 'Lyrion database identity is unavailable' unless defined($lyrion_identity) && length($lyrion_identity);
    $worker_membership_count = $membership_count if $worker_child;
    my $key = join('|', $database_identity, $scan_time,
        $media_roots_identity, $lyrion_identity,
        $candidate_library->{id} || '', defined $membership_count
            ? $membership_count : 'all');
    if ($cached_result && ($cached_key || '') eq $key
        && ($cached_result->{status}->{candidate_library_membership_sha256} || '')
            eq ($membership_sha256 || '')) {
        _assert_shared_artifact($shared_inventory, $cached_result->{artifact}->{path}) if $shared_inventory;
        $cached_result->{status}->{cache_state} = 'memory';
        return $cached_result;
    }
    if (my $disk = _load_cached_inventory(
        $key, $database_identity, $scan_time, $candidate_library,
        $membership_sha256, $membership_count,
    )) {
        _assert_shared_artifact($shared_inventory, $disk->{artifact}->{path}) if $shared_inventory;
        $cached_key = $key;
        $cached_result = $disk;
        $last_status = $disk->{status};
        _log_cache_hit($last_status);
        return $cached_result;
    }

    if ($shared_inventory) {
        my ($members, $digest, $count) = _candidate_library_membership($candidate_library);
        die 'Candidate library changed while preparing host identities'
            unless $digest eq $membership_sha256
                && (!defined($count) && !defined($membership_count)
                    || defined($count) && defined($membership_count) && $count == $membership_count);
        $library_members = $members;
    }

    my (%lms_files, %candidate_files, %lms_files_folded, %ambiguous_folded,
        %lms_identity_for);
    my (%file_owner, %ambiguous_files, %counted_tracks, %counted_candidates);
    my $lms_track_count = 0;
    my $candidate_library_track_count = 0;
    my $bundle = _register_shared_bundle();
    local @INC = (File::Spec->catdir($bundle, 'lib'), @INC);
    require Plugins::BlissLibrary::FileIdentity;
    my $alias_mapper = Plugins::BlissLibrary::FileIdentity::make_alias_mapper($roots);
    my $shared_snapshot = _open_shared_repeat_identity_snapshot(
        $scan_time, $database_identity, $media_roots_identity, $lyrion_identity,
    );
    my $repeat_snapshot = $shared_snapshot ? undef : _new_repeat_identity_snapshot();
    _worker_progress('Rebuilding candidate library: scanning local LMS tracks');
    my %duration_seconds;
    if ($shared_snapshot) {
        my $duration_sth = _lms_dbh()->prepare(
            'SELECT id, secs FROM tracks WHERE remote = 0 AND audio = 1'
        );
        $duration_sth->execute;
        my $last_yield = time();
        while (my ($id, $seconds) = $duration_sth->fetchrow_array) {
            $duration_seconds{$id} = $seconds if defined $seconds && $seconds > 0;
            _yield_to_lms_if_due(\$last_yield);
        }
        $duration_sth->finish;
    }
    my $lms_sth = $shared_snapshot ? $shared_snapshot->{dbh}->prepare(
        'SELECT lms_track_id, database_file, lms_urlmd5, recording_mbid, '
        . 'primary_contributor_id, primary_artist_mbid, primary_artist_name FROM track_identity'
    ) : _lms_dbh()->prepare(
        'SELECT tracks.id, tracks.url, tracks.tracknum, tracks.urlmd5, tracks.musicbrainz_id, tracks.secs, '
        . 'contributors.id, contributors.musicbrainz_id, contributors.name FROM tracks '
        . 'LEFT JOIN contributors ON contributors.id = tracks.primary_artist '
        . 'WHERE tracks.remote = 0 AND tracks.audio = 1'
    );
    $lms_sth->execute;
    my $lms_last_yield = time();
    while (my @row = $lms_sth->fetchrow_array) {
        my ($track_id, $database_file, $urlmd5, $recording_mbid, $seconds,
            $primary_contributor_id, $artist_mbid, $artist_name);
        my @database_files;
        if ($shared_snapshot) {
            ($track_id, $database_file, $urlmd5, $recording_mbid,
                $primary_contributor_id, $artist_mbid, $artist_name) = @row;
            $seconds = $duration_seconds{$track_id};
            @database_files = ($database_file);
        } else {
            my ($url, $tracknum);
            ($track_id, $url, $tracknum, $urlmd5, $recording_mbid, $seconds,
                $primary_contributor_id, $artist_mbid, $artist_name) = @row;
            @database_files = @{$alias_mapper->($url, $tracknum)};
        }
        @database_files = grep { defined($_) && length($_) } @database_files;
        next unless @database_files;
        $lms_track_count++ unless $counted_tracks{$track_id}++;
        my $is_candidate = !length($candidate_library->{id} || '') || $library_members->{0 + $track_id};
        $candidate_library_track_count++ if $is_candidate && !$counted_candidates{$track_id}++;
        for my $database_file (@database_files) {
            if (exists($file_owner{$database_file}) && $file_owner{$database_file} != $track_id) {
                $ambiguous_files{$database_file} = [$file_owner{$database_file}, $track_id];
                next;
            }
            $file_owner{$database_file} = $track_id;
            $repeat_snapshot->{insert_track}->execute(
                $database_file, 0 + $track_id, $urlmd5, $recording_mbid,
                $primary_contributor_id, $artist_mbid, $artist_name,
                defined $artist_name ? $artist_name : '',
            ) if $repeat_snapshot;
            $lms_files{$database_file} = 1;
            if ($is_candidate) {
                $candidate_files{$database_file} = 1;
                $lms_identity_for{$database_file} = {
                    lms_track_id => 0 + $track_id,
                    defined $seconds && $seconds > 0
                        ? (duration_ms => int($seconds * 1000 + 0.5)) : (),
                    defined $urlmd5 && length $urlmd5
                        ? (lms_urlmd5 => "$urlmd5") : (),
                    defined $recording_mbid && length $recording_mbid
                        ? (recording_mbid => "$recording_mbid") : (),
                    defined $artist_mbid && length $artist_mbid
                        ? (artist_mbid => "$artist_mbid") : (),
                };
            }
            my $folded = lc($database_file);
            if (exists $lms_files_folded{$folded}
                && $lms_files_folded{$folded} ne $database_file) {
                $ambiguous_folded{$folded} = 1;
            } else {
                $lms_files_folded{$folded} = $database_file;
            }
        }
        _yield_to_lms_if_due(\$lms_last_yield);
    }
    $lms_sth->finish;

    if ($shared_snapshot) {
        $shared_snapshot->{dbh}->disconnect;
    } else {
    _worker_progress('Rebuilding candidate library: collecting artist identities');
    my $artist_sth = _lms_dbh()->prepare(
        'SELECT tracks.url, tracks.tracknum, contributor_track.role, contributors.id, '
        . 'contributors.musicbrainz_id, contributors.name FROM contributor_track '
        . 'JOIN tracks ON tracks.id = contributor_track.track '
        . 'JOIN contributors ON contributors.id = contributor_track.contributor '
        . 'WHERE tracks.remote = 0 AND tracks.audio = 1 '
        . 'AND contributor_track.role IN (1, 6) '
        . 'ORDER BY contributor_track.track, contributor_track.role, contributors.id'
    );
    $artist_sth->execute;
    my $artist_last_yield = time();
    while (my ($url, $tracknum, $role, $contributor_id, $artist_mbid, $artist_name)
        = $artist_sth->fetchrow_array) {
        my @database_files = @{$alias_mapper->($url, $tracknum)};
        my $canonical_key = Plugins::BetterCallBliss::RepeatIdentity::canonical_artist_key(
            $artist_mbid, $contributor_id, $artist_name,
        );
        next unless defined $canonical_key;
        for my $database_file (@database_files) {
            next unless defined $database_file && $lms_files{$database_file};
            $repeat_snapshot->{insert_artist}->execute(
                $database_file, int($role) == 6 ? 'TRACKARTIST' : 'ARTIST',
                $canonical_key, $contributor_id, $artist_mbid,
                defined $artist_name ? $artist_name : '',
            );
        }
        _yield_to_lms_if_due(\$artist_last_yield);
    }
    $artist_sth->finish;
    }

    _worker_progress('Rebuilding candidate library: matching Bliss rows');
    my $dbh = DBI->connect(
        'dbi:SQLite:dbname=' . $capability->{database}, '', '',
        {
            RaiseError => 1,
            PrintError => 0,
            AutoCommit => 1,
            sqlite_unicode => 1,
            sqlite_open_flags => 1,
        },
    );
    die "Could not open bliss.db read-only" unless $dbh;
    my $sth = $dbh->prepare(
        'SELECT rowid, File, Title, Artist, Album, Ignore IS NOT 1 FROM TracksV2 ORDER BY rowid'
    );
    $sth->execute;
    my (@allowed, @candidate_identities, @unmatched);
    my $usable_count = 0;
    my $virtual_library_excluded_bliss_row_count = 0;
    my $bliss_last_yield = time();
    while (my ($row_id, $file, $title, $artist, $album, $eligible) = $sth->fetchrow_array) {
        my $database_file = _database_text($file);
        die "Ambiguous media-root identity '$database_file' maps to local tracks $ambiguous_files{$database_file}[0] and $ambiguous_files{$database_file}[1]"
            if defined($database_file) && exists($ambiguous_files{$database_file});
        next unless $eligible;
        $usable_count++;
        $repeat_snapshot->{update_credit}->execute(
            defined $artist ? $artist : '', $database_file,
        ) if $repeat_snapshot && defined $database_file && $lms_files{$database_file};
        my $folded = defined $database_file ? lc($database_file) : '';
        if (defined $database_file && $candidate_files{$database_file}) {
            push @allowed, 0 + $row_id;
            my $lms_identity = $lms_identity_for{$database_file} || {};
            push @candidate_identities, {
                candidate_id => 'bliss-row-' . (0 + $row_id),
                row_id => 0 + $row_id,
                lms_track_id => 0 + ($lms_identity->{lms_track_id} || 0),
                defined $lms_identity->{duration_ms} && $lms_identity->{duration_ms} > 0
                    ? (duration_ms => 0 + $lms_identity->{duration_ms}) : (),
                defined $lms_identity->{lms_urlmd5}
                    ? (lms_urlmd5 => $lms_identity->{lms_urlmd5}) : (),
                title => defined $title ? $title : '',
                artist => defined $artist ? $artist : '',
                defined $lms_identity->{recording_mbid}
                    ? (recording_mbid => $lms_identity->{recording_mbid}) : (),
                defined $lms_identity->{artist_mbid}
                    ? (artist_mbid => $lms_identity->{artist_mbid}) : (),
            };
            _yield_to_lms_if_due(\$bliss_last_yield);
            next;
        }
        if (defined $database_file && $lms_files{$database_file}) {
            $virtual_library_excluded_bliss_row_count++;
            _yield_to_lms_if_due(\$bliss_last_yield);
            next;
        }
        my $case_variant = defined $database_file
            && !$ambiguous_folded{$folded}
            && exists $lms_files_folded{$folded}
            ? $lms_files_folded{$folded} : undef;
        push @unmatched, {
            row_id => 0 + $row_id,
            database_file => defined $database_file ? $database_file : '',
            title => defined $title ? $title : '',
            artist => defined $artist ? $artist : '',
            album => defined $album ? $album : '',
            reason => defined $case_variant
                ? 'filename_case_differs_from_lms_catalog'
                : defined $database_file && length $database_file
                    ? _unmatched_reason($database_file, $roots)
                    : 'missing_bliss_file_identity',
            defined $case_variant
                ? (related_lms_database_file => $case_variant) : (),
        };
        _yield_to_lms_if_due(\$bliss_last_yield);
    }
    $sth->finish;
    $dbh->disconnect;

    if ($shared_inventory) {
        _assert_shared_rows($shared_inventory, \@allowed);
        @allowed = map { 0 + $_ } @{$shared_inventory->{row_ids}};
    }

    _worker_progress('Rebuilding candidate library: publishing stable identities');
    my ($track_identity_artifact, $track_identity_path, $track_identity_sha256) =
        $shared_snapshot ? ({
            path => $shared_snapshot->{path}, sha256 => $shared_snapshot->{sha256},
            schema_identity => 'lyrion-track-identities-v1',
        }, $shared_snapshot->{path}, $shared_snapshot->{sha256}) : _publish_repeat_identity_snapshot(
            $repeat_snapshot, $scan_time, $database_identity,
            $media_roots_identity, $lyrion_identity, scalar(keys %ambiguous_files),
        );

    _worker_progress('Rebuilding candidate library: publishing candidate artifacts');
    my $now = time();
    my $inventory = {
        schema_version => 1,
        schema_identity => 'lms-local-candidate-inventory-v1',
        generated_at => int($now),
        database_cache_identity => $database_identity,
        lms_scan_time => 0 + $scan_time,
        lms_local_track_count => $lms_track_count,
        usable_bliss_row_count => $usable_count,
        allowed_row_ids => \@allowed,
    };
    my $bytes = _json()->encode($inventory);
    my $sha256 = sha256_hex($bytes);
    my $path = $inventory_root . '/inventory-' . $sha256 . '.json';
    my $existing_inventory = -r $path ? eval { read_file($path, binmode => ':raw') } : undef;
    _write_atomic($path, $bytes)
        unless defined($existing_inventory) && sha256_hex($existing_inventory) eq $sha256;
    my $identity_index = {
        schema_version => 1,
        schema_identity => 'eligible-candidate-identities-v1',
        generated_at => $now,
        database_cache_identity => $database_identity,
        lms_scan_time => $scan_time,
        candidate_library_id => $candidate_library->{id} || '',
        candidates => \@candidate_identities,
    };
    my $identity_bytes = _json()->encode($identity_index);
    my $identity_sha256 = sha256_hex($identity_bytes);
    my $identity_path =
        $inventory_root . '/identities-' . $identity_sha256 . '.json';
    _write_atomic($identity_path, $identity_bytes) unless -r $identity_path;
    my $identity_lookup_path =
        $inventory_root . '/identities-' . $identity_sha256 . '.sqlite';
    _write_identity_lookup($identity_lookup_path, \@candidate_identities)
        unless -r $identity_lookup_path;
    my $summary = {
        database_cache_identity => $database_identity,
        lms_scan_time => $scan_time,
        lms_local_track_count => $lms_track_count,
        usable_bliss_row_count => $usable_count,
        allowed_row_count => scalar(@allowed),
        unmatched_row_count => scalar(@unmatched),
        candidate_library_id => $candidate_library->{id} || '',
        candidate_library_name => $candidate_library->{name} || 'All tracks',
        candidate_library_track_count => $candidate_library_track_count,
        candidate_library_membership_sha256 => $membership_sha256,
        virtual_library_excluded_lms_track_count =>
            $lms_track_count - $candidate_library_track_count,
        virtual_library_excluded_bliss_row_count =>
            $virtual_library_excluded_bliss_row_count,
    };
    _update_audit(\@unmatched, $summary, $now);

    $last_status = {
        %$summary,
        ready => 1,
        inventory_path => $path,
        inventory_sha256 => $sha256,
        audit_path => $audit_path,
        cache_state => 'miss',
    };
    $cached_key = $key;
    $cached_result = {
        artifact => {
            path => $path,
            sha256 => $sha256,
            schema_identity => 'lms-local-candidate-inventory-v1',
        },
        status => $last_status,
        identities => \@candidate_identities,
        identity_artifact => {
            kind => 'eligible-candidate-identities-v1',
            path => $identity_path,
            sha256 => $identity_sha256,
            schema_identity => 'eligible-candidate-identities-v1',
        },
        identity_lookup_path => $identity_lookup_path,
        track_identity_artifact => $track_identity_artifact,
    };
    my $published_state = {
        schema_version => 1,
        builder_revision => BUILDER_REVISION,
        cache_key => $key,
        candidate_library_id => $candidate_library->{id} || '',
        candidate_library_membership_sha256 => $membership_sha256,
        candidate_library_track_count => $candidate_library_track_count,
        membership_track_count => $membership_count,
        virtual_library_excluded_lms_track_count =>
            $lms_track_count - $candidate_library_track_count,
        virtual_library_excluded_bliss_row_count =>
            $virtual_library_excluded_bliss_row_count,
        inventory_path => $path,
        inventory_sha256 => $sha256,
        identity_path => $identity_path,
        identity_sha256 => $identity_sha256,
        identity_lookup_path => $identity_lookup_path,
        track_identity_path => $track_identity_path,
        track_identity_sha256 => $track_identity_sha256,
    };
    my $state_bytes = _json()->encode($published_state);
    _write_atomic(_manifest_path_for_key($key), $state_bytes);
    _write_atomic($state_path, $state_bytes);
    $log->info(
        'candidate_inventory stage=Ready'
        . " lms_local=$lms_track_count bliss_usable=$usable_count"
        . ' allowed=' . scalar(@allowed)
        . ' unmatched=' . scalar(@unmatched)
        . ' candidate_library=' . ($candidate_library->{id} || 'all')
        . ' candidate_library_tracks=' . $candidate_library_track_count
        . ' virtual_library_excluded_bliss='
        . $virtual_library_excluded_bliss_row_count
        . " audit=$audit_path"
    );
    return $cached_result;
}

sub _lms_database_path {
    my $rows = _lms_dbh()->selectall_arrayref('PRAGMA database_list');
    for my $row (@{$rows || []}) {
        return $row->[2]
            if ($row->[1] || '') eq 'main' && length($row->[2] || '');
    }
    die "Could not resolve the Lyrion database path";
}

sub _parent_source_state {
    my ($capability, $lms_path) = @_;
    my $bliss = $capability->{database};
    die 'Bliss database is unavailable' unless defined($bliss) && length($bliss);
    my @files;
    for my $item ([$lms_path, 0], ["$lms_path-wal", 1], [$bliss, 0], ["$bliss-wal", 1]) {
        my ($path, $optional) = @$item;
        my @stat = stat($path);
        die 'Candidate database is unavailable' if !@stat && !$optional;
        push @files, @stat ? [@stat[0, 1, 7, 9, 10]] : undef;
    }
    my ($data_version) = _lms_dbh()->selectrow_array('PRAGMA data_version');
    return JSON::XS->new->utf8->canonical->encode({files => \@files,
        roots => $capability->{music_roots} || [], current_roots => Slim::Utils::Misc::getMediaDirs('audio') || [],
        data_version => 0 + ($data_version || 0),
        scan => 0 + (Slim::Music::Import->lastScanTime() || 0)});
}

sub _fast_memo_key {
    my ($capability, $database_identity, $library) = @_;
    return JSON::XS->new->utf8->canonical->encode({
        database => $capability->{database}, roots => $capability->{music_roots} || [],
        database_identity => $database_identity, library => ($library->{id} || ''),
    });
}

sub _check_fast_library {
    my ($library) = @_;
    my $id = $library->{id} || '';
    return 1 unless length $id;
    require Slim::Music::VirtualLibraries;
    my $real = Slim::Music::VirtualLibraries->getRealId($id);
    die 'Selected virtual library is unavailable' unless defined($real) && $real eq $id;
    return 1;
}

sub _schedule_async_poll {
    Slim::Utils::Timers::setTimer(
        undef, time() + 0.25, \&_poll_async_prepare,
    );
}

sub _start_next_async_prepare {
    return if $async_prepare_worker || !@async_prepare_queue;
    my $task = shift @async_prepare_queue;

    if (main::ISWINDOWS) {
        Slim::Utils::Timers::setTimer(undef, time() + 0.01, sub {
            my ($result, $error);
            eval {
                $result = prepare(
                    @{$task}{qw(capability database_identity candidate_library)},
                );
                1;
            } or $error = $@ || 'Could not capture candidate library';
            $error ? $task->{on_error}->($error) : $task->{on_done}->($result);
            _start_next_async_prepare();
        });
        return;
    }

    my $lms_database_path = eval { _lms_database_path() };
    if (!$lms_database_path) {
        $task->{on_error}->($@ || 'Could not resolve the Lyrion database path');
        _start_next_async_prepare();
        return;
    }
    my $initial_source = eval { _parent_source_state($task->{capability}, $lms_database_path) };
    unless (defined $initial_source) {
        $task->{on_error}->($@ || 'Could not capture candidate library source state');
        _start_next_async_prepare();
        return;
    }
    my $observer = eval {
        my $bundle = _register_shared_bundle();
        local @INC = (File::Spec->catdir($bundle, 'lib'), @INC);
        require Plugins::BlissLibrary::SourceIdentity;
        Plugins::BlissLibrary::SourceIdentity::begin_session([$lms_database_path, $task->{capability}->{database}]);
    };
    unless ($observer) {
        $task->{on_error}->($@ || 'Could not observe candidate library source changes');
        _start_next_async_prepare();
        return;
    }
    my $token = $$ . '-' . int(time() * 1000) . '-' . int(rand(1_000_000));
    my $result_path = $inventory_root . '/prepare-' . $token . '.json';
    my $progress_path = $inventory_root . '/prepare-' . $token . '-progress.json';
    my $pid = fork();
    if (!defined $pid) {
        $task->{on_error}->("Could not start candidate-library worker: $!");
        _start_next_async_prepare();
        return;
    }

    if (!$pid) {
        $worker_child = 1;
        $worker_progress_path = $progress_path;
        eval { setpriority(0, 0, 10); };
        my ($ionice) = grep { -x $_ }
            qw(/usr/local/bin/ionice /usr/bin/ionice /bin/ionice);
        system($ionice, '-c', '3', '-p', $$) if $ionice;
        my $ok = eval {
            my $parent_dbh = Slim::Schema->dbh;
            $parent_dbh->{InactiveDestroy} = 1 if $parent_dbh;
            $lms_dbh_override = DBI->connect(
                'dbi:SQLite:dbname=' . $lms_database_path, '', '',
                {
                    RaiseError => 1,
                    PrintError => 0,
                    AutoCommit => 1,
                    sqlite_unicode => 1,
                    sqlite_open_flags => 1,
                },
            );
            die "Could not open the Lyrion database read-only"
                unless $lms_dbh_override;
            ($cached_key, $cached_result, $last_status) = (undef, undef, undef);
            my $prepared = prepare(
                @{$task}{qw(capability database_identity candidate_library)},
            );
            _write_atomic(
                $result_path, _json()->encode({ok => JSON::XS::true, cache_key => $cached_key,
                    membership_sha256 => $prepared->{status}->{candidate_library_membership_sha256},
                    membership_count => $worker_membership_count,
                    scan_time => $prepared->{status}->{lms_scan_time}}),
            );
            1;
        };
        if (!$ok) {
            my $error = $@ || 'Could not capture candidate library';
            eval {
                _write_atomic(
                    $result_path,
                    _json()->encode({
                        ok => JSON::XS::false,
                        error => "$error",
                    }),
                );
                1;
            };
        }
        eval { $lms_dbh_override->disconnect if $lms_dbh_override; };
        POSIX::_exit($ok ? 0 : 1);
    }

    $async_prepare_worker = {
        pid => $pid,
        task => $task,
        result_path => $result_path,
        progress_path => $progress_path,
        last_progress => '',
        started_at => time(),
        lms_database_path => $lms_database_path,
        initial_source => $initial_source,
        source_observer => $observer,
    };
    $log->info(
        "candidate_inventory stage=BackgroundRebuildStarted pid=$pid"
        . ' nice=10 io_priority=idle',
    );
    _schedule_async_poll();
}

sub _poll_async_prepare {
    my $worker = $async_prepare_worker || return;
    if (-r $worker->{progress_path}) {
        my $bytes = eval {
            scalar read_file($worker->{progress_path}, binmode => ':raw')
        };
        my $progress = defined $bytes ? eval { _json()->decode($bytes) } : undef;
        my $message = ref($progress) eq 'HASH'
            ? ($progress->{message} || '') : '';
        if (length($message) && $message ne ($worker->{last_progress} || '')) {
            $worker->{last_progress} = $message;
            $worker->{task}->{on_progress}->($message)
                if $worker->{task}->{on_progress};
        }
    }

    my $waited = waitpid($worker->{pid}, WNOHANG);
    if (!$waited) {
        _schedule_async_poll();
        return;
    }

    my $bytes = eval {
        scalar read_file($worker->{result_path}, binmode => ':raw')
    };
    my $outcome = defined $bytes ? eval { _json()->decode($bytes) } : undef;
    unlink $worker->{result_path} if -e $worker->{result_path};
    unlink $worker->{progress_path} if -e $worker->{progress_path};
    my $task = $worker->{task};
    $async_prepare_worker = undef;
    $log->info(sprintf(
        'candidate_inventory stage=BackgroundRebuildFinished pid=%d elapsed_ms=%d outcome=%s',
        $worker->{pid},
        1000 * (time() - ($worker->{started_at} || time())),
        ref($outcome) eq 'HASH' && $outcome->{ok} ? 'success' : 'failed',
    ));

    if (ref($outcome) ne 'HASH' || !$outcome->{ok}) {
        $task->{on_error}->(
            ref($outcome) eq 'HASH' && $outcome->{error}
                ? $outcome->{error}
                : 'Candidate-library worker exited without a valid result',
        );
    } else {
        my ($result, $error);
        eval {
            local $Plugins::BlissLibrary::SourceIdentity::session = $worker->{source_observer};
            Plugins::BlissLibrary::SourceIdentity::_check_session($worker->{lms_database_path});
            Plugins::BlissLibrary::SourceIdentity::_check_session($task->{capability}->{database});
            die 'Candidate library changed while the worker was running'
                unless _parent_source_state($task->{capability}, $worker->{lms_database_path}) eq $worker->{initial_source};
            my $library = $task->{candidate_library} || {id => '', name => 'All tracks'};
            _check_fast_library($library);
            $result = _load_cached_inventory($outcome->{cache_key}, $task->{database_identity},
                $outcome->{scan_time}, $library, $outcome->{membership_sha256}, $outcome->{membership_count}, 1);
            die 'Could not load the verified candidate inventory' unless $result;
            Plugins::BlissLibrary::SourceIdentity::_check_session($worker->{lms_database_path});
            Plugins::BlissLibrary::SourceIdentity::_check_session($task->{capability}->{database});
            die 'Candidate library changed while the worker was running'
                unless _parent_source_state($task->{capability}, $worker->{lms_database_path}) eq $worker->{initial_source};
            _check_fast_library($library);
            $cached_key = $outcome->{cache_key};
            $cached_result = $result;
            $last_status = $result->{status};
            $fast_memo = {
                key => _fast_memo_key($task->{capability}, $task->{database_identity}, $library),
                observer => $worker->{source_observer}, source => $worker->{initial_source},
                lms_path => $worker->{lms_database_path}, cache_key => $outcome->{cache_key},
                scan_time => $outcome->{scan_time}, membership_sha256 => $outcome->{membership_sha256},
                membership_count => $outcome->{membership_count},
            };
            _log_cache_hit($last_status);
            1;
        } or $error = $@ || 'Could not load the rebuilt candidate library';
        $error ? $task->{on_error}->($error) : $task->{on_done}->($result);
    }
    _start_next_async_prepare();
}

sub prepare_async {
    my ($capability, $database_identity, $candidate_library,
        $on_done, $on_error, $on_progress) = @_;
    die "Candidate inventory completion callback is required"
        unless ref($on_done) eq 'CODE';
    die "Candidate inventory error callback is required"
        unless ref($on_error) eq 'CODE';
    my $bundle_ok = eval { _register_shared_bundle(); 1 };
    unless ($bundle_ok) {
        $on_error->($@ || 'Shared inventory bundle is incompatible');
        return;
    }
    my $task = {
        capability => $capability,
        database_identity => $database_identity,
        candidate_library => $candidate_library,
        on_done => sub {
            my $result = shift;
            my $id = $candidate_library->{id} || '';
            my $scope = length($id) ? {kind => 'library', id => "$id"} : {kind => 'all'};
            eval { _init_shared_refresh(); Plugins::BlissLibrary::LyrionRefresh::remember($scope) };
            $log->warn("Could not remember candidate refresh scope: $@") if $@;
            $on_done->($result);
        },
        on_error => $on_error,
        on_progress => $on_progress,
    };
    my $library = $candidate_library || {id => '', name => 'All tracks'};
    my $memo = $fast_memo;
    if ($memo && !$async_prepare_worker && !@async_prepare_queue
        && $memo->{key} eq _fast_memo_key($capability, $database_identity, $library)) {
        my $generation = $async_generation;
        Slim::Utils::Timers::setTimer(undef, time() + 0.01, sub {
            return if $generation != $async_generation;
            if ($async_prepare_worker || @async_prepare_queue) {
                push @async_prepare_queue, $task;
                _start_next_async_prepare();
                return;
            }
            my $result = eval {
                _check_fast_library($library);
                local $Plugins::BlissLibrary::SourceIdentity::session = $memo->{observer};
                Plugins::BlissLibrary::SourceIdentity::_check_session($memo->{lms_path});
                Plugins::BlissLibrary::SourceIdentity::_check_session($capability->{database});
                die 'Candidate source changed' unless _parent_source_state($capability, $memo->{lms_path}) eq $memo->{source};
                my $value = _load_cached_inventory($memo->{cache_key}, $database_identity, $memo->{scan_time},
                    $library, $memo->{membership_sha256}, $memo->{membership_count}, 1);
                die 'Cached candidate inventory is unavailable' unless $value;
                Plugins::BlissLibrary::SourceIdentity::_check_session($memo->{lms_path});
                Plugins::BlissLibrary::SourceIdentity::_check_session($capability->{database});
                die 'Candidate source changed' unless _parent_source_state($capability, $memo->{lms_path}) eq $memo->{source};
                _check_fast_library($library);
                $value;
            };
            if ($result) {
                $result->{status}->{cache_state} = 'memory';
                $cached_key = $memo->{cache_key};
                $cached_result = $result;
                $last_status = $result->{status};
                _log_cache_hit($last_status);
                $task->{on_done}->($result);
                return;
            }
            $fast_memo = undef if $fast_memo && $fast_memo == $memo;
            push @async_prepare_queue, $task;
            _start_next_async_prepare();
        });
        return;
    }
    push @async_prepare_queue, $task;
    _start_next_async_prepare();
}

sub shutdown {
    $async_generation++;
    $fast_memo = undef;
    if ($INC{'Plugins/BlissLibrary/LyrionRefresh.pm'}) {
        my $bundle = File::Spec->catdir(dirname(__FILE__), 'SharedInventory');
        eval { Plugins::BlissLibrary::LyrionRefresh::release($bundle) };
    }
    @async_prepare_queue = ();
    if ($async_prepare_worker) {
        kill 'TERM', $async_prepare_worker->{pid};
        waitpid($async_prepare_worker->{pid}, 0);
        unlink $async_prepare_worker->{result_path}
            if -e $async_prepare_worker->{result_path};
        unlink $async_prepare_worker->{progress_path}
            if -e $async_prepare_worker->{progress_path};
        $async_prepare_worker = undef;
    }
}

sub status {
    return $last_status || {
        ready => 0,
        unmatched_row_count => undef,
        audit_path => $audit_path,
    };
}

1;
