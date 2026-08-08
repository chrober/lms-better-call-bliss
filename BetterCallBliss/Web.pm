package Plugins::BetterCallBliss::Web;

use strict;
use File::Basename qw(basename);
use Slim::Schema;
use Slim::Player::Client;
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
        source_mode playlist_id route_player_id route_target_track_id ordering_policy extension_mode algorithm seed_limit
        learned_percent artist_window album_window track_window restart_count
        variation_percent generation_seed lastfm_enabled
        lastfm_track_guidance_percent lastfm_artist_guidance_percent
        max_added_tracks trigger_percent additional_track_count bridge_target_track_count target_track_count output_mode output_name
        queue_player_id queue_action queue_start_playback
    )) {
        $form->{$name} = $params->{$name} if defined $params->{$name};
    }
    $form->{source_mode} = 'saved_playlist'
        unless ($form->{source_mode} || '') eq 'route_to_track';
    return $form;
}

sub _form_from_job {
    my ($job, $defaults) = @_;
    my $options = ref($job->{options}) eq 'HASH' ? $job->{options} : {};
    my %params = (%$options, playlist_id => $job->{playlist_id});
    if ($job->{route_to_track}) {
        $params{source_mode} = 'route_to_track';
        $params{route_player_id} = $job->{route_player_id};
        $params{route_target_track_id} = $job->{route_target_track_id};
        $params{queue_player_id} = $options->{queue_player_id} || $job->{route_player_id};
    }
    my $form = _form_from_params(\%params, $defaults);
    $form->{output_name_generated} =
        $options->{output_name_generated} ? 1 : 0;
    $form->{generation_seed} = ''
        unless $options->{generation_seed_supplied};
    return $form;
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
        route_player_id => $job->{route_player_id},
        route_tail_label => $job->{route_tail_label},
        route_target_label => $job->{route_target_label},
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
            $view->{seed_growth_extension} = 1
                if $job->{options}->{extension_mode} eq 'seed_growth';
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
            if ($job->{options}->{extension_mode} eq 'seed_growth') {
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
            $view->{semantic_mode} = $artifact->{semantic_mode};
            my @additions;
            for my $addition (@{$job->{additions} || []}) {
                my $label = $job->{labels}->{$addition->{track_id}} || {};
                if ($job->{options}->{extension_mode} eq 'seed_growth') {
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
        for my $id (@{$job->{final_track_ids} || []}) {
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
    if (($form->{source_mode} || '') eq 'route_to_track') {
        $form->{route_player_id} ||= $form->{queue_player_id};
        if (!$form->{route_player_id} && $client) {
            $form->{route_player_id} = eval { $client->id } || '';
        }
        $form->{queue_player_id} ||= $form->{route_player_id};
        $form->{queue_action} ||= 'append';
        $form->{output_mode} = 'player_queue';
        $form->{ordering_policy} = 'preserve_order';
        $form->{extension_mode} = 'exact_count';
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
    if ($params->{create_copy}) {
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
    } elsif ($params->{run_route_to_track_preview}
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
            die "Choose a saved playlist"
                unless defined $form->{playlist_id} && "$form->{playlist_id}" =~ /^\d+$/;
            $job = Plugins::BetterCallBliss::Jobs::start_reorder_preview(
                int($form->{playlist_id}), $form,
            );
        };
        $error = $@;
        $error =~ s/\s+/ /g if $error;
        $log->warn("Could not start web preview: $error") if $error;
    } elsif ($params->{job_id}) {
        $job = Plugins::BetterCallBliss::Jobs::get($params->{job_id});
        $error = 'Preview job is no longer available' unless $job;
    }

    $form = _form_from_job($job, $defaults) if $job;

    $params->{bettercallbliss_playlists} = $playlists;
    $params->{bettercallbliss_players} = $players;
    $params->{bettercallbliss_form} = $form;
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
