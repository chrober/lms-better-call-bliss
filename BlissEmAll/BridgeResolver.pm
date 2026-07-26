package Plugins::BlissEmAll::BridgeResolver;

use strict;
use DBI;
use File::Spec::Functions qw(catfile);
use Scalar::Util qw(blessed);
use Slim::Schema;
use Slim::Utils::Misc;
use Slim::Utils::Unicode;

sub _fail {
    my ($code, $message) = @_;
    die "$code: $message\n";
}

sub _same_values {
    my ($left, $right) = @_;
    return 0 unless @$left == @$right;
    for my $index (0 .. $#$left) {
        return 0 unless defined $right->[$index]
            && $left->[$index] eq $right->[$index];
    }
    return 1;
}

sub _track_for_database_file {
    my ($roots, $database_file) = @_;
    my ($path, $cue_track) = ($database_file, 0);
    if ($path =~ s/\.CUE_TRACK\.([1-9][0-9]*)$//) {
        $cue_track = int($1);
    }
    $path =~ s{\\}{/}g;

    for my $root (@$roots) {
        my @parts = split m{/}, $path;
        my $absolute = catfile($root, @parts);
        my $encoded = Slim::Utils::Unicode::utf8encode_locale($absolute);
        $absolute = $encoded if !-e $absolute && -e $encoded;
        next unless -e $absolute;

        my $url = Slim::Utils::Misc::fileURLFromPath($absolute);
        my $track_id;
        if ($cue_track) {
            my $sth = Slim::Schema->dbh->prepare(
                'SELECT id, url FROM tracks '
                . 'WHERE url LIKE ? AND tracknum = ? '
                . 'AND remote = 0 AND audio = 1 LIMIT 1'
            );
            $sth->execute($url . '#%', $cue_track);
            my ($cue_id, $cue_url) = $sth->fetchrow_array;
            $sth->finish;
            next unless $cue_url;
            $track_id = $cue_id;
            $url = $cue_url;
        } else {
            my $sth = Slim::Schema->dbh->prepare(
                'SELECT id FROM tracks '
                . 'WHERE url = ? AND remote = 0 AND audio = 1 LIMIT 1'
            );
            $sth->execute($url);
            ($track_id) = $sth->fetchrow_array;
            $sth->finish;
        }
        next unless $track_id;
        my $track = Slim::Schema->find('Track', $track_id);
        return $track if blessed($track) && !$track->remote;
    }
    return;
}

sub resolve_bridge_preview {
    my $job = shift;
    my $artifact = $job->{artifact} || {};
    _fail('BRIDGE_ARTIFACT_INVALID', 'The optimizer did not return a bridge artifact')
        unless ($artifact->{artifact_kind} || '') eq 'contextual-bridge-analysis-v1';

    my $preview = $artifact->{selection_preview} || {};
    my $mode = $job->{options}->{extension_mode} || '';
    my $ordering = $job->{options}->{ordering_policy} || '';
    _fail('BRIDGE_ARTIFACT_INVALID', 'The optimizer returned the wrong source-order policy')
        unless ($artifact->{ordering_policy} || '') eq $ordering;
    _fail('BRIDGE_ARTIFACT_INVALID', 'The optimizer returned the wrong addition mode')
        unless (($mode eq 'automatic' || $mode eq 'exact_count')
            && ($preview->{mode} || '') eq $mode);
    _fail('BRIDGE_ARTIFACT_INVALID', 'The exact-count preview changed the requested count')
        if $mode eq 'exact_count'
            && (!exists $preview->{requested_added_tracks}
                || $preview->{requested_added_tracks}
                    != $job->{options}->{additional_track_count});
    _fail('BRIDGE_ARTIFACT_INVALID', 'The exact-count preview omitted its feasibility state')
        if $mode eq 'exact_count' && !exists $preview->{feasible};
    if ($mode eq 'exact_count' && !$preview->{feasible}) {
        my $infeasibility = $preview->{infeasibility} || {};
        my $code = $infeasibility->{code} || 'EXACT_COUNT_INFEASIBLE';
        my $requested = 0 + ($preview->{requested_added_tracks} || 0);
        my $found = 0 + ($infeasibility->{maximum_additions_found} || 0);
        my $upper = 0 + ($infeasibility->{structural_upper_bound} || 0);
        my $requested_noun = $requested == 1 ? 'track' : 'tracks';
        _fail(
            $code,
            'Could not add exactly ' . $requested . ' ' . $requested_noun
                . '. The search found '
                . 'a maximum of ' . $found . '; the structural upper bound is '
                . $upper . '. No partial result was accepted.',
        );
    }
    _fail('BRIDGE_ARTIFACT_INVALID', 'The optimizer did not return a final addition sequence')
        unless ref($preview->{final_sequence}) eq 'ARRAY';
    _fail('BRIDGE_ARTIFACT_INVALID', 'The addition preview failed its membership proofs')
        unless $preview->{original_subsequence_preserved}
            && $preview->{unique_membership};

    my @source = @{$job->{source_track_ids} || []};
    my @selected = @{$artifact->{selected_track_ids} || []};
    my %source = map { $_ => 1 } @source;
    my %selected = map { $_ => 1 } @selected;
    _fail('BRIDGE_ARTIFACT_INVALID', 'The optimized base route changed source membership')
        unless @source == @selected
            && scalar(keys %source) == @source
            && scalar(keys %selected) == @selected
            && !scalar(grep { !$selected{$_} } @source);
    _fail('BRIDGE_ARTIFACT_INVALID', 'The optimizer changed preserved source order')
        if $ordering eq 'preserve_order' && !_same_values(\@source, \@selected);

    my (@final, @originals, @bridges);
    my %seen;
    for my $index (0 .. $#{$preview->{final_sequence}}) {
        my $entry = $preview->{final_sequence}->[$index] || {};
        _fail('BRIDGE_ARTIFACT_INVALID', 'The final sequence has a non-contiguous position')
            unless defined $entry->{position} && $entry->{position} == $index;
        my $id = $entry->{track_id} || '';
        _fail('BRIDGE_ARTIFACT_INVALID', 'The final sequence contains an empty track identity')
            unless length $id;
        _fail('BRIDGE_ARTIFACT_INVALID', "Track '$id' occurs more than once")
            if $seen{$id}++;
        if (($entry->{kind} || '') eq 'original') {
            _fail('BRIDGE_ARTIFACT_INVALID', "Unknown original track '$id'")
                unless $source{$id};
            push @originals, $id;
        } elsif (($entry->{kind} || '') eq 'bridge') {
            _fail('BRIDGE_ARTIFACT_INVALID', "Invalid bridge identity '$id'")
                unless $id =~ /^bliss-row-([1-9][0-9]*)$/;
            push @bridges, [$id, 0 + $1];
        } else {
            _fail('BRIDGE_ARTIFACT_INVALID', "Unknown sequence kind for '$id'");
        }
        push @final, $id;
    }
    _fail('BRIDGE_ARTIFACT_INVALID', 'The final sequence changed the optimized base order')
        unless _same_values(\@originals, \@selected);
    _fail('BRIDGE_ARTIFACT_INVALID', 'The reported added-track count does not match the sequence')
        unless defined $preview->{added_track_count}
            && $preview->{added_track_count} == @bridges;
    if ($mode eq 'automatic') {
        _fail('BRIDGE_ARTIFACT_INVALID', 'The automatic preview exceeded its bridge budget')
            if @bridges > ($preview->{max_added_tracks} || 0);
    } else {
        _fail('BRIDGE_ARTIFACT_INVALID', 'The exact-count preview changed the requested count')
            unless defined $preview->{requested_added_tracks}
                && $preview->{requested_added_tracks}
                    == $job->{options}->{additional_track_count};
        _fail('BRIDGE_ARTIFACT_INVALID', 'The exact-count preview returned a partial result')
            unless @bridges == $job->{options}->{additional_track_count};
    }

    my %decision_for;
    for my $decision (@{$preview->{decisions} || []}) {
        next unless ($decision->{reason} || '') eq 'selected';
        my $bridge = $decision->{selected_bridge} || {};
        my $id = $bridge->{candidate_id} || '';
        _fail('BRIDGE_ARTIFACT_INVALID', 'A selected transition has no bridge identity')
            unless $id =~ /^bliss-row-[1-9][0-9]*$/;
        _fail('BRIDGE_ARTIFACT_INVALID', "Bridge '$id' was selected more than once")
            if $decision_for{$id};
        $decision_for{$id} = $decision;
    }
    _fail('BRIDGE_ARTIFACT_INVALID', 'A final bridge has no selected-transition decision')
        if scalar(grep { !$decision_for{$_->[0]} } @bridges);
    _fail('BRIDGE_ARTIFACT_INVALID', 'Selected-transition decisions do not match final bridges')
        unless scalar(keys %decision_for) == @bridges;

    my $database = $job->{capability}->{database};
    my $dbh = DBI->connect(
        "dbi:SQLite:dbname=$database", '', '',
        {
            RaiseError => 1,
            PrintError => 0,
            AutoCommit => 1,
            sqlite_unicode => 1,
            sqlite_open_flags => 1,
        },
    );
    _fail('BRIDGE_DATABASE_UNREADABLE', 'Could not open bliss.db read-only')
        unless $dbh;
    my $sth = $dbh->prepare(
        'SELECT File, Title, Artist, Album FROM TracksV2 '
        . 'WHERE rowid = ? AND Ignore IS NOT 1'
    );

    my %urls = %{$job->{track_urls} || {}};
    my %labels = %{$job->{labels} || {}};
    my %positions = %{$job->{original_positions} || {}};
    my %used_url = map { $urls{$_} => 1 } keys %urls;
    my @additions;
    my $ok = eval {
        for my $bridge (@bridges) {
            my ($id, $row_id) = @$bridge;
            $sth->execute($row_id);
            my ($file, $title, $artist, $album) = $sth->fetchrow_array;
            _fail('BRIDGE_TRACK_MISSING', "Bridge '$id' is no longer usable in bliss.db")
                unless defined $file;
            my $track = _track_for_database_file(
                $job->{capability}->{music_roots} || [], $file,
            );
            _fail('BRIDGE_TRACK_NOT_IN_LMS', "Bridge '$id' is not a local LMS track")
                unless blessed($track) && $track->can('url') && !$track->remote;
            my $url = $track->url;
            _fail('BRIDGE_TRACK_DUPLICATE', "Bridge '$id' duplicates a source or bridge track")
                if $used_url{$url}++;

            $urls{$id} = $url;
            $labels{$id} = {
                artist => $track->artistName || $artist || 'Unknown Artist',
                title => $track->title || $title || $file,
                album => $track->albumname || $album || '',
            };
            $positions{$id} = 0;
            my $decision = $decision_for{$id};
            my $selected_bridge = $decision->{selected_bridge} || {};
            push @additions, {
                track_id => $id,
                left_track_id => $decision->{left_track_id},
                right_track_id => $decision->{right_track_id},
                direct_percentile => $decision->{direct_percentile},
                semantic_pool => $decision->{semantic_pool} || 'bliss_only',
                semantic_tier => $selected_bridge->{semantic_tier} || 'bliss_only',
            };
        }
        1;
    };
    my $error = $@;
    $sth->finish;
    $dbh->disconnect;
    die $error unless $ok;

    return {
        final_track_ids => \@final,
        final_track_count => scalar @final,
        bridge_track_ids => [map { $_->[0] } @bridges],
        added_track_count => scalar @bridges,
        track_urls => \%urls,
        labels => \%labels,
        original_positions => \%positions,
        additions => \@additions,
    };
}

1;
