package Plugins::BlissEmAll::Web;

use strict;
use File::Basename qw(basename);
use Slim::Schema;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Utils::Unicode;
use Slim::Web::HTTP;
use Slim::Web::Pages;
use Plugins::BlissEmAll::BlissCompatibility;
use Plugins::BlissEmAll::JobOptions;
use Plugins::BlissEmAll::Jobs;
use Plugins::BlissEmAll::PlaylistWriter;

my $log = Slim::Utils::Log::logger('plugin.blissemall');
my $plugin_prefs = preferences('plugin.blissemall');
my $page = 'plugins/BlissEmAll/index.html';
my $icon =
    'plugins/BlissEmAll/html/images/blissemall_MTL_icon_timeline.png';

sub init {
    Slim::Web::Pages->addPageFunction($page, \&handler);
    Slim::Web::Pages->addPageLinks(
        'plugins', {'PLUGIN_BLISSEMALL_NAME' => $page},
    );
    Slim::Web::Pages->addPageLinks(
        'icons', {'PLUGIN_BLISSEMALL_NAME' => $icon},
    );
}

sub shutdown {
    Slim::Web::Pages->addPageLinks(
        'plugins', {'PLUGIN_BLISSEMALL_NAME' => undef},
    );
    Slim::Web::Pages->addPageLinks(
        'icons', {'PLUGIN_BLISSEMALL_NAME' => undef},
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
        playlist_id ordering_policy extension_mode algorithm seed_limit
        learned_percent artist_window album_window track_window restart_count
        max_added_tracks trigger_percent additional_track_count output_mode output_name
    )) {
        $form->{$name} = $params->{$name} if defined $params->{$name};
    }
    return $form;
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
        ordering_policy => $job->{options}->{ordering_policy},
        preserve_order => $job->{options}->{ordering_policy} eq 'preserve_order' ? 1 : 0,
        extension_mode => $job->{options}->{extension_mode},
        write_state => $job->{write_state},
        write_stage => $job->{write_stage},
        write_error_code => $job->{write_error_code},
        write_error => $job->{write_error},
        persistence => $job->{persistence},
    };
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
                if $job->{options}->{extension_mode} eq 'exact_count';
            $view->{base_route_objective} = sprintf(
                '%.3f', $artifact->{selected_route_objective},
            );
            $view->{added_track_count} = 0 + ($preview->{added_track_count} || 0);
            $view->{final_track_count} = 0 + ($job->{final_track_count} || 0);
            $view->{max_added_tracks} = 0 + ($preview->{max_added_tracks} || 0);
            $view->{requested_added_tracks} =
                0 + ($preview->{requested_added_tracks} || 0);
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
                    semantic_pool => $addition->{semantic_pool},
                    semantic_tier => $addition->{semantic_tier},
                };
            }
            $view->{additions} = \@additions;

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
    my $capability = Plugins::BlissEmAll::BlissCompatibility::snapshot();
    my $defaults = Plugins::BlissEmAll::JobOptions::defaults($capability);
    my $form = _form_from_params($params, $defaults);
    my $playlists = _playlists();

    my $trimmed_output_name = $form->{output_name} || '';
    $trimmed_output_name =~ s/^\s+|\s+$//g;
    $form->{output_name} = $trimmed_output_name;
    $form->{output_name_generated} = 0;
    if (defined $form->{playlist_id}
        && "$form->{playlist_id}" =~ /^\d+$/
        && !length($form->{output_name})) {
        for my $playlist (@$playlists) {
            if ($playlist->{id} == $form->{playlist_id}) {
                my $suffix = $form->{extension_mode} ne 'none'
                    ? ($plugin_prefs->get('extended_suffix') || 'Extended')
                    : ($plugin_prefs->get('output_suffix') || 'Optimized');
                $form->{output_name} =
                    Plugins::BlissEmAll::PlaylistWriter::available_copy_name(
                        $playlist->{title} . ' ' . $suffix,
                    );
                $form->{output_name_generated} = 1;
                last;
            }
        }
    }

    my ($job, $error);
    if ($params->{create_copy}) {
        eval {
            die "Preview job is no longer available"
                unless $params->{job_id};
            $job = Plugins::BlissEmAll::Jobs::get($params->{job_id});
            die "Preview job is no longer available" unless $job;
            Plugins::BlissEmAll::Jobs::create_copy($params->{job_id});
        };
        $error = $@;
        $error =~ s/\s+/ /g if $error;
        $error = undef if $job && ($job->{write_state} || '') eq 'failed';
    } elsif ($params->{run_preview}) {
        eval {
            die "Choose a saved playlist"
                unless defined $form->{playlist_id} && "$form->{playlist_id}" =~ /^\d+$/;
            $job = Plugins::BlissEmAll::Jobs::start_reorder_preview(
                int($form->{playlist_id}), $form,
            );
        };
        $error = $@;
        $error =~ s/\s+/ /g if $error;
        $log->warn("Could not start web preview: $error") if $error;
    } elsif ($params->{job_id}) {
        $job = Plugins::BlissEmAll::Jobs::get($params->{job_id});
        $error = 'Preview job is no longer available' unless $job;
    }

    $params->{blissemall_playlists} = $playlists;
    $params->{blissemall_form} = $form;
    $params->{blissemall_defaults} = $defaults;
    $params->{blissemall_capability} = $capability;
    $params->{blissemall_job} = _result_view($job) if $job;
    $params->{blissemall_error} = $error if $error;
    return Slim::Web::HTTP::filltemplatefile($page, $params);
}

1;
