package Plugins::BetterCallBliss::CandidateGuidance;

use strict;
use Slim::Utils::Log;

my $log = Slim::Utils::Log::logger('plugin.bettercallbliss');

sub _normalize_text {
    my $value = lc(shift || '');
    $value =~ s/^\s+|\s+$//g;
    $value =~ s/\s+/ /g;
    return $value;
}

sub _normalize_mbid {
    my $value = lc(shift || '');
    return $value =~ /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
        ? $value : '';
}

sub _recording_key {
    my ($artist, $title) = @_;
    return _normalize_text($artist) . "\0" . _normalize_text($title);
}

sub _index_candidates {
    my $identities = shift || [];
    my (%recording_mbid, %recording_name, %artist_mbid, %artist_name);
    for my $identity (@$identities) {
        next unless ref($identity) eq 'HASH';
        my $candidate_id = $identity->{candidate_id} || '';
        next unless $candidate_id =~ /^bliss-row-[1-9][0-9]*$/;
        my $recording_mbid = _normalize_mbid($identity->{recording_mbid});
        push @{$recording_mbid{$recording_mbid}}, $candidate_id
            if length $recording_mbid;
        my $recording_name = _recording_key(
            $identity->{artist}, $identity->{title},
        );
        push @{$recording_name{$recording_name}}, $candidate_id
            if $recording_name ne "\0";
        my $artist_mbid = _normalize_mbid($identity->{artist_mbid});
        push @{$artist_mbid{$artist_mbid}}, $candidate_id
            if length $artist_mbid;
        my $artist_name = _normalize_text($identity->{artist});
        push @{$artist_name{$artist_name}}, $candidate_id
            if length $artist_name;
    }
    return {
        recording_mbid => \%recording_mbid,
        recording_name => \%recording_name,
        artist_mbid => \%artist_mbid,
        artist_name => \%artist_name,
    };
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

sub resolve {
    my ($bundle, $candidate_inventory, $context) = @_;
    $bundle ||= {};
    $candidate_inventory ||= {};
    $context ||= {};
    my $job_id = $context->{job_id} || '';
    my $prefix = length $job_id ? "job=$job_id " : '';
    my $identities = $candidate_inventory->{identities} || [];
    my $index = _index_candidates($identities);
    my (@resolved, %seen);
    my ($recording_edges, $artist_edges, $unmatched_edges) = (0, 0, 0);

    for my $edge (@{$bundle->{edges} || []}) {
        next unless ref($edge) eq 'HASH';
        my @candidate_ids = _candidate_ids_for_edge($edge, $index);
        if (!@candidate_ids) {
            $unmatched_edges++;
            next;
        }
        for my $candidate_id (@candidate_ids) {
            my $source = ref($edge->{source}) eq 'HASH' ? $edge->{source} : {};
            my $key = join('|',
                $source->{kind} || '', $source->{id} || '',
                $candidate_id, $edge->{scope} || '',
                $edge->{provider} || '', $edge->{dataset_or_algorithm} || '',
            );
            next if $seen{$key}++;
            my %resolved_edge = %$edge;
            $resolved_edge{resolved_candidate_id} = $candidate_id;
            push @resolved, \%resolved_edge;
            if (($source->{kind} || '') eq 'recording') {
                $recording_edges++;
            } elsif (($source->{kind} || '') eq 'artist') {
                $artist_edges++;
            }
        }
    }

    my %resolved_bundle = %$bundle;
    $resolved_bundle{edges} = \@resolved;
    my $stats = {
        candidate_identity_count => scalar(@$identities),
        input_edge_count => scalar(@{$bundle->{edges} || []}),
        resolved_edge_count => scalar(@resolved),
        recording_edge_count => $recording_edges,
        artist_edge_count => $artist_edges,
        unmatched_edge_count => $unmatched_edges,
    };
    $log->info(
        $prefix . 'Candidate guidance resolved by Better Call Bliss'
        . " candidates=$stats->{candidate_identity_count}"
        . " input_edges=$stats->{input_edge_count}"
        . " resolved_edges=$stats->{resolved_edge_count}"
        . " recording_edges=$recording_edges artist_edges=$artist_edges"
        . " unmatched_edges=$unmatched_edges"
    );
    return (\%resolved_bundle, $stats);
}

1;
