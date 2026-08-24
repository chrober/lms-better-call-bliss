use strict;
use warnings;
use FindBin;
use Test::More;
use lib "$FindBin::Bin/..";

require "$FindBin::Bin/../BetterCallBliss/LogDiagnostics.pm";

my $job = {
    id => 'preview-test-0001',
    route_to_track => 1,
    route_player_id => 'aa:bb:cc:dd:ee:ff',
    route_source_context_count => 2,
    route_start_label => 'Seed Artist - Tail Song',
    route_target_label => 'Target Artist - Destination Song',
    route_output_skip_source_count => 1,
    track_count => 2,
    final_track_count => 3,
    added_track_count => 1,
    history_track_ids => [qw(context)],
    source_track_ids => [qw(tail target)],
    final_track_ids => [qw(tail bridge target)],
    labels => {
        context => {artist => 'Context Artist', title => 'Context Song'},
        tail => {artist => 'Seed Artist', title => 'Tail Song'},
        bridge => {artist => 'Bridge Artist', title => 'Bridge Song'},
        target => {artist => 'Target Artist', title => 'Destination Song'},
    },
    track_urls => {
        context => 'file:///context.flac',
        tail => 'file:///tail.flac',
        bridge => 'file:///bridge.flac',
        target => 'file:///target.flac',
    },
    capability => {matrix_available => 1},
    candidate_inventory => {
        allowed_row_count => 64128,
        unmatched_row_count => 1,
        cache_state => 'memory',
    },
    native_performance => {total_ms => 1488, database_cache => 'hit'},
    options => {
        extension_mode => 'destination_route',
        algorithm => 'adaptive',
        seed_limit => 3,
        learned_percent => 20,
        artist_window => 5,
        album_window => 10,
        track_window => 100,
        restart_count => 50,
        variation_percent => 25,
        lastfm_enabled => 1,
        lastfm_track_guidance_percent => 25,
        lastfm_artist_guidance_percent => 25,
        route_length_policy => 'automatic',
        route_direct_caution => 'cautious',
        route_min_intermediates => 0,
        route_max_intermediates => 4,
        route_search_effort => 'fast',
        trigger_percent => 70,
    },
    additions => [{
        track_id => 'bridge',
        semantic_evidence => [{
            provider => 'last.fm',
            dataset_or_algorithm => 'LastMix track.getSimilar',
            kind => 'recording',
            scope => 'endpoint_local',
            source_endpoint => 'left',
            raw_rank => 4,
            raw_score => 0.91,
            identity_confidence => 0.85,
            cache_state => 'fresh',
        }, {
            provider => 'last.fm',
            dataset_or_algorithm => 'LastMix artist.getSimilar',
            kind => 'artist',
            scope => 'endpoint_local',
            source_endpoint => 'right',
            raw_rank => 7,
            raw_score => 0.75,
            identity_confidence => 1,
            cache_state => 'fresh',
        }],
    }],
    request_path => '/cache/request.json',
    result_path => '/cache/result.json',
    semantic_path => '/cache/semantic.json',
    progress_path => '/cache/progress.json',
    database_identity => 'dev:inode:size:mtime',
    lastfm_state => 'fresh',
    artifact => {
        selected_strategy => 'adaptive',
        usable_library_track_count => 64128,
        eligible_candidate_count => 64125,
        frozen_reference_count => 64125,
        semantic_mode => 'semantic-assisted',
        scoring_provenance => {
            context_policy => 'frozen-destination-route-context',
            seed_policy => 'recent immutable listening history plus the locked queue tail',
            configured_algorithm => 'adaptive',
            configured_learned_percent => 20,
            effective_base_learned_percent => 20,
            learned_matrix_available => 1,
            base_matrix_sha256 => ('a' x 64),
            fallback_policy => 'BlissMixer-compatible fallback',
        },
        gaps => [{
            position => 1,
            left_track_id => 'tail',
            right_track_id => 'target',
            direct_distance => 2.4,
            direct_percentile => 0.88,
            triggering => 1,
            semantic_pool => 'endpoint_local',
            semantic_candidate_count => 120,
            evaluated_candidate_count => 128,
            accepted_candidate_count => 12,
            repeat_rejected_count => 3,
            acoustic_rejected_count => 113,
            shortlisted_candidate_count => 128,
            shortlist_excluded_count => 63997,
        }],
        provider_states => [{
            provider => 'last.fm',
            state => 'fresh',
            request_count => 4,
            failure_count => 0,
            error_codes => [],
        }],
        selection_preview => {
            search => {
                evaluated_states => 235,
                retained_states => 91,
                maximum_additions_found => 4,
                structural_upper_bound => 4,
            },
            quality_target_met => 1,
            achieved_max_leg_percentile => 0.55,
            route_quality => {
                matrix_role => 'adaptive-context',
                adjacent_worst_percentile => 0.42,
                model_selection => {
                    direct_transition_caution => 'cautious',
                    model_disagreement_percentile => 0.27,
                    disagreement_triggered_search => 1,
                    selected_matrix_role => 'adaptive-context',
                    adaptive_algorithm => 'blended(learned=20%)',
                    adaptive_seed_track_ids => ['history', 'tail'],
                    adaptive_seed_limit => 3,
                    configured_learned_percent => 20,
                    adaptive_variance_failure => undef,
                    fallback_reason => undef,
                    direct_edge_models => [{
                        matrix_role => 'adaptive-context',
                        source_relative_percentile => 0.88,
                    }, {
                        matrix_role => 'static-weights',
                        source_relative_percentile => 0.61,
                    }, {
                        matrix_role => 'learned-matrix',
                        source_relative_percentile => 0.76,
                    }],
                },
                adjacent_legs => [{
                    position => 1,
                    left_track_id => 'tail',
                    right_track_id => 'bridge',
                    distance => 0.31,
                    source_relative_percentile => 0.20,
                }, {
                    position => 2,
                    left_track_id => 'bridge',
                    right_track_id => 'target',
                    distance => 0.47,
                    source_relative_percentile => 0.42,
                }],
                secondary_models => [{
                    matrix_role => 'static-weights',
                    adjacent_worst_percentile => 0.55,
                    adjacent_legs => [{
                        position => 1,
                        left_track_id => 'tail',
                        right_track_id => 'bridge',
                        distance => 0.51,
                        source_relative_percentile => 0.55,
                    }, {
                        position => 2,
                        left_track_id => 'bridge',
                        right_track_id => 'target',
                        distance => 0.41,
                        source_relative_percentile => 0.35,
                    }],
                }],
            },
        },
    },
};

my $start = join "\n",
    @{Plugins::BetterCallBliss::LogDiagnostics::start_info_lines($job)};
like(
    $start,
    qr/User action: Bliss me there\.\.\. when we're through!(?:\n|$)/,
    'information log names the queue-end action',
);

my $now_playing_start = join "\n",
    @{Plugins::BetterCallBliss::LogDiagnostics::start_info_lines({
        %$job,
        route_source => 'now_playing',
    })};
like(
    $now_playing_start,
    qr/User action: Bliss me there\.\.\.(?:\n|$)/,
    'information log distinguishes the now-playing context action',
);
my $round_trip_start = join "\n",
    @{Plugins::BetterCallBliss::LogDiagnostics::start_info_lines({
        %$job,
        route_source => 'round_trip',
        route_rejoin_label => 'Queue Artist - Rejoin Song',
    })};
like($round_trip_start, qr/User action: Bliss me there\.\.\. and back again!/,
    'information log distinguishes the round-trip context action');
like($round_trip_start, qr/Target Artist - Destination Song -> Queue Artist - Rejoin Song/,
    'round-trip source diagnostics identify waypoint and rejoin anchors');
like($start, qr/Seed Artist - Tail Song.*Target Artist - Destination Song/,
    'information log identifies both destination-route endpoints');
like($start, qr/Mixing strategy: adaptive.*learned matrix available/,
    'information log explains the effective acoustic strategy');
like($start, qr/similar tracks 25%.*similar artists 25%/,
    'information log exposes both Last.fm guidance settings');
like($start, qr/destination route \(automatic, 0-4 intermediate tracks, fast effort, target 70%, cautious direct-transition caution\)/,
    'information log explains destination length, effort, and target settings');
like($start, qr/64128 local LMS-matched Bliss rows; 1 non-LMS rows excluded; cache memory/,
    'information log summarizes the frozen candidate inventory');
like($start, qr/Immutable listening history \(1\):.*Context Artist/s,
    'information log lists immutable listening history separately');
like($start, qr/Route members \(2\):.*Seed Artist.*Target Artist/s,
    'information log lists only the actual route anchors as route members');

my $result = join "\n",
    @{Plugins::BetterCallBliss::LogDiagnostics::result_info_lines($job)};
like($result, qr/Semantic provider: last\.fm; state fresh; 4 requests, 0 failures/,
    'information log reports provider health');
like($result, qr/strategy adaptive; 64128 usable library tracks; 64125 eligible candidates.*semantic mode semantic-assisted/,
    'information log reports native inventory and semantic statistics');
like($result, qr/Native optimizer performance: 1488 ms total; database cache hit/,
    'information log reports native runtime and cache state');
like($result, qr/235 states evaluated, 91 retained; maximum additions found 4/,
    'information log reports bounded selection-search statistics');
like($result, qr/1 added tracks supported by track similarity, 1 by artist similarity/,
    'information log counts selected additions supported by Last.fm');
like($result, qr/Adaptive destination matrix: blended\(learned=20%\) from 2\/3 recent analyzed seed tracks; configured learned share 20%/,
    'information log explains the effective adaptive destination matrix');
like($result, qr/Direct transition acoustic comparison: adaptive-context 88\.0%.*static-weights 61\.0%.*learned-matrix 76\.0%/,
    'information log compares direct-edge acoustic models');
like($result, qr/governing adaptive-context worst adjacent percentile 42\.0%; target met/,
    'information log reports governing whole-route quality');
like($result, qr/disagreement 27\.0%; caution cautious; disagreement-triggered search yes/,
    'information log explains why cautious automatic routing searched');
like($result, qr/Consensus secondary-model measurement: static-weights.*55\.0%.*included in cautious route acceptance/,
    'information log explains that both acoustic views constrained cautious selection');
like($result, qr/Cautious consensus result: worst available-model adjacent percentile 55\.0%; target met/,
    'information log summarizes the consensus percentile that controls acceptance');
like($result, qr/Selected route \(3\):.*Tail Song.*Bridge Song.*Destination Song/s,
    'destination logging omits earlier context and lists only the audible route');
unlike($result, qr/Context Song/, 'earlier queue context is absent from the audible route');

my $debug = join "\n",
    @{Plugins::BetterCallBliss::LogDiagnostics::result_debug_lines($job)};
like($debug, qr/Artifacts: request=\/cache\/request\.json.*database_identity=/,
    'debug log exposes artifact identities and paths');
like($debug, qr/Route leg 1:.*adaptive-context \(governing\).*static-weights \(consensus\)/,
    'debug log marks both model measurements as part of cautious consensus');
like($debug, qr/Gap 1:.*direct distance=2\.4000 percentile=88\.0%.*candidates=120 evaluated=128 accepted=12.*shortlist_excluded=63997/,
    'debug log reports per-gap candidate and rejection aggregates');
like($debug, qr/Addition evidence: Bridge Artist.*kind=recording.*rank=4/s,
    'debug log reports detailed Last.fm recording evidence');
like($debug, qr/id=bridge; url=file:\/\/\/bridge\.flac/,
    'debug route details include stable identity and LMS URL');

my $legacy = {%$job, artifact => {%{$job->{artifact}}}};
$legacy->{artifact}->{selection_preview} = {
    %{$job->{artifact}->{selection_preview}},
    route_quality => {%{$job->{artifact}->{selection_preview}->{route_quality}}},
};
delete $legacy->{artifact}->{selection_preview}->{route_quality}->{secondary_models};
delete $legacy->{artifact}->{scoring_provenance};
my $legacy_result = eval {
    Plugins::BetterCallBliss::LogDiagnostics::result_info_lines($legacy)
};
ok($legacy_result, 'plugin logging remains compatible with an older optimizer artifact');

like($result, qr/Scoring provenance: context frozen-destination-route-context.*configured adaptive.*learned matrix available/,
    'information log reports generalized scoring provenance');
like($debug, qr/Scoring provenance details: context=frozen-destination-route-context.*base_matrix=a{64}/,
    'debug log reports matrix identity and fallback provenance');

my $direct_best_effort = {
    %$job,
    added_track_count => 0,
    final_track_count => 2,
    final_track_ids => [qw(tail target)],
    artifact => {
        %{$job->{artifact}},
        selection_preview => {
            %{$job->{artifact}->{selection_preview}},
            quality_target_met => 0,
            achieved_max_leg_percentile => 0.90,
            best_effort => 1,
            best_effort_reason => 'no-beneficial-bridge-over-direct',
        },
    },
};
my $direct_best_effort_result = join "\n",
    @{Plugins::BetterCallBliss::LogDiagnostics::result_info_lines(
        $direct_best_effort,
    )};
like(
    $direct_best_effort_result,
    qr/No beneficial bridge was found:.*direct destination was retained/,
    'information log explicitly explains a direct best-effort fallback',
);

done_testing();
