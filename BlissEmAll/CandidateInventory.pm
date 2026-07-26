package Plugins::BlissEmAll::CandidateInventory;

use strict;
use DBI;
use Digest::SHA qw(sha256_hex);
use Encode qw(encode_utf8);
use File::Path qw(make_path);
use File::Slurp qw(read_file write_file);
use File::Spec::Functions qw(catfile);
use JSON::XS;
use Slim::Music::Import;
use Slim::Schema;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Unicode;

my $log = Slim::Utils::Log::logger('plugin.blissemall');
my ($inventory_root, $audit_path, $cached_key, $cached_result, $last_status);

sub init {
    my $cache_root = shift;
    $inventory_root = $cache_root . '/candidate-inventory';
    $audit_path = $cache_root . '/non-lms-bliss-rows.json';
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
        $relative = Slim::Utils::Unicode::utf8decode_locale($relative);
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
    my ($url, $tracknum, $roots) = @_;
    return unless $url && $url =~ /^file:/i;
    return _relative_database_file(
        Slim::Utils::Misc::pathFromFileURL($url), $url, $tracknum, $roots,
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
    my $ledger = eval {
        _json()->decode(read_file($audit_path, binmode => ':raw'));
    };
    return ref($ledger) eq 'HASH' && ref($ledger->{rows}) eq 'ARRAY'
        ? $ledger : {schema_version => 1, rows => []};
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
    my ($capability, $database_identity) = @_;
    die "Candidate inventory cache is not initialized" unless $inventory_root;
    my $scan_time = 0 + (Slim::Music::Import->lastScanTime() || 0);
    my $key = join('|', $database_identity, $scan_time);
    return $cached_result if $cached_result && ($cached_key || '') eq $key;

    my %lms_files;
    my $lms_track_count = 0;
    my $lms_sth = Slim::Schema->dbh->prepare(
        'SELECT url, tracknum FROM tracks WHERE remote = 0 AND audio = 1'
    );
    $lms_sth->execute;
    while (my ($url, $tracknum) = $lms_sth->fetchrow_array) {
        my $database_file = _database_file_for_url(
            $url, $tracknum, $capability->{music_roots} || [],
        );
        next unless defined $database_file && length $database_file;
        $lms_files{$database_file} = 1;
        $lms_track_count++;
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
    my (@allowed, @unmatched);
    my $usable_count = 0;
    while (my ($row_id, $file, $title, $artist, $album) = $sth->fetchrow_array) {
        $usable_count++;
        if (defined $file && $lms_files{$file}) {
            push @allowed, 0 + $row_id;
            next;
        }
        push @unmatched, {
            row_id => 0 + $row_id,
            database_file => defined $file ? $file : '',
            title => defined $title ? $title : '',
            artist => defined $artist ? $artist : '',
            album => defined $album ? $album : '',
            reason => defined $file && length $file
                ? _unmatched_reason($file, $capability->{music_roots} || [])
                : 'missing_bliss_file_identity',
        };
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
    my $summary = {
        database_cache_identity => $database_identity,
        lms_scan_time => $scan_time,
        lms_local_track_count => $lms_track_count,
        usable_bliss_row_count => $usable_count,
        allowed_row_count => scalar(@allowed),
        unmatched_row_count => scalar(@unmatched),
    };
    _update_audit(\@unmatched, $summary, $now);

    $last_status = {
        %$summary,
        ready => 1,
        inventory_path => $path,
        inventory_sha256 => $sha256,
        audit_path => $audit_path,
    };
    $cached_key = $key;
    $cached_result = {
        artifact => {
            path => $path,
            sha256 => $sha256,
            schema_identity => 'lms-local-candidate-inventory-v1',
        },
        status => $last_status,
    };
    $log->info(
        'candidate_inventory stage=Ready'
        . " lms_local=$lms_track_count bliss_usable=$usable_count"
        . ' allowed=' . scalar(@allowed)
        . ' unmatched=' . scalar(@unmatched)
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
