package Plugins::BetterCallBliss::CandidateInventory;

use strict;
use DBI;
use Digest::SHA qw(sha256_hex);
use Encode qw(decode encode_utf8 FB_CROAK);
use File::Path qw(make_path);
use File::Slurp qw(read_file write_file);
use File::Spec::Functions qw(catfile);
use JSON::XS;
use Slim::Music::Import;
use Slim::Schema;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Timers;
use Slim::Utils::Unicode;
use Time::HiRes qw(time);
use URI::Escape qw(uri_unescape);
use Plugins::BetterCallBliss::CandidateIdentity;

my $log = Slim::Utils::Log::logger('plugin.bettercallbliss');
use constant BUILDER_REVISION => 5;
my (
    $inventory_root, $audit_path, $state_path,
    $cached_key, $cached_result, $last_status,
);

use constant YIELD_EVERY_ROWS => 250;
use constant ASYNC_CHUNK_ROWS => 250;
use constant ASYNC_RESUME_DELAY => 0.02;

sub _yield_to_lms {
    main::idleStreams() if defined &main::idleStreams;
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
    make_path($inventory_root) unless -d $inventory_root;
}

sub _json {
    return JSON::XS->new->utf8->canonical->pretty;
}

sub _write_atomic {
    my ($path, $bytes) = @_;
    my $temporary = $path . '.tmp-' . $$;
    write_file($temporary, {binmode => ':raw'}, $bytes);
    rename($temporary, $path) or die "Could not publish '$path': $!";
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

sub _database_file_for_url {
    my ($url, $tracknum, $root_descriptors, $roots) = @_;
    return unless $url && $url =~ /^file:/i;
    my $file_url = $url;
    $file_url =~ s/#.*$//;
    for my $descriptor (@$root_descriptors) {
        my $prefix = $descriptor->{url_prefix};
        next unless index($file_url, $prefix . '/') == 0;
        my $relative = substr($file_url, length($prefix) + 1);
        $relative = uri_unescape($relative);
        $relative = _database_text($relative);
        $relative .= '.CUE_TRACK.' . $tracknum
            if $url =~ /#/ && $tracknum;
        return $relative;
    }
    return _relative_database_file(
        Slim::Utils::Misc::pathFromFileURL($url), $url, $tracknum, $roots,
    );
}

sub _root_descriptors {
    my $roots = shift;
    my @descriptors;
    for my $root (@$roots) {
        my $prefix = Slim::Utils::Misc::fileURLFromPath($root);
        $prefix =~ s{/+$}{};
        push @descriptors, {url_prefix => $prefix};
    }
    return \@descriptors;
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

sub _load_cached_inventory {
    my ($key, $database_identity, $scan_time, $candidate_library,
        $membership_sha256, $membership_count) = @_;
    my $miss = sub {
        my $reason = shift;
        $log->info("candidate_inventory stage=CacheMiss reason=$reason");
        return;
    };
    return $miss->('state_unreadable') unless $state_path && -r $state_path;
    my $state_bytes = eval { scalar read_file($state_path, binmode => ':raw') };
    my $state = defined $state_bytes
        ? eval { _json()->decode($state_bytes) } : undef;
    return $miss->('state_invalid') unless ref($state) eq 'HASH';
    return $miss->('builder_revision_changed')
        unless ($state->{builder_revision} || 0) == BUILDER_REVISION;
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
            && 0 + ($state->{candidate_library_track_count} || 0)
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
    my $identity_index;
    if ($identity_lookup_path
        !~ /^\Q$inventory_root\E\/identities-[0-9a-f]{64}\.sqlite$/
        || !-r $identity_lookup_path) {
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
            _write_atomic($state_path, _json()->encode($state));
            1;
        } or return $miss->('identity_lookup_migration_failed');
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
            path => $identity_path,
            sha256 => $state->{identity_sha256},
            schema_identity => 'eligible-candidate-identities-v1',
        },
        identity_lookup_path => $identity_lookup_path,
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
    my $sth = Slim::Schema->dbh->prepare(
        'SELECT track FROM library_track WHERE library = ? ORDER BY track'
    );
    $sth->execute($id);
    my $row_count = 0;
    while (my ($track_id) = $sth->fetchrow_array) {
        next unless defined $track_id;
        $members{0 + $track_id} = 1;
        $digest->add("$track_id\n");
        _yield_to_lms() unless ++$row_count % YIELD_EVERY_ROWS;
    }
    $sth->finish;
    return (\%members, $digest->hexdigest, scalar keys %members);
}

sub _candidate_library_track_count {
    my $candidate_library = shift || {};
    my $id = $candidate_library->{id} || '';
    return undef unless length $id;
    my ($count) = Slim::Schema->dbh->selectrow_array(
        'SELECT COUNT(1) FROM library_track WHERE library = ?', undef, $id,
    );
    return 0 + ($count || 0);
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

sub prepare {
    my ($capability, $database_identity, $candidate_library) = @_;
    die "Candidate inventory cache is not initialized" unless $inventory_root;
    $candidate_library ||= {id => '', name => 'All tracks'};
    my $scan_time_value = Slim::Music::Import->lastScanTime() || 0;
    my $scan_time = int($scan_time_value);
    my $membership_count = _candidate_library_track_count($candidate_library);
    my $key = join('|', $database_identity, $scan_time,
        $candidate_library->{id} || '', defined $membership_count
            ? $membership_count : 'all');
    if ($cached_result && ($cached_key || '') eq $key) {
        $cached_result->{status}->{cache_state} = 'memory';
        return $cached_result;
    }
    if (my $disk = _load_cached_inventory(
        $key, $database_identity, $scan_time, $candidate_library,
        undef, $membership_count,
    )) {
        $cached_key = $key;
        $cached_result = $disk;
        $last_status = $disk->{status};
        $log->info(
            'candidate_inventory stage=CacheHit'
            . ' allowed=' . $last_status->{allowed_row_count}
            . ' unmatched=' . $last_status->{unmatched_row_count}
            . " audit=$audit_path"
        );
        return $cached_result;
    }

    my ($library_members, $membership_sha256, $captured_membership_count) =
        _candidate_library_membership($candidate_library);
    $membership_count = $captured_membership_count
        if defined $captured_membership_count;

    my (%lms_files, %candidate_files, %lms_files_folded, %ambiguous_folded,
        %lms_identity_for);
    my $lms_track_count = 0;
    my $candidate_library_track_count = 0;
    my $roots = $capability->{music_roots} || [];
    my $root_descriptors = _root_descriptors($roots);
    my $lms_sth = Slim::Schema->dbh->prepare(
        'SELECT tracks.id, tracks.url, tracks.tracknum, tracks.urlmd5, tracks.musicbrainz_id, '
        . 'contributors.musicbrainz_id FROM tracks '
        . 'LEFT JOIN contributors ON contributors.id = tracks.primary_artist '
        . 'WHERE tracks.remote = 0 AND tracks.audio = 1'
    );
    $lms_sth->execute;
    my $lms_row_count = 0;
    while (my ($track_id, $url, $tracknum, $urlmd5, $recording_mbid, $artist_mbid)
        = $lms_sth->fetchrow_array) {
        my $database_file = _database_file_for_url(
            $url, $tracknum, $root_descriptors, $roots,
        );
        next unless defined $database_file && length $database_file;
        $lms_files{$database_file} = 1;
        if (!length($candidate_library->{id} || '')
            || $library_members->{0 + $track_id}) {
            $candidate_files{$database_file} = 1;
            $lms_identity_for{$database_file} = {
                lms_track_id => 0 + $track_id,
                defined $urlmd5 && length $urlmd5
                    ? (lms_urlmd5 => "$urlmd5") : (),
                defined $recording_mbid && length $recording_mbid
                    ? (recording_mbid => "$recording_mbid") : (),
                defined $artist_mbid && length $artist_mbid
                    ? (artist_mbid => "$artist_mbid") : (),
            };
            $candidate_library_track_count++;
        }
        my $folded = lc($database_file);
        if (exists $lms_files_folded{$folded}
            && $lms_files_folded{$folded} ne $database_file) {
            $ambiguous_folded{$folded} = 1;
        } else {
            $lms_files_folded{$folded} = $database_file;
        }
        $lms_track_count++;
        _yield_to_lms() unless ++$lms_row_count % YIELD_EVERY_ROWS;
    }
    $lms_sth->finish;

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
        'SELECT rowid, File, Title, Artist, Album FROM TracksV2 '
        . 'WHERE Ignore IS NOT 1 ORDER BY rowid'
    );
    $sth->execute;
    my (@allowed, @candidate_identities, @unmatched);
    my $usable_count = 0;
    my $virtual_library_excluded_bliss_row_count = 0;
    my $bliss_row_count = 0;
    while (my ($row_id, $file, $title, $artist, $album) = $sth->fetchrow_array) {
        $usable_count++;
        my $database_file = _database_text($file);
        my $folded = defined $database_file ? lc($database_file) : '';
        if (defined $database_file && $candidate_files{$database_file}) {
            push @allowed, 0 + $row_id;
            my $lms_identity = $lms_identity_for{$database_file} || {};
            push @candidate_identities, {
                candidate_id => 'bliss-row-' . (0 + $row_id),
                row_id => 0 + $row_id,
                lms_track_id => 0 + ($lms_identity->{lms_track_id} || 0),
                defined $lms_identity->{lms_urlmd5}
                    ? (lms_urlmd5 => $lms_identity->{lms_urlmd5}) : (),
                title => defined $title ? $title : '',
                artist => defined $artist ? $artist : '',
                defined $lms_identity->{recording_mbid}
                    ? (recording_mbid => $lms_identity->{recording_mbid}) : (),
                defined $lms_identity->{artist_mbid}
                    ? (artist_mbid => $lms_identity->{artist_mbid}) : (),
            };
            _yield_to_lms() unless ++$bliss_row_count % YIELD_EVERY_ROWS;
            next;
        }
        if (defined $database_file && $lms_files{$database_file}) {
            $virtual_library_excluded_bliss_row_count++;
            _yield_to_lms() unless ++$bliss_row_count % YIELD_EVERY_ROWS;
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
        _yield_to_lms() unless ++$bliss_row_count % YIELD_EVERY_ROWS;
    }
    $sth->finish;
    $dbh->disconnect;

    my $now = time();
    my $inventory = {
        schema_version => 1,
        schema_identity => 'lms-local-candidate-inventory-v1',
        generated_at => $now,
        database_cache_identity => $database_identity,
        lms_scan_time => $scan_time,
        lms_local_track_count => $lms_track_count,
        usable_bliss_row_count => $usable_count,
        allowed_row_ids => \@allowed,
    };
    my $bytes = _json()->encode($inventory);
    my $sha256 = sha256_hex($bytes);
    my $path = $inventory_root . '/inventory-' . $sha256 . '.json';
    _write_atomic($path, $bytes) unless -r $path;
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
            path => $identity_path,
            sha256 => $identity_sha256,
            schema_identity => 'eligible-candidate-identities-v1',
        },
        identity_lookup_path => $identity_lookup_path,
    };
    _write_atomic($state_path, _json()->encode({
        schema_version => 1,
        builder_revision => BUILDER_REVISION,
        cache_key => $key,
        candidate_library_id => $candidate_library->{id} || '',
        candidate_library_membership_sha256 => $membership_sha256,
        candidate_library_track_count => $candidate_library_track_count,
        virtual_library_excluded_lms_track_count =>
            $lms_track_count - $candidate_library_track_count,
        virtual_library_excluded_bliss_row_count =>
            $virtual_library_excluded_bliss_row_count,
        inventory_path => $path,
        inventory_sha256 => $sha256,
        identity_path => $identity_path,
        identity_sha256 => $identity_sha256,
        identity_lookup_path => $identity_lookup_path,
    }));
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

sub status {
    return $last_status || {
        ready => 0,
        unmatched_row_count => undef,
        audit_path => $audit_path,
    };
}

1;
