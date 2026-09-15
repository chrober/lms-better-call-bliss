package Plugins::BetterCallBliss::CandidateGuidance;

use strict;
use Slim::Utils::Log;
use Slim::Utils::Timers;
use Time::HiRes qw(time);
use Plugins::BetterCallBliss::CandidateIdentity;

my $log = Slim::Utils::Log::logger('plugin.bettercallbliss');

use constant YIELD_EVERY_ROWS => 250;
use constant ASYNC_CHUNK_ROWS => 2000;
use constant ASYNC_RESUME_DELAY => 0.02;

sub _yield_to_lms {
    main::idleStreams() if defined &main::idleStreams;
}

sub _normalize_text {
    return Plugins::BetterCallBliss::CandidateIdentity::normalize_text(shift);
}

sub _normalize_mbid {
    return Plugins::BetterCallBliss::CandidateIdentity::normalize_mbid(shift);
}

sub _recording_key {
    my ($artist, $title) = @_;
    return _normalize_text($artist) . "\0" . _normalize_text($title);
}

sub _index_candidates {
    my $identities = shift || [];
    my $index = _empty_index();
    my $row_count = 0;
    for my $identity (@$identities) {
        _index_candidate($identity, $index);
        _yield_to_lms() unless ++$row_count % YIELD_EVERY_ROWS;
    }
    return $index;
}

sub _empty_index {
    return {
        recording_mbid => {},
        recording_name => {},
        artist_mbid => {},
        artist_name => {},
    };
}

sub _index_candidate {
    my ($identity, $index) = @_;
    return unless ref($identity) eq 'HASH';
    my $candidate_id = $identity->{candidate_id} || '';
    return unless $candidate_id =~ /^bliss-row-[1-9][0-9]*$/;
    my $recording_mbid = _normalize_mbid($identity->{recording_mbid});
    push @{$index->{recording_mbid}->{$recording_mbid}}, $candidate_id
        if length $recording_mbid;
    my $recording_name = _recording_key(
        $identity->{artist}, $identity->{title},
    );
    push @{$index->{recording_name}->{$recording_name}}, $candidate_id
        if $recording_name ne "\0";
    my $artist_mbid = _normalize_mbid($identity->{artist_mbid});
    push @{$index->{artist_mbid}->{$artist_mbid}}, $candidate_id
        if length $artist_mbid;
    my $artist_name = _normalize_text($identity->{artist});
    push @{$index->{artist_name}->{$artist_name}}, $candidate_id
        if length $artist_name;
}

sub _candidate_ids_for_edge {
    my ($edge, $index) = @_;
    my $candidate = ref($edge->{candidate}) eq 'HASH'
        ? $edge->{candidate} : {};
    my $kind = $candidate->{kind} || '';
    my @matches;
    if ($kind eq 'recording') {
        my $mbid = _normalize_mbid($candidate->{mbid});
        @matches = @{$index->{recording_mbid}->{$mbid} || []}
            if length $mbid;
        if (!@matches) {
            my $key = _recording_key(
                $candidate->{name}, $candidate->{title},
            );
            @matches = @{$index->{recording_name}->{$key} || []};
        }
    } elsif ($kind eq 'artist') {
        my $mbid = _normalize_mbid($candidate->{mbid});
        @matches = @{$index->{artist_mbid}->{$mbid} || []}
            if length $mbid;
        if (!@matches) {
            my $key = _normalize_text($candidate->{name});
            @matches = @{$index->{artist_name}->{$key} || []};
        }
    }
    my %seen;
    return grep { !$seen{$_}++ } @matches;
}

sub _candidate_ids_for_lookup {
    my ($edge, $dbh) = @_;
    my $candidate = ref($edge->{candidate}) eq 'HASH'
        ? $edge->{candidate} : {};
    my $kind = $candidate->{kind} || '';
    my @matches;
    if ($kind eq 'recording') {
        my $mbid = _normalize_mbid($candidate->{mbid});
        @matches = @{$dbh->selectcol_arrayref(
            'SELECT candidate_id FROM candidate_identity '
            . 'WHERE recording_mbid = ?', undef, $mbid,
        ) || []} if length $mbid;
        if (!@matches) {
            @matches = @{$dbh->selectcol_arrayref(
                'SELECT candidate_id FROM candidate_identity '
                . 'WHERE recording_artist = ? AND recording_title = ?',
                undef, _normalize_text($candidate->{name}),
                _normalize_text($candidate->{title}),
            ) || []};
        }
    } elsif ($kind eq 'artist') {
        my $mbid = _normalize_mbid($candidate->{mbid});
        @matches = @{$dbh->selectcol_arrayref(
            'SELECT candidate_id FROM candidate_identity '
            . 'WHERE artist_mbid = ?', undef, $mbid,
        ) || []} if length $mbid;
        if (!@matches) {
            @matches = @{$dbh->selectcol_arrayref(
                'SELECT candidate_id FROM candidate_identity '
                . 'WHERE artist_name = ?', undef,
                _normalize_text($candidate->{name}),
            ) || []};
        }
    }
    my %seen;
    return grep { !$seen{$_}++ } @matches;
}

sub _resolve_edge {
    my ($edge, $index, $resolved, $seen, $counts) = @_;
    return unless ref($edge) eq 'HASH';
    my @candidate_ids = ref($index) eq 'CODE'
        ? $index->($edge) : _candidate_ids_for_edge($edge, $index);
    unless (@candidate_ids) {
        $counts->{unmatched}++;
        return;
    }
    for my $candidate_id (@candidate_ids) {
        my $source = ref($edge->{source}) eq 'HASH' ? $edge->{source} : {};
        my $key = join('|',
            $source->{kind} || '', $source->{id} || '',
            $candidate_id, $edge->{scope} || '',
            $edge->{provider} || '', $edge->{dataset_or_algorithm} || '',
        );
        next if $seen->{$key}++;
        my %resolved_edge = %$edge;
        $resolved_edge{resolved_candidate_id} = $candidate_id;
        push @$resolved, \%resolved_edge;
        if (($source->{kind} || '') eq 'recording') {
            $counts->{recording}++;
        } elsif (($source->{kind} || '') eq 'artist') {
            $counts->{artist}++;
        }
    }
}

sub _finish_resolution {
    my ($bundle, $identities, $resolved, $counts, $prefix,
        $candidate_identity_count) = @_;
    my %resolved_bundle = %$bundle;
    $resolved_bundle{edges} = $resolved;
    my $stats = {
        candidate_identity_count => defined $candidate_identity_count
            ? $candidate_identity_count : scalar(@$identities),
        input_edge_count => scalar(@{$bundle->{edges} || []}),
        resolved_edge_count => scalar(@$resolved),
        recording_edge_count => $counts->{recording},
        artist_edge_count => $counts->{artist},
        unmatched_edge_count => $counts->{unmatched},
    };
    $log->info(
        $prefix . 'Candidate guidance resolved by Better Call Bliss'
        . " candidates=$stats->{candidate_identity_count}"
        . " input_edges=$stats->{input_edge_count}"
        . " resolved_edges=$stats->{resolved_edge_count}"
        . " recording_edges=$counts->{recording}"
        . " artist_edges=$counts->{artist}"
        . " unmatched_edges=$counts->{unmatched}"
    );
    return (\%resolved_bundle, $stats);
}

sub resolve {
    my ($bundle, $candidate_inventory, $context) = @_;
    $bundle ||= {};
    $candidate_inventory ||= {};
    $context ||= {};
    my $job_id = $context->{job_id} || '';
    my $prefix = length $job_id ? "job=$job_id " : '';
    my $identities = $candidate_inventory->{identities} || [];
    my $edges = $bundle->{edges} || [];
    return _finish_resolution(
        $bundle, $identities, [],
        {recording => 0, artist => 0, unmatched => 0}, $prefix,
    ) unless @$edges;
    my $index = _index_candidates($identities);
    my (@resolved, %seen);
    my $counts = {recording => 0, artist => 0, unmatched => 0};

    my $edge_count = 0;
    for my $edge (@$edges) {
        _resolve_edge($edge, $index, \@resolved, \%seen, $counts);
        _yield_to_lms() unless ++$edge_count % YIELD_EVERY_ROWS;
    }
    return _finish_resolution(
        $bundle, $identities, \@resolved, $counts, $prefix,
    );
}

sub resolve_async {
    my ($bundle, $candidate_inventory, $context, $callback) = @_;
    $bundle ||= {};
    $candidate_inventory ||= {};
    $context ||= {};
    die 'Candidate-guidance completion callback is required'
        unless ref($callback) eq 'CODE';
    my $job_id = $context->{job_id} || '';
    my $should_continue = $context->{should_continue};
    my $prefix = length $job_id ? "job=$job_id " : '';
    my $identities = $candidate_inventory->{identities} || [];
    my $candidate_identity_count =
        ref($candidate_inventory->{status}) eq 'HASH'
            && defined $candidate_inventory->{status}->{allowed_row_count}
        ? $candidate_inventory->{status}->{allowed_row_count}
        : scalar @$identities;
    my $edges = $bundle->{edges} || [];
    unless (@$edges) {
        my ($resolved_bundle, $stats) = _finish_resolution(
            $bundle, $identities, [],
            {recording => 0, artist => 0, unmatched => 0}, $prefix,
            $candidate_identity_count,
        );
        $callback->($resolved_bundle, $stats, undef);
        return;
    }

    my $identity_lookup_path = $candidate_inventory->{identity_lookup_path};
    my $lookup_dbh;
    my $index = _empty_index();
    my $identity_offset = 0;
    if (length($identity_lookup_path || '') && -r $identity_lookup_path) {
        require DBI;
        $lookup_dbh = DBI->connect(
            "dbi:SQLite:dbname=$identity_lookup_path", '', '',
            {RaiseError => 1, AutoCommit => 1},
        );
        $index = sub {
            return _candidate_ids_for_lookup($_[0], $lookup_dbh);
        };
        $identity_offset = scalar @$identities;
    }
    my $edge_offset = 0;
    my (@resolved, %seen);
    my $counts = {recording => 0, artist => 0, unmatched => 0};
    my ($index_step, $edge_step);
    $edge_step = sub {
        if (ref($should_continue) eq 'CODE' && !$should_continue->()) {
            $lookup_dbh->disconnect if $lookup_dbh;
            $edge_step = undef;
            return;
        }
        my $ok = eval {
            my $limit = $edge_offset + ASYNC_CHUNK_ROWS;
            $limit = @$edges if $limit > @$edges;
            while ($edge_offset < $limit) {
                _resolve_edge(
                    $edges->[$edge_offset++], $index,
                    \@resolved, \%seen, $counts,
                );
            }
            1;
        };
        unless ($ok) {
            $lookup_dbh->disconnect if $lookup_dbh;
            $edge_step = undef;
            return $callback->(
                undef, undef, $@ || 'Could not match guidance edges',
            );
        }
        if ($edge_offset < @$edges) {
            Slim::Utils::Timers::setTimer(
                undef, time() + ASYNC_RESUME_DELAY, $edge_step,
            );
            return;
        }
        $edge_step = undef;
        $lookup_dbh->disconnect if $lookup_dbh;
        my ($resolved_bundle, $stats) = _finish_resolution(
            $bundle, $identities, \@resolved, $counts, $prefix,
            $candidate_identity_count,
        );
        $callback->($resolved_bundle, $stats, undef);
    };
    $index_step = sub {
        if (ref($should_continue) eq 'CODE' && !$should_continue->()) {
            $lookup_dbh->disconnect if $lookup_dbh;
            $index_step = undef;
            $edge_step = undef;
            return;
        }
        my $ok = eval {
            my $limit = $identity_offset + ASYNC_CHUNK_ROWS;
            $limit = @$identities if $limit > @$identities;
            while ($identity_offset < $limit) {
                _index_candidate($identities->[$identity_offset++], $index);
            }
            1;
        };
        unless ($ok) {
            $lookup_dbh->disconnect if $lookup_dbh;
            $index_step = undef;
            $edge_step = undef;
            return $callback->(
                undef, undef, $@ || 'Could not index candidates',
            );
        }
        if ($identity_offset < @$identities) {
            Slim::Utils::Timers::setTimer(
                undef, time() + ASYNC_RESUME_DELAY, $index_step,
            );
            return;
        }
        my $next = $edge_step;
        $index_step = undef;
        Slim::Utils::Timers::setTimer(
            undef, time() + ASYNC_RESUME_DELAY, $next,
        );
    };
    Slim::Utils::Timers::setTimer(
        undef, time() + ASYNC_RESUME_DELAY, $index_step,
    );
}

1;
