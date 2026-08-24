package Plugins::BetterCallBliss::LogDiagnostics;

use strict;
use Plugins::BetterCallBliss::RouteMode;

use constant INFO_TRACK_LIMIT => 100;

sub _label {
    my ($job, $track_id) = @_;
    my $label = ref($job->{labels}) eq 'HASH'
        ? $job->{labels}->{$track_id} || {} : {};
    return ($label->{artist} || 'Unknown Artist') . ' - '
        . ($label->{title} || $track_id || 'Unknown Track');
}

sub _action_name {
    my $job = shift;
    return Plugins::BetterCallBliss::RouteMode::action_name(
        $job->{route_source},
    ) if $job->{route_to_track};
    my $mode = ($job->{options} || {})->{extension_mode} || 'none';
    return 'Reorder playlist' if $mode eq 'none';
    return 'Improve difficult transitions' if $mode eq 'automatic';
    return 'Extend playlist';
}

sub _artifact {
    my $job = shift;
    return ref($job->{artifact}) eq 'HASH' ? $job->{artifact} : {};
}

sub _scoring_provenance {
    my $job = shift;
    my $artifact = _artifact($job);
    return ref($artifact->{scoring_provenance}) eq 'HASH'
        ? $artifact->{scoring_provenance} : {};
}

sub _source_description {
    my $job = shift;
    if ($job->{route_to_track}) {
        my $description = sprintf(
            'player queue %s; route source %s; %d context tracks; %s -> %s',
            $job->{route_player_id} || 'unknown',
            ($job->{route_source} || 'queue_end') eq 'queue_end'
                ? 'queue end'
                : ($job->{route_source} || '') eq 'round_trip'
                    ? 'now playing with queue rejoin'
                    : 'now playing',
            0 + ($job->{route_source_context_count} || $job->{track_count} || 0),
            $job->{route_start_label} || _label($job, $job->{route_start_track_id}),
            $job->{route_target_label} || _label($job, $job->{route_target_track_id}),
        );
        $description .= ' -> '
            . ($job->{route_rejoin_label}
                || _label($job, $job->{route_rejoin_track_id}))
            if ($job->{route_source} || '') eq 'round_trip';
        return $description;
    }
    if (($job->{source_mode} || '') eq 'player_queue') {
        return sprintf(
            'player queue %s (%s snapshot, %d tracks)',
            $job->{source_player_name} || $job->{source_player_id} || 'unknown',
            $job->{source_queue_scope} || 'full',
            0 + ($job->{track_count} || 0),
        );
    }
    return sprintf(
        'saved playlist "%s" (%d tracks)',
        $job->{playlist_title} || $job->{playlist_id} || 'unknown',
        0 + ($job->{track_count} || 0),
    );
}

sub _track_lines {
    my ($job, $heading, $ids, $limit, $detailed) = @_;
    $ids = [] unless ref($ids) eq 'ARRAY';
    $limit = scalar @$ids unless defined $limit;
    my @lines = (sprintf('%s (%d):', $heading, scalar @$ids));
    my $last = @$ids
        ? ($#$ids < $limit - 1 ? $#$ids : $limit - 1) : -1;
    for (my $index = 0; $index <= $last; $index++) {
        my $id = $ids->[$index];
        my $line = sprintf('  %d. %s', $index + 1, _label($job, $id));
        if ($detailed) {
            my $url = ref($job->{track_urls}) eq 'HASH'
                ? $job->{track_urls}->{$id} : undef;
            $line .= " [id=$id" . (defined $url ? "; url=$url" : '') . ']';
        }
        push @lines, $line;
    }
    push @lines, sprintf('  ... %d additional tracks omitted', @$ids - $limit)
        if @$ids > $limit;
    return @lines;
}

sub _display_route_ids {
    my $job = shift;
    my @ids = @{ref($job->{final_track_ids}) eq 'ARRAY'
        ? $job->{final_track_ids} : []};
    if ($job->{route_to_track} && ($job->{route_output_skip_source_count} || 0) > 0) {
        my $start = $job->{route_output_skip_source_count} - 1;
        @ids = @ids[$start .. $#ids] if $start <= $#ids;
    }
    return \@ids;
}

sub _semantic_counts {
    my $job = shift;
    my ($recording, $artist, $bliss_only) = (0, 0, 0);
    for my $addition (@{ref($job->{additions}) eq 'ARRAY' ? $job->{additions} : []}) {
        my ($has_recording, $has_artist) = (0, 0);
        for my $evidence (@{ref($addition->{semantic_evidence}) eq 'ARRAY'
            ? $addition->{semantic_evidence} : []}) {
            next unless ($evidence->{provider} || '') =~ /^last\.fm/i;
            $has_recording = 1 if ($evidence->{kind} || '') eq 'recording';
            $has_artist = 1 if ($evidence->{kind} || '') eq 'artist';
        }
        $recording++ if $has_recording;
        $artist++ if $has_artist;
        $bliss_only++ unless $has_recording || $has_artist;
    }
    return ($recording, $artist, $bliss_only);
}

sub _evidence_label {
    my $addition = shift;
    my ($recording, $artist) = (0, 0);
    for my $evidence (@{ref($addition->{semantic_evidence}) eq 'ARRAY'
        ? $addition->{semantic_evidence} : []}) {
        next unless ($evidence->{provider} || '') =~ /^last\.fm/i;
        $recording = 1 if ($evidence->{kind} || '') eq 'recording';
        $artist = 1 if ($evidence->{kind} || '') eq 'artist';
    }
    return 'Last.fm track and artist similarity' if $recording && $artist;
    return 'Last.fm track similarity' if $recording;
    return 'Last.fm artist similarity' if $artist;
    return 'Bliss acoustic evidence only';
}

sub start_info_lines {
    my $job = shift || {};
    my $options = ref($job->{options}) eq 'HASH' ? $job->{options} : {};
    my $capability = ref($job->{capability}) eq 'HASH' ? $job->{capability} : {};
    my @lines = (
        'User action: ' . _action_name($job),
        'Source: ' . _source_description($job),
        sprintf(
            'Mixing strategy: %s; adaptive context %d; learned blend %d%%; learned matrix %s.',
            $options->{algorithm} || 'unknown',
            0 + ($options->{seed_limit} || 0),
            0 + ($options->{learned_percent} || 0),
            $capability->{matrix_available} ? 'available' : 'not available',
        ),
        sprintf(
            'Repeat windows: artist %d, album %d, track %d; route restarts %d; variation %d%%.',
            0 + ($options->{artist_window} || 0),
            0 + ($options->{album_window} || 0),
            0 + ($options->{track_window} || 0),
            0 + ($options->{restart_count} || 0),
            0 + ($options->{variation_percent} || 0),
        ),
    );
    my $ordering = ($options->{ordering_policy} || '') eq 'preserve_order'
        ? 'preserve source order and fill gaps'
        : 'optimize source and added tracks together';
    my $mode = $options->{extension_mode} || 'none';
    my $addition = $mode eq 'none' ? 'none'
        : $mode eq 'automatic' ? 'improve difficult transitions'
        : $mode eq 'destination_route' ? sprintf(
            'destination route (%s, %d-%d intermediate tracks, %s effort, target %d%%%s)',
            $options->{route_length_policy} || 'automatic',
            0 + ($options->{route_min_intermediates} || 0),
            0 + ($options->{route_max_intermediates} || 0),
            $options->{route_search_effort} || 'unknown',
            0 + ($options->{trigger_percent} || 0),
            ($options->{route_length_policy} || 'automatic') eq 'automatic'
                ? ', ' . ($options->{route_direct_caution} || 'normal') . ' direct-transition caution' : '',
        ) : $mode;
    push @lines, "Job mode: $ordering; additional tracks: $addition.";
    push @lines, sprintf(
        'Adaptive gap context: %s.',
        ($options->{gap_context_mode} || 'rolling') eq 'frozen'
            ? 'freeze weights once per original source gap'
            : 'follow the evolving route and recalculate weights after additions',
    ) if $mode eq 'automatic' && ($options->{algorithm} || '') eq 'adaptive';
    if (ref($job->{candidate_inventory}) eq 'HASH') {
        push @lines, sprintf(
            'Candidate inventory: %d local LMS-matched Bliss rows; %d non-LMS rows excluded; cache %s.',
            0 + ($job->{candidate_inventory}->{allowed_row_count} || 0),
            0 + ($job->{candidate_inventory}->{unmatched_row_count} || 0),
            $job->{candidate_inventory}->{cache_state} || 'unknown',
        );
    }
    if ($options->{lastfm_enabled}) {
        push @lines, sprintf(
            'Last.fm guidance: enabled; similar tracks %d%%, similar artists %d%%; failures fall back to Bliss.',
            0 + ($options->{lastfm_track_guidance_percent} || 0),
            0 + ($options->{lastfm_artist_guidance_percent} || 0),
        );
    } else {
        push @lines, 'Last.fm guidance: disabled.';
    }
    push @lines, _track_lines(
        $job, 'Immutable listening history', $job->{history_track_ids},
        INFO_TRACK_LIMIT, 0,
    ) if $job->{route_to_track} && @{$job->{history_track_ids} || []};
    push @lines, _track_lines(
        $job, $job->{route_to_track} ? 'Route members' : 'Source tracks',
        $job->{source_track_ids}, INFO_TRACK_LIMIT, 0,
    );
    return \@lines;
}

sub _provider_lines {
    my $job = shift;
    my $artifact = _artifact($job);
    my @providers = @{ref($artifact->{provider_states}) eq 'ARRAY'
        ? $artifact->{provider_states} : []};
    return ('Last.fm evidence: ' . ($job->{lastfm_state} || 'unknown') . '.')
        unless @providers;
    return map {
        sprintf(
            'Semantic provider: %s; state %s; %d requests, %d failures%s.',
            $_->{provider} || 'unknown',
            $_->{state} || 'unknown',
            0 + ($_->{request_count} || 0),
            0 + ($_->{failure_count} || 0),
            ref($_->{error_codes}) eq 'ARRAY' && @{$_->{error_codes}}
                ? '; errors ' . join(',', @{$_->{error_codes}}) : '',
        )
    } @providers;
}

sub _destination_quality_lines {
    my $job = shift;
    return () unless $job->{route_to_track};
    my $preview = ((ref($job->{artifact}) eq 'HASH' ? $job->{artifact} : {})
        ->{selection_preview} || {});
    my $quality = ref($preview->{route_quality}) eq 'HASH'
        ? $preview->{route_quality} : {};
    return () unless %$quality;
    my $selection = ref($quality->{model_selection}) eq 'HASH'
        ? $quality->{model_selection} : {};
    my @lines;
    my @direct = @{ref($selection->{direct_edge_models}) eq 'ARRAY'
        ? $selection->{direct_edge_models} : []};
    if (defined $selection->{adaptive_algorithm}) {
        my $seed_count = ref($selection->{adaptive_seed_track_ids}) eq 'ARRAY'
            ? scalar @{$selection->{adaptive_seed_track_ids}} : 0;
        my $fallback = $selection->{fallback_reason}
            ? "; fallback $selection->{fallback_reason}" : '';
        my $variance_failure = $selection->{adaptive_variance_failure}
            ? "; variance calculation failed: $selection->{adaptive_variance_failure}"
            : '';
        push @lines, sprintf(
            'Adaptive destination matrix: %s from %d/%d recent analyzed seed tracks; configured learned share %d%%%s%s.',
            $selection->{adaptive_algorithm},
            $seed_count,
            0 + ($selection->{adaptive_seed_limit} || 0),
            0 + ($selection->{configured_learned_percent} || 0),
            $fallback,
            $variance_failure,
        );
    }
    if (@direct) {
        push @lines, 'Direct transition acoustic comparison: ' . join(', ', map {
            sprintf('%s %.1f%%', $_->{matrix_role} || 'unknown',
                100 * ($_->{source_relative_percentile} || 0))
        } @direct)
            . sprintf(
                '; disagreement %.1f%%; caution %s; disagreement-triggered search %s; governing model %s.',
                100 * ($selection->{model_disagreement_percentile} || 0),
                $selection->{direct_transition_caution} || 'normal',
                $selection->{disagreement_triggered_search} ? 'yes' : 'no',
                $quality->{matrix_role} || 'unknown',
            );
    }
    push @lines, sprintf(
        'Selected route acoustic quality: governing %s worst adjacent percentile %.1f%%%s.',
        $quality->{matrix_role} || 'unknown',
        100 * ($quality->{adjacent_worst_percentile} || 0),
        defined $preview->{quality_target_met}
            ? ($preview->{quality_target_met} ? '; target met' : '; target missed, best effort')
            : '',
    );
    for my $secondary (@{ref($quality->{secondary_models}) eq 'ARRAY'
        ? $quality->{secondary_models} : []}) {
        my $cautious = ($selection->{direct_transition_caution} || 'normal')
            eq 'cautious';
        push @lines, sprintf(
            '%s secondary-model measurement: %s worst adjacent percentile %.1f%%%s.',
            $cautious ? 'Consensus' : 'Advisory',
            $secondary->{matrix_role} || 'unknown',
            100 * ($secondary->{adjacent_worst_percentile} || 0),
            $cautious ? '; included in cautious route acceptance and ranking'
                : '; it did not affect selection',
        );
    }
    if (($selection->{direct_transition_caution} || 'normal') eq 'cautious'
        && defined $preview->{achieved_max_leg_percentile}) {
        push @lines, sprintf(
            'Cautious consensus result: worst available-model adjacent percentile %.1f%%; %s.',
            100 * ($preview->{achieved_max_leg_percentile} || 0),
            $preview->{quality_target_met} ? 'target met' : 'target missed',
        );
    }
    if (($preview->{best_effort_reason} || '')
        eq 'no-beneficial-bridge-over-direct') {
        push @lines,
            'No beneficial bridge was found: every searched repeat-safe bridge path improved the cautious direct result by less than one percentile point, or made it worse; the direct destination was retained.';
    }
    return @lines;
}

sub result_info_lines {
    my $job = shift || {};
    my @lines = (sprintf(
        'Result: %d source tracks -> %d final tracks; %d additions.',
        0 + ($job->{track_count} || 0),
        0 + ($job->{final_track_count} || 0),
        0 + ($job->{added_track_count} || 0),
    ));
    my $artifact = _artifact($job);
    push @lines, sprintf(
        'Optimizer result: strategy %s; %d usable library tracks; %d eligible candidates; %d reference observations; semantic mode %s.',
        $artifact->{selected_strategy} || 'unknown',
        0 + ($artifact->{usable_library_track_count} || 0),
        0 + ($artifact->{eligible_candidate_count} || 0),
        0 + ($artifact->{frozen_reference_count} || 0),
        $artifact->{semantic_mode} || 'not applicable',
    );
    my $provenance = _scoring_provenance($job);
    if (%$provenance) {
        push @lines, sprintf(
            'Scoring provenance: context %s; seeds %s; configured %s with learned share %d%%; effective base share %d%%; learned matrix %s.',
            $provenance->{context_policy} || 'unknown',
            $provenance->{seed_policy} || 'unknown',
            $provenance->{configured_algorithm} || 'unknown',
            0 + ($provenance->{configured_learned_percent} || 0),
            0 + ($provenance->{effective_base_learned_percent} || 0),
            $provenance->{learned_matrix_available} ? 'available' : 'not available',
        );
    }
    if (ref($job->{native_performance}) eq 'HASH') {
        push @lines, sprintf(
            'Native optimizer performance: %d ms total; database cache %s.',
            0 + ($job->{native_performance}->{total_ms} || 0),
            $job->{native_performance}->{database_cache} || 'unknown',
        );
    }
    my $search = (($artifact->{selection_preview} || {})->{search} || {});
    push @lines, sprintf(
        'Selection search: %d states evaluated, %d retained; maximum additions found %d of structural upper bound %d.',
        0 + ($search->{evaluated_states} || 0),
        0 + ($search->{retained_states} || 0),
        0 + ($search->{maximum_additions_found} || 0),
        0 + ($search->{structural_upper_bound} || 0),
    ) if %$search;
    push @lines, _provider_lines($job) if ($job->{options} || {})->{lastfm_enabled};
    my ($recording, $artist, $bliss_only) = _semantic_counts($job);
    if ($job->{added_track_count}) {
        push @lines, ($job->{options} || {})->{lastfm_enabled}
            ? sprintf(
                'Last.fm contribution: %d added tracks supported by track similarity, %d by artist similarity; %d additions used Bliss acoustic evidence only.',
                $recording, $artist, $bliss_only,
            )
            : sprintf('Addition evidence: %d additions used Bliss acoustic evidence.',
                0 + ($job->{added_track_count} || 0));
    }
    push @lines, _destination_quality_lines($job);
    my $addition_index = 0;
    for my $addition (@{ref($job->{additions}) eq 'ARRAY' ? $job->{additions} : []}) {
        $addition_index++;
        my $detail = _evidence_label($addition);
        $detail .= sprintf('; relevance distance %.4f', $addition->{relevance_distance})
            if defined $addition->{relevance_distance};
        push @lines, sprintf(
            'Addition %d: %s [%s].',
            $addition_index, _label($job, $addition->{track_id}), $detail,
        );
    }
    push @lines, _track_lines(
        $job, 'Selected route', _display_route_ids($job), INFO_TRACK_LIMIT, 0,
    );
    return \@lines;
}

sub _quality_by_role {
    my $quality = shift;
    my %models;
    $models{$quality->{matrix_role} || 'governing'} = {
        matrix_role => $quality->{matrix_role} || 'governing',
        adjacent_legs => $quality->{adjacent_legs} || [],
    };
    for my $secondary (@{ref($quality->{secondary_models}) eq 'ARRAY'
        ? $quality->{secondary_models} : []}) {
        $models{$secondary->{matrix_role} || 'secondary'} = $secondary;
    }
    return \%models;
}

sub result_debug_lines {
    my $job = shift || {};
    my @lines = (sprintf(
        'Artifacts: request=%s result=%s semantic=%s progress=%s database_identity=%s.',
        $job->{request_path} || 'unknown',
        $job->{result_path} || 'unknown',
        $job->{semantic_path} || 'unknown',
        $job->{progress_path} || 'not-supported',
        $job->{database_identity} || 'unknown',
    ));
    push @lines, _track_lines($job, 'Immutable listening-history details',
        $job->{history_track_ids}, undef, 1)
        if $job->{route_to_track} && @{$job->{history_track_ids} || []};
    push @lines, _track_lines($job, 'Source track details',
        $job->{source_track_ids}, undef, 1);
    push @lines, _track_lines($job, 'Selected route details',
        _display_route_ids($job), undef, 1);

    my $artifact = _artifact($job);
    my $provenance = _scoring_provenance($job);
    push @lines, sprintf(
        'Scoring provenance details: context=%s gap_context=%s base_matrix=%s fallback=%s.',
        $provenance->{context_policy} || 'unknown',
        $provenance->{gap_context_mode} || 'not-applicable',
        $provenance->{base_matrix_sha256} || 'unknown',
        $provenance->{fallback_policy} || 'unknown',
    ) if %$provenance;
    for my $gap (@{ref($artifact->{gaps}) eq 'ARRAY' ? $artifact->{gaps} : []}) {
        my $triggering = !defined $gap->{triggering} ? 'not-applicable'
            : $gap->{triggering} ? 'yes' : 'no';
        push @lines, sprintf(
            'Gap %d: %s -> %s; direct distance=%.4f percentile=%.1f%% triggering=%s semantic_pool=%s candidates=%d evaluated=%d accepted=%d rejected_repeat=%d rejected_acoustic=%d shortlisted=%d shortlist_excluded=%d.',
            0 + ($gap->{position} || 0),
            _label($job, $gap->{left_track_id}),
            _label($job, $gap->{right_track_id}),
            0 + ($gap->{direct_distance} || 0),
            100 * ($gap->{direct_percentile} || 0),
            $triggering,
            $gap->{semantic_pool} || 'unknown',
            0 + ($gap->{semantic_candidate_count} || 0),
            0 + ($gap->{evaluated_candidate_count} || 0),
            0 + ($gap->{accepted_candidate_count} || 0),
            0 + ($gap->{repeat_rejected_count} || 0),
            0 + ($gap->{acoustic_rejected_count} || 0),
            0 + ($gap->{shortlisted_candidate_count} || 0),
            0 + ($gap->{shortlist_excluded_count} || 0),
        );
    }

    my $selected = $artifact->{selected_strategy} || '';
    my $route = $selected eq 'adaptive-arc'
        ? $artifact->{arc} : $artifact->{primary};
    if (ref($route) eq 'HASH') {
        for my $leg (@{ref($route->{legs}) eq 'ARRAY' ? $route->{legs} : []}) {
            push @lines, sprintf(
                'Contextual route leg %d: seeds=[%s] -> %s; algorithm=%s distance=%.4f.',
                0 + ($leg->{position} || 0),
                join(', ', map { _label($job, $_) }
                    @{ref($leg->{seed_track_ids}) eq 'ARRAY'
                        ? $leg->{seed_track_ids} : []}),
                _label($job, $leg->{candidate_track_id}),
                $leg->{algorithm} || 'unknown',
                0 + ($leg->{distance} || 0),
            );
        }
    }

    my $preview = ($artifact->{selection_preview} || {});
    my $quality = ref($preview->{route_quality}) eq 'HASH'
        ? $preview->{route_quality} : {};
    if (%$quality) {
        my $models = _quality_by_role($quality);
        my $governing = $quality->{matrix_role} || 'governing';
        my $secondary_label =
            ((($quality->{model_selection} || {})->{direct_transition_caution} || 'normal')
                eq 'cautious') ? 'consensus' : 'advisory';
        for my $leg (@{ref($quality->{adjacent_legs}) eq 'ARRAY'
            ? $quality->{adjacent_legs} : []}) {
            my @measurements;
            for my $role (sort {
                ($a eq $governing ? 0 : 1) <=> ($b eq $governing ? 0 : 1)
                    || $a cmp $b
            } keys %$models) {
                my ($same) = grep {
                    ($_->{position} || 0) == ($leg->{position} || 0)
                        && ($_->{left_track_id} || '') eq ($leg->{left_track_id} || '')
                        && ($_->{right_track_id} || '') eq ($leg->{right_track_id} || '')
                } @{ref($models->{$role}->{adjacent_legs}) eq 'ARRAY'
                    ? $models->{$role}->{adjacent_legs} : []};
                next unless $same;
                push @measurements, sprintf(
                    '%s%s distance=%.4f percentile=%.1f%%',
                    $role, $role eq $governing ? ' (governing)' : " ($secondary_label)",
                    0 + ($same->{distance} || 0),
                    100 * ($same->{source_relative_percentile} || 0),
                );
            }
            push @lines, sprintf(
                'Route leg %d: %s -> %s; %s.',
                0 + ($leg->{position} || 0),
                _label($job, $leg->{left_track_id}),
                _label($job, $leg->{right_track_id}),
                join('; ', @measurements),
            );
        }
    }

    for my $addition (@{ref($job->{additions}) eq 'ARRAY' ? $job->{additions} : []}) {
        my $evidence = ref($addition->{semantic_evidence}) eq 'ARRAY'
            ? $addition->{semantic_evidence} : [];
        if (!@$evidence) {
            push @lines, 'Addition evidence: ' . _label($job, $addition->{track_id})
                . '; Bliss acoustic evidence only.';
            next;
        }
        for my $item (@$evidence) {
            push @lines, sprintf(
                'Addition evidence: %s; provider=%s algorithm=%s kind=%s scope=%s endpoint=%s rank=%s score=%s confidence=%s cache=%s.',
                _label($job, $addition->{track_id}),
                $item->{provider} || 'unknown',
                $item->{dataset_or_algorithm} || 'unknown',
                $item->{kind} || 'unknown',
                $item->{scope} || 'unknown',
                $item->{source_endpoint} || 'unknown',
                defined $item->{raw_rank} ? $item->{raw_rank} : 'n/a',
                defined $item->{raw_score} ? $item->{raw_score} : 'n/a',
                defined $item->{identity_confidence} ? $item->{identity_confidence} : 'n/a',
                $item->{cache_state} || 'unknown',
            );
        }
    }
    return \@lines;
}

1;
