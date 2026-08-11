package Plugins::BetterCallBliss::Web;

use strict;
use File::Basename qw(basename);
use URI::Escape qw(uri_escape_utf8);
use Slim::Schema;
use Slim::Player::Client;
use Slim::Player::Playlist;
use Slim::Player::Source;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Utils::Unicode;
use Slim::Web::HTTP;
use Slim::Web::Pages;
use Plugins::BetterCallBliss::BlissCompatibility;
use Plugins::BetterCallBliss::CandidateInventory;
use Plugins::BetterCallBliss::JobOptions;
use Plugins::BetterCallBliss::Jobs;
use Plugins::BetterCallBliss::LastFmEvidence;
use Plugins::BetterCallBliss::PlaylistWriter;

my $log = Slim::Utils::Log::logger('plugin.bettercallbliss');
my $plugin_prefs = preferences('plugin.bettercallbliss');
my $page = 'plugins/BetterCallBliss/index.html';
my $icon =
    'plugins/BetterCallBliss/html/images/bettercallbliss_MTL_icon_playlist_add_check_circle.png';

sub init {
    Slim::Web::Pages->addPageFunction($page, \&handler);
    Slim::Web::Pages->addPageLinks(
        'plugins', {'PLUGIN_BETTERCALLBLISS_NAME' => $page},
    );
    Slim::Web::Pages->addPageLinks(
        'icons', {'PLUGIN_BETTERCALLBLISS_NAME' => $icon},
    );
}

sub shutdown {
    Slim::Web::Pages->addPageLinks(
        'plugins', {'PLUGIN_BETTERCALLBLISS_NAME' => undef},
    );
    Slim::Web::Pages->addPageLinks(
        'icons', {'PLUGIN_BETTERCALLBLISS_NAME' => undef},
    );
}

sub _playlist_title {
    my $playlist = shift;
    my $url = eval { $playlist->url } || '';
    if ($url =~ /^file:/i) {
        my $path = Slim::Utils::Misc::pathFromFileURL($url);
        my $decoded = Slim::Utils::Unicode::utf8decode_locale($path || '');
        my $filename = basename($decoded || '');
        $filename =~ s/\.[^.]+$//;
        return $filename if length $filename;
    }
    return $playlist->title || $playlist->name;
}

sub _players {
    my @rows;
    for my $player (Slim::Player::Client::clients()) {
        next unless $player;
        my $id = eval { $player->id } || '';
        next unless length $id;
        my $name = eval { $player->name } || $id;
        push @rows, {
            id => $id,
            name => $name,
            power => eval { $player->power } ? 1 : 0,
            queue_count => 0 + (eval { Slim::Player::Playlist::count($player) } || 0),
            current_index => 0 + (eval { Slim::Player::Source::playingSongIndex($player) } || 0),
            active => ((eval { Slim::Player::Source::playmode($player) } || '') =~ /^(?:play|pause)$/) ? 1 : 0,
        };
    }
    @rows = sort { lc($a->{name} || '') cmp lc($b->{name} || '') } @rows;
    return \@rows;
}

sub _player_name {
    my $player_id = shift || '';
    return '' unless length $player_id;
    my $player = Slim::Player::Client::getClient($player_id);
    return $player ? (eval { $player->name } || $player_id) : $player_id;
}

sub _track_label {
    my $track_id = shift;
    return '' unless defined $track_id && "$track_id" =~ /^\d+$/;
    my $track = Slim::Schema->find('Track', int($track_id));
    return '' unless $track;
    my $artist = eval { $track->artistName } || 'Unknown Artist';
    my $title = eval { $track->title } || eval { $track->path } || 'Unknown Title';
    return "$artist - $title";
}

sub _route_context {
    my $form = shift || {};
    return unless ($form->{source_mode} || '') eq 'route_to_track';
    return {
        player_id => $form->{route_player_id} || $form->{queue_player_id} || '',
        player_name => _player_name($form->{route_player_id} || $form->{queue_player_id}),
        target_track_id => $form->{route_target_track_id},
        target_label => _track_label($form->{route_target_track_id}),
    };
}
sub _playlists {
    my @rows;
    for my $playlist (sort {
        lc($a->title || $a->name || '') cmp lc($b->title || $b->name || '')
    } Slim::Schema->rs('Playlist')->getPlaylists('all')->all) {
        next unless $playlist && $playlist->can('tracks');
        my $count = eval { $playlist->tracks->count } || 0;
        next unless $count >= 2;
        push @rows, {
            id => 0 + $playlist->id,
            title => _playlist_title($playlist),
            count => 0 + $count,
        };
    }
    return \@rows;
}

sub _form_from_params {
    my ($params, $defaults) = @_;
    my $form = {%$defaults};
    for my $name (qw(
        source_mode playlist_id source_player_id source_queue_scope route_player_id route_target_track_id quick_route ordering_policy extension_mode addition_purpose addition_amount_mode algorithm seed_limit
        learned_percent artist_window album_window track_window restart_count
        variation_percent generation_seed lastfm_enabled
        route_length_policy route_max_intermediates route_exact_intermediates
        lastfm_track_guidance_percent lastfm_artist_guidance_percent
        max_added_tracks trigger_percent additional_track_count bridge_target_track_count target_track_count output_mode output_name
        queue_player_id queue_action queue_start_playback
    )) {
        $form->{$name} = $params->{$name} if defined $params->{$name};
    }
    $form->{source_mode} = 'saved_playlist'
        unless ($form->{source_mode} || '') eq 'route_to_track'
            || ($form->{source_mode} || '') eq 'player_queue';
    $form->{source_queue_scope} ||= 'full';
    return $form;
}

sub _form_from_job {
    my ($job, $defaults) = @_;
    my $options = ref($job->{options}) eq 'HASH' ? $job->{options} : {};
    my %params = (%$options, playlist_id => $job->{playlist_id});
    if (($job->{source_mode} || '') eq 'player_queue') {
        $params{source_mode} = 'player_queue';
        $params{source_player_id} = $job->{source_player_id};
        $params{source_queue_scope} = $job->{source_queue_scope};
    }
    if ($job->{route_to_track}) {
        $params{source_mode} = 'route_to_track';
        $params{route_player_id} = $job->{route_player_id};
        $params{route_target_track_id} = $job->{route_target_track_id};
        $params{queue_player_id} = $options->{queue_player_id} || $job->{route_player_id};
        $params{quick_route} = $job->{quick_route} ? 1 : 0;
    }
    my $form = _form_from_params(\%params, $defaults);
    $form->{output_name_generated} =
        $options->{output_name_generated} ? 1 : 0;
    $form->{generation_seed} = ''
        unless $options->{generation_seed_supplied};
    return $form;
}


sub _job_mode_label {
    my $job = shift || {};
    my $options = ref($job->{options}) eq 'HASH' ? $job->{options} : {};
    my $purpose = $options->{addition_purpose} || '';
    return 'Bliss me there...' if $job->{route_to_track};
    return 'Reorder only' if ($options->{extension_mode} || 'none') eq 'none';
    return 'Improve difficult transitions' if $purpose eq 'automatic'
        || ($options->{extension_mode} || '') eq 'automatic';
    return 'Extend playlist' if $purpose eq 'extend_playlist'
        || ($options->{extension_mode} || '') eq 'fixed_source_extension';
    return 'Strict gap bridge placement';
}

sub _job_summary {
    my $job = shift || {};
    my $options = ref($job->{options}) eq 'HASH' ? $job->{options} : {};
    my $started = int($job->{started_at} || 0);
    my $finished = int($job->{finished_at} || 0);
    my $elapsed = int(($finished || time()) - ($job->{started_at} || time()));
    $elapsed = 0 if $elapsed < 0;
    my $state = $job->{state} || 'unknown';
    my $status = $job->{stage} || $state;
    if ($state eq 'failed') {
        $status = 'Failed: ' . ($job->{error_code} || 'UNKNOWN_FAILURE');
    } elsif ($state eq 'completed') {
        $status = 'Completed';
        $status .= ' - added ' . (0 + ($job->{added_track_count} || 0))
            if ($options->{extension_mode} || 'none') ne 'none';
    } elsif ($state eq 'cancelled') {
        $status = 'Cancelled';
    }
    return {
        id => $job->{id},
        state => $state,
        stage => $job->{stage} || '',
        status => $status,
        status_detail => Plugins::BetterCallBliss::Jobs::status_detail($job),
        status_detail_lines => Plugins::BetterCallBliss::Jobs::status_detail_lines($job),
        title => $job->{playlist_title} || 'Untitled source',
        mode => _job_mode_label($job),
        started_at => $started,
        started_text => Plugins::BetterCallBliss::Jobs::start_text($started),
        duration_text => Plugins::BetterCallBliss::Jobs::duration_text($elapsed),
        live_status => Plugins::BetterCallBliss::Jobs::compact_status($job),
        elapsed_seconds => $elapsed,
        can_cancel => $state eq 'running' ? 1 : 0,
        can_open => 1,
    };
}

sub _job_lists {
    my @summaries = map { _job_summary($_) } Plugins::BetterCallBliss::Jobs::all();
    my @running = grep { ($_->{state} || '') eq 'running' } @summaries;
    my @recent = grep { ($_->{state} || '') ne 'running' } @summaries;
    splice(@recent, 8) if @recent > 8;
    return (\@running, \@recent);
}

sub _semantic_evidence_summary {
    my $evidence = shift;
    return 'Bliss only; no Last.fm edge was attached to this selection'
        unless ref($evidence) eq 'ARRAY' && @$evidence;
    my @parts;
    for my $edge (@$evidence) {
        next unless ref($edge) eq 'HASH';
        my $provider = $edge->{provider} || 'semantic';
        my $raw_kind = lc($edge->{kind} || '');
        my $kind = ($raw_kind eq 'track' || $raw_kind eq 'recording')
            ? 'similar track' : 'similar artist';
        my $source = $edge->{source_endpoint} || $edge->{scope} || '';
        $source =~ s/_/ /g;
        my $where = length $source ? " from $source" : '';
        my $rank = defined $edge->{raw_rank} ? ', rank ' . $edge->{raw_rank} : '';
        my $score = defined $edge->{raw_score}
            ? sprintf(', score %.2f', 0 + $edge->{raw_score}) : '';
        push @parts, "$provider $kind$where$rank$score";
    }
    return @parts ? join('; ', @parts)
        : 'Bliss only; no Last.fm edge was attached to this selection';
}

sub _semantic_evidence_stats {
    my $additions = shift;
    my %stats = (
        total => 0,
        bliss_only => 0,
        lastfm_any => 0,
        lastfm_artist => 0,
        lastfm_track => 0,
        lastfm_edges => 0,
        other_semantic => 0,
    );
    for my $addition (@{$additions || []}) {
        next unless ref($addition) eq 'HASH';
        $stats{total}++;
        my ($lastfm_any, $lastfm_artist, $lastfm_track, $other_semantic) = (0, 0, 0, 0);
        for my $edge (@{$addition->{semantic_evidence} || []}) {
            next unless ref($edge) eq 'HASH';
            my $provider = lc($edge->{provider} || '');
            my $kind = lc($edge->{kind} || '');
            if ($provider eq 'last.fm') {
                $lastfm_any = 1;
                $stats{lastfm_edges}++;
                if ($kind eq 'recording' || $kind eq 'track') {
                    $lastfm_track = 1;
                } elsif ($kind eq 'artist') {
                    $lastfm_artist = 1;
                }
            } else {
                $other_semantic = 1;
            }
        }
        $stats{lastfm_any}++ if $lastfm_any;
        $stats{lastfm_artist}++ if $lastfm_artist;
        $stats{lastfm_track}++ if $lastfm_track;
        $stats{other_semantic}++ if $other_semantic;
        $stats{bliss_only}++ unless $lastfm_any || $other_semantic;
    }
    return \%stats;
}
sub _result_view {
    my $job = shift;
    return unless $job;
    my $view = {
        id => $job->{id},
        state => $job->{state},
        stage => $job->{stage},
        status_detail => Plugins::BetterCallBliss::Jobs::status_detail($job),
        status_detail_lines => Plugins::BetterCallBliss::Jobs::status_detail_lines($job),
        playlist_title => $job->{playlist_title},
        output_mode => $job->{options}->{output_mode},
        output_name => $job->{options}->{output_name},
        output_name_generated => $job->{options}->{output_name_generated} ? 1 : 0,
        queue_player_id => $job->{options}->{queue_player_id},
        queue_player_name => _player_name($job->{options}->{queue_player_id}),
        queue_action => $job->{options}->{queue_action},
        queue_start_playback => $job->{options}->{queue_start_playback},
        ordering_policy => $job->{options}->{ordering_policy},
        preserve_order => $job->{options}->{ordering_policy} eq 'preserve_order' ? 1 : 0,
        extension_mode => $job->{options}->{extension_mode},
        source_track_count => 0 + ($job->{track_count} || 0),
        variation_percent => $job->{options}->{variation_percent},
        generation_seed => $job->{options}->{generation_seed},
        lastfm_enabled => $job->{options}->{lastfm_enabled},
        lastfm_track_guidance_percent =>
            $job->{options}->{lastfm_track_guidance_percent},
        lastfm_artist_guidance_percent =>
            $job->{options}->{lastfm_artist_guidance_percent},
        lastfm_state => $job->{lastfm_state},
        write_state => $job->{write_state},
        write_stage => $job->{write_stage},
        write_error_code => $job->{write_error_code},
        write_error => $job->{write_error},
        persistence => $job->{persistence},
        mixing_strategy => $job->{options}->{algorithm},
        blissmixer_strategy => $job->{capability}->{algorithm},
        learned_matrix_available => $job->{capability}->{matrix_available} ? 1 : 0,
        route_to_track => $job->{route_to_track} ? 1 : 0,
        source_mode => $job->{source_mode} || ($job->{route_to_track} ? 'route_to_track' : 'saved_playlist'),
        source_player_id => $job->{source_player_id},
        source_player_name => $job->{source_player_name},
        source_queue_scope => $job->{source_queue_scope},
        source_queue_count => $job->{source_queue_count},
        source_queue_current_index => $job->{source_queue_current_index},
        source_queue_active => $job->{source_queue_active} ? 1 : 0,
        source_overwrite_supported => ($job->{playlist_id} || 0) > 0 && !$job->{route_to_track} ? 1 : 0,
        route_player_id => $job->{route_player_id},
        route_tail_label => $job->{route_tail_label},
        route_target_label => $job->{route_target_label},
        route_source_context_count => 0 + ($job->{route_source_context_count} || 0),
        route_length_policy => $job->{options}->{route_length_policy},
        route_max_intermediates => 0 + ($job->{options}->{route_max_intermediates} || 0),
        route_exact_intermediates => 0 + ($job->{options}->{route_exact_intermediates} || 0),
    };
    if (($view->{mixing_strategy} || '') eq 'static') {
        $view->{mixing_note} = 'Static BlissMixer weights were used for every contextual distance.';
    } elsif (!$view->{learned_matrix_available}) {
        $view->{mixing_note} = 'No learned matrix was available. Adaptive used variance for multi-track contexts and Static BlissMixer weights for one-track contexts.';
    } else {
        $view->{mixing_note} = 'Adaptive used the learned matrix according to the selected blend.';
    }

    if ($job->{state} eq 'failed') {
        $view->{error_code} = $job->{error_code};
        $view->{error} = $job->{error};
    } elsif ($job->{state} eq 'completed') {
        my $artifact = $job->{artifact};
        my $selected = $artifact->{selected_strategy} || 'adaptive';
        $view->{selected_strategy} = $selected;
        if ($job->{options}->{extension_mode} ne 'none') {
            my $preview = $artifact->{selection_preview} || {};
            $view->{bridge_extension} = 1;
            $view->{automatic_extension} = 1
                if $job->{options}->{extension_mode} eq 'automatic';
            $view->{exact_count_extension} = 1
                if $job->{options}->{extension_mode} eq 'exact_count'
                    || $job->{options}->{extension_mode} eq 'target_count'
                    || $job->{options}->{extension_mode} eq 'double_count';
            $view->{target_count_extension} = 1
                if $job->{options}->{extension_mode} eq 'target_count';
            $view->{double_count_extension} = 1
                if $job->{options}->{extension_mode} eq 'double_count';
            $view->{fixed_source_extension} = 1
                if $job->{options}->{extension_mode} eq 'fixed_source_extension';
            $view->{extend_playlist_extension} = 1
                if $job->{options}->{extension_mode} eq 'fixed_source_extension';
            $view->{base_route_objective} = sprintf(
                '%.3f', $artifact->{selected_route_objective},
            );
            $view->{added_track_count} = 0 + ($preview->{added_track_count} || 0);
            $view->{final_track_count} = 0 + ($job->{final_track_count} || 0);
            $view->{max_added_tracks} = 0 + ($preview->{max_added_tracks} || 0);
            $view->{requested_added_tracks} =
                0 + ($preview->{requested_added_tracks} || 0);
            $view->{target_track_count} =
                0 + ($preview->{target_track_count} || 0);
            $view->{relevance_reference_track_count} =
                0 + ($preview->{relevance_reference_track_count} || 0);
            if ($job->{options}->{extension_mode} eq 'fixed_source_extension') {
                my $relevance = $preview->{relevance_summary} || {};
                my $route = $preview->{route_summary} || {};
                $view->{relevance_minimum} = sprintf(
                    '%.4f', 0 + ($relevance->{minimum_distance} || 0),
                );
                $view->{relevance_mean} = sprintf(
                    '%.4f', 0 + ($relevance->{mean_distance} || 0),
                );
                $view->{relevance_maximum} = sprintf(
                    '%.4f', 0 + ($relevance->{maximum_distance} || 0),
                );
                $view->{route_transition_sum} = sprintf(
                    '%.3f', 0 + ($route->{transition_sum} || 0),
                );
                $view->{route_worst_transition} = sprintf(
                    '%.3f', 0 + ($route->{worst_transition} || 0),
                );
                $view->{route_objective} = sprintf(
                    '%.3f', 0 + ($route->{objective} || 0),
                );
                $view->{route_arc_error} = sprintf(
                    '%.3f', 0 + ($route->{arc_error} || 0),
                );
            }
            $view->{maximum_additions_found} =
                0 + (($preview->{search} || {})->{maximum_additions_found} || 0);
            $view->{structural_upper_bound} =
                0 + (($preview->{search} || {})->{structural_upper_bound} || 0);
            $view->{trigger_percent} = int(
                100 * ($artifact->{trigger_percentile} || 0) + 0.5
            );
            if ($job->{route_to_track}) {
                my $first_gap = ($artifact->{gaps} || [])->[0] || {};
                $view->{route_direct_percent} = sprintf(
                    '%.1f', 100 * ($first_gap->{direct_percentile} || 0),
                );
                $view->{route_fallback_direct} =
                    ($job->{options}->{route_length_policy} || '') eq 'automatic'
                    && ($first_gap->{direct_percentile} || 0)
                        > ($artifact->{trigger_percentile} || 0)
                    && !$view->{added_track_count} ? 1 : 0;
            }
            $view->{semantic_mode} = $artifact->{semantic_mode};
            my @additions;
            for my $addition (@{$job->{additions} || []}) {
                my $label = $job->{labels}->{$addition->{track_id}} || {};
                if ($job->{options}->{extension_mode} eq 'fixed_source_extension') {
                    push @additions, {
                        artist => $label->{artist} || 'Unknown Artist',
                        title => $label->{title} || $addition->{track_id},
                        relevance_distance => sprintf(
                            '%.4f', 0 + ($addition->{relevance_distance} || 0),
                        ),
                        semantic_tier => $addition->{semantic_tier} || 'bliss_only',
                        semantic_pool => $addition->{semantic_pool} || 'bliss_only',
                        semantic_summary => _semantic_evidence_summary(
                            $addition->{semantic_evidence},
                        ),
                    };
                    next;
                }
                my $left = $job->{labels}->{$addition->{left_track_id}} || {};
                my $right = $job->{labels}->{$addition->{right_track_id}} || {};
                push @additions, {
                    artist => $label->{artist} || 'Unknown Artist',
                    title => $label->{title} || $addition->{track_id},
                    left => $left->{title} || $addition->{left_track_id},
                    right => $right->{title} || $addition->{right_track_id},
                    direct_percent => sprintf(
                        '%.1f', 100 * ($addition->{direct_percentile} || 0),
                    ),
                    semantic_pool => $addition->{semantic_pool} || 'bliss_only',
                    semantic_tier => $addition->{semantic_tier} || 'bliss_only',
                    semantic_summary => _semantic_evidence_summary(
                        $addition->{semantic_evidence},
                    ),
                };
            }
            $view->{additions} = \@additions;
            $view->{semantic_stats} = _semantic_evidence_stats(\@additions);

            my @decisions;
            for my $decision (@{$preview->{decisions} || []}) {
                my $left = $job->{labels}->{$decision->{left_track_id}} || {};
                my $right = $job->{labels}->{$decision->{right_track_id}} || {};
                my $reason = $decision->{reason} || 'unknown';
                $reason =~ s/_/ /g;
                push @decisions, {
                    left => $left->{title} || $decision->{left_track_id},
                    right => $right->{title} || $decision->{right_track_id},
                    direct_percent => sprintf(
                        '%.1f', 100 * ($decision->{direct_percentile} || 0),
                    ),
                    reason => $reason,
                    semantic_pool => $decision->{semantic_pool} || 'bliss_only',
                };
            }
            $view->{gap_decisions} = \@decisions;
        } else {
            my $candidate = $selected eq 'adaptive-arc'
                ? $artifact->{arc} : $artifact->{primary};
            $view->{objective} = sprintf('%.3f', $candidate->{objective});
            $view->{worst_transition} = sprintf(
                '%.3f', $candidate->{worst_transition},
            );
        }
        my @order;
        my $position = 0;
        my %bridge = map { $_ => 1 } @{$job->{bridge_track_ids} || []};
        my @display_ids = @{$job->{final_track_ids} || []};
        if ($job->{route_to_track} && ($job->{route_output_skip_source_count} || 0) > 0) {
            my $start = $job->{route_output_skip_source_count} - 1;
            @display_ids = @display_ids[$start .. $#display_ids] if $start <= $#display_ids;
        }
        for my $id (@display_ids) {
            my $label = $job->{labels}->{$id} || {};
            push @order, {
                position => ++$position,
                artist => $label->{artist} || 'Unknown Artist',
                title => $label->{title} || $id,
                original_position => $job->{original_positions}->{$id} || 0,
                bridge => $bridge{$id} ? 1 : 0,
            };
        }
        $view->{order} = \@order;
    }
    return $view;
}

sub handler {
    my ($client, $params) = @_;
    $params ||= {};
    my $capability = Plugins::BetterCallBliss::BlissCompatibility::snapshot();
    my $defaults = Plugins::BetterCallBliss::JobOptions::defaults($capability);
    my $form = _form_from_params($params, $defaults);
    if (($form->{source_mode} || '') eq 'player_queue') {
        $form->{source_player_id} ||= $form->{queue_player_id};
        if (!$form->{source_player_id} && $client) {
            $form->{source_player_id} = eval { $client->id } || '';
        }
        $form->{source_queue_scope} ||= 'full';
    }
    if (($form->{source_mode} || '') eq 'route_to_track') {
        $form->{route_player_id} ||= $form->{queue_player_id};
        if (!$form->{route_player_id} && $client) {
            $form->{route_player_id} = eval { $client->id } || '';
        }
        $form->{queue_player_id} ||= $form->{route_player_id};
        $form->{queue_action} ||= 'append';
        $form->{output_mode} = 'player_queue';
        $form->{ordering_policy} = 'preserve_order';
        $form->{extension_mode} = 'destination_route';
    }
    if (($params->{run_preview} || $params->{run_route_to_track_preview}) && $params->{lastfm_present}) {
        $form->{lastfm_enabled} = $params->{lastfm_enabled} ? 1 : 0;
    }
    my $playlists = _playlists();
    my $players = _players();

    my $trimmed_output_name = $form->{output_name} || '';
    $trimmed_output_name =~ s/^\s+|\s+$//g;
    $form->{output_name} = $trimmed_output_name;
    $form->{output_name_generated} = length($form->{output_name}) ? 0 : 1;

    my ($job, $error);
    if ($params->{cancel_job}) {
        eval {
            die "Preview job is no longer available"
                unless $params->{job_id};
            $job = Plugins::BetterCallBliss::Jobs::cancel($params->{job_id});
        };
        $error = $@;
        $error =~ s/\s+/ /g if $error;
    } elsif ($params->{create_copy}) {
        eval {
            die "Preview job is no longer available"
                unless $params->{job_id};
            $job = Plugins::BetterCallBliss::Jobs::get($params->{job_id});
            die "Preview job is no longer available" unless $job;
            Plugins::BetterCallBliss::Jobs::create_copy($params->{job_id}, $params);
        };
        $error = $@;
        $error =~ s/\s+/ /g if $error;
        $error = undef if $job && ($job->{write_state} || '') eq 'failed';
    } elsif ($params->{overwrite_source}) {
        eval {
            die "Preview job is no longer available"
                unless $params->{job_id};
            $job = Plugins::BetterCallBliss::Jobs::get($params->{job_id});
            die "Preview job is no longer available" unless $job;
            Plugins::BetterCallBliss::Jobs::overwrite_source(
                $params->{job_id}, $params->{confirm_overwrite} ? 1 : 0,
                $params,
            );
        };
        $error = $@;
        $error =~ s/\s+/ /g if $error;
        $error = undef if $job && ($job->{write_state} || '') eq 'failed';
    } elsif ($params->{send_to_queue}) {
        eval {
            die "Preview job is no longer available"
                unless $params->{job_id};
            $job = Plugins::BetterCallBliss::Jobs::get($params->{job_id});
            die "Preview job is no longer available" unless $job;
            Plugins::BetterCallBliss::Jobs::send_to_queue($params->{job_id}, $params);
        };
        $error = $@;
        $error =~ s/\s+/ /g if $error;
        $error = undef if $job && ($job->{write_state} || '') eq 'failed';
    } elsif ($params->{quick_route} || $params->{run_route_to_track_preview}
        || ($params->{run_preview} && ($form->{source_mode} || '') eq 'route_to_track')) {
        eval {
            $job = Plugins::BetterCallBliss::Jobs::start_route_to_track_preview(
                $form->{route_player_id} || $form->{queue_player_id},
                $form->{route_target_track_id},
                $form,
            );
        };
        $error = $@;
        $error =~ s/\s+/ /g if $error;
        $log->warn("Could not start route-to-track preview: $error") if $error;
    } elsif ($params->{run_preview}) {
        eval {
            if (($form->{source_mode} || '') eq 'player_queue') {
                $job = Plugins::BetterCallBliss::Jobs::start_queue_preview(
                    $form->{source_player_id}, $form->{source_queue_scope}, $form,
                );
            } else {
                die "Choose a saved playlist"
                    unless defined $form->{playlist_id} && "$form->{playlist_id}" =~ /^\d+$/;
                $job = Plugins::BetterCallBliss::Jobs::start_reorder_preview(
                    int($form->{playlist_id}), $form,
                );
            }
        };
        $error = $@;
        $error =~ s/\s+/ /g if $error;
        $log->warn("Could not start web preview: $error") if $error;
    } elsif ($params->{job_id}) {
        $job = Plugins::BetterCallBliss::Jobs::get($params->{job_id});
        $error = 'Preview job is no longer available' unless $job;
    }

    $form = _form_from_job($job, $defaults) if $job;

    my ($running_jobs, $recent_jobs) = _job_lists();
    $params->{bettercallbliss_running_jobs} = $running_jobs;
    $params->{bettercallbliss_recent_jobs} = $recent_jobs;

    $params->{bettercallbliss_playlists} = $playlists;
    $params->{bettercallbliss_players} = $players;
    $params->{bettercallbliss_form} = $form;
    $params->{bettercallbliss_quick_route} = $job
        ? ($job->{quick_route} ? 1 : 0) : ($form->{quick_route} ? 1 : 0);
    if (($form->{source_mode} || '') eq 'route_to_track') {
        my $player = uri_escape_utf8($form->{route_player_id} || '');
        my $target = uri_escape_utf8($form->{route_target_track_id} || '');
        my $base_route_url = $page
            . '?player=' . $player
            . '&source_mode=route_to_track&route_player_id=' . $player
            . '&queue_player_id=' . $player
            . '&route_target_track_id=' . $target;
        $params->{bettercallbliss_advanced_route_url} = $base_route_url;
        $params->{bettercallbliss_recalculate_route_url}
            = $base_route_url . '&quick_route=1';
    }
    $params->{bettercallbliss_route_context} = _route_context($form);
    $params->{bettercallbliss_defaults} = $defaults;
    $params->{bettercallbliss_capability} = $capability;
    $params->{bettercallbliss_lastmix_available}
        = Plugins::BetterCallBliss::LastFmEvidence::available();
    $params->{bettercallbliss_candidate_inventory}
        = Plugins::BetterCallBliss::CandidateInventory::status();
    $params->{bettercallbliss_job} = _result_view($job) if $job;
    $params->{bettercallbliss_error} = $error if $error;
    return Slim::Web::HTTP::filltemplatefile($page, $params);
}

1;
