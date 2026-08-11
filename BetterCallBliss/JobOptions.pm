package Plugins::BetterCallBliss::JobOptions;

use strict;
use Slim::Utils::Prefs;

my $plugin_prefs = preferences('plugin.bettercallbliss');

sub defaults {
    my $capability = shift;
    my $bridge_budget = $plugin_prefs->get('auto_bridge_budget');
    $bridge_budget = 8 unless defined $bridge_budget;
    my $trigger_percent = $plugin_prefs->get('auto_trigger_percent');
    $trigger_percent = 70 unless defined $trigger_percent;
    my $lastfm_track_guidance =
        $plugin_prefs->get('lastfm_track_guidance_percent');
    $lastfm_track_guidance = 75 unless defined $lastfm_track_guidance;
    my $lastfm_artist_guidance =
        $plugin_prefs->get('lastfm_artist_guidance_percent');
    $lastfm_artist_guidance = 75 unless defined $lastfm_artist_guidance;
    my $default_algorithm = $capability->{algorithm} || 'adaptive';
    $default_algorithm = 'adaptive' if $default_algorithm eq 'forest';
    my $variation_percent = $plugin_prefs->get('variation_percent');
    $variation_percent = 25 unless defined $variation_percent;
    my $route_length_policy = $plugin_prefs->get('route_length_policy') || 'automatic';
    $route_length_policy = 'automatic'
        unless $route_length_policy eq 'automatic' || $route_length_policy eq 'exact';
    return {
        ordering_policy => 'optimize_order',
        extension_mode => 'none',
        addition_purpose => 'none',
        addition_amount_mode => 'exact_count',
        algorithm => $default_algorithm,
        seed_limit => int($capability->{seed_limit}),
        learned_percent => int($capability->{learned_percent}),
        artist_window => int($capability->{artist_window}),
        album_window => int($capability->{album_window}),
        track_window => int($capability->{track_window}),
        restart_count => int($plugin_prefs->get('restart_count') || 50),
        variation_percent => int($variation_percent),
        generation_seed => '',
        generation_seed_supplied => 0,
        lastfm_enabled => $plugin_prefs->get('lastfm_enabled') ? 1 : 0,
        lastfm_track_guidance_percent => int($lastfm_track_guidance),
        lastfm_artist_guidance_percent => int($lastfm_artist_guidance),
        max_added_tracks => int($bridge_budget),
        trigger_percent => int($trigger_percent),
        route_length_policy => $route_length_policy,
        route_max_intermediates => int(
            $plugin_prefs->get('route_max_intermediates') // 4,
        ),
        route_exact_intermediates => int(
            $plugin_prefs->get('route_exact_intermediates') // 2,
        ),
        additional_track_count => 1,
        bridge_target_track_count => 25,
        target_track_count => 25,
        output_mode => 'create_copy',
        output_name => '',
        output_name_generated => 0,
        queue_player_id => '',
        queue_action => 'replace',
        source_queue_scope => 'full',
        queue_start_playback => 0,
    };
}

sub _integer {
    my ($input, $name, $minimum, $maximum, $fallback) = @_;
    return $fallback unless defined $input->{$name};
    my $raw = $input->{$name};
    die "$name must be an integer" unless "$raw" =~ /^\d+$/;
    my $value = int($raw);
    die "$name must be between $minimum and $maximum"
        if $value < $minimum || $value > $maximum;
    return $value;
}

sub normalize {
    my ($capability, $input) = @_;
    $input ||= {};
    my $options = defaults($capability);

    $options->{ordering_policy} = $input->{ordering_policy}
        if defined $input->{ordering_policy};
    die "Source-track order must be Optimize or Preserve"
        unless $options->{ordering_policy} eq 'optimize_order'
            || $options->{ordering_policy} eq 'preserve_order';

    $options->{extension_mode} = $input->{extension_mode}
        if defined $input->{extension_mode};
    die "Extension mode must be Reorder only, Improve difficult transitions, Add exactly N tracks, Reach final track count, Double track count, destination route, or the internal fixed-source extension mode"
        unless $options->{extension_mode} eq 'none'
            || $options->{extension_mode} eq 'automatic'
            || $options->{extension_mode} eq 'exact_count'
            || $options->{extension_mode} eq 'target_count'
            || $options->{extension_mode} eq 'double_count'
            || $options->{extension_mode} eq 'destination_route'
            || $options->{extension_mode} eq 'fixed_source_extension';

    my $destination_route = $options->{extension_mode} eq 'destination_route';
    my $addition_purpose_provided = defined $input->{addition_purpose};
    $options->{addition_purpose} = $input->{addition_purpose}
        if $addition_purpose_provided;
    my $legacy_fixed_source_extension_purpose = 0;
    if ($options->{addition_purpose} eq 'fixed_source_extension') {
        $legacy_fixed_source_extension_purpose = 1;
        $options->{addition_purpose} = 'extend_playlist';
        $options->{addition_amount_mode} = 'target_count';
    }
    die "Additional tracks must be No additions, Improve difficult transitions, or Extend playlist"
        unless $options->{addition_purpose} eq 'none'
            || $options->{addition_purpose} eq 'automatic'
            || $options->{addition_purpose} eq 'extend_playlist';
    $options->{addition_amount_mode} = $input->{addition_amount_mode}
        if defined $input->{addition_amount_mode};
    die "Chosen amount must be Add exactly N tracks, Reach final track count, or Double track count"
        unless $options->{addition_amount_mode} eq 'exact_count'
            || $options->{addition_amount_mode} eq 'target_count'
            || $options->{addition_amount_mode} eq 'double_count';
    if (!defined $input->{addition_purpose}) {
        if ($options->{extension_mode} eq 'exact_count'
            || $options->{extension_mode} eq 'target_count'
            || $options->{extension_mode} eq 'double_count') {
            $options->{addition_purpose} = 'none';
            $options->{addition_amount_mode} = $options->{extension_mode};
        } elsif ($options->{extension_mode} eq 'automatic') {
            $options->{addition_purpose} = $options->{extension_mode};
        } elsif ($options->{extension_mode} eq 'fixed_source_extension') {
            $legacy_fixed_source_extension_purpose = 1;
            $options->{addition_purpose} = 'extend_playlist';
            $options->{addition_amount_mode} = 'target_count';
        } else {
            $options->{addition_purpose} = 'none';
        }
    }
    if ($addition_purpose_provided && !$destination_route) {
        if ($options->{addition_purpose} eq 'extend_playlist') {
            $options->{extension_mode} = 'fixed_source_extension';
        } elsif ($options->{addition_purpose} eq 'automatic'
            || $options->{addition_purpose} eq 'none') {
            $options->{extension_mode} = $options->{addition_purpose};
        }
    }

    $options->{algorithm} = $input->{algorithm}
        if defined $input->{algorithm};
    die "Mixing strategy must be Adaptive or Static; Extended Isolation Forest is not connected yet"
        unless $options->{algorithm} eq 'adaptive'
            || $options->{algorithm} eq 'static';

    $options->{seed_limit} = _integer(
        $input, 'seed_limit', 1, 50, $options->{seed_limit},
    );
    $options->{learned_percent} = _integer(
        $input, 'learned_percent', 0, 100, $options->{learned_percent},
    );
    $options->{artist_window} = _integer(
        $input, 'artist_window', 0, 10000, $options->{artist_window},
    );
    $options->{album_window} = _integer(
        $input, 'album_window', 0, 10000, $options->{album_window},
    );
    $options->{track_window} = _integer(
        $input, 'track_window', 0, 10000, $options->{track_window},
    );
    $options->{restart_count} = _integer(
        $input, 'restart_count', 0, 500, $options->{restart_count},
    );
    $options->{variation_percent} = _integer(
        $input, 'variation_percent', 0, 100, $options->{variation_percent},
    );
    if (defined $input->{generation_seed} && length "$input->{generation_seed}") {
        $options->{generation_seed} = _integer(
            $input, 'generation_seed', 0, 4294967295, 0,
        );
        $options->{generation_seed_supplied} = 1;
    } else {
        $options->{generation_seed} = undef;
        $options->{generation_seed_supplied} = 0;
    }
    $options->{lastfm_enabled} = $input->{lastfm_enabled} ? 1 : 0
        if exists $input->{lastfm_enabled};
    $options->{lastfm_track_guidance_percent} = _integer(
        $input, 'lastfm_track_guidance_percent', 0, 100,
        $options->{lastfm_track_guidance_percent},
    );
    $options->{lastfm_artist_guidance_percent} = _integer(
        $input, 'lastfm_artist_guidance_percent', 0, 100,
        $options->{lastfm_artist_guidance_percent},
    );
    $options->{max_added_tracks} = _integer(
        $input, 'max_added_tracks', 0, 100, $options->{max_added_tracks},
    );
    $options->{trigger_percent} = _integer(
        $input, 'trigger_percent', 0, 100, $options->{trigger_percent},
    );
    $options->{route_length_policy} = $input->{route_length_policy}
        if defined $input->{route_length_policy};
    die "Bliss me there route length must be Automatic or Exact"
        unless $options->{route_length_policy} eq 'automatic'
            || $options->{route_length_policy} eq 'exact';
    $options->{route_max_intermediates} = _integer(
        $input, 'route_max_intermediates', 0, 8,
        $options->{route_max_intermediates},
    );
    $options->{route_exact_intermediates} = _integer(
        $input, 'route_exact_intermediates', 0, 8,
        $options->{route_exact_intermediates},
    );

    $options->{additional_track_count} = _integer(
        $input, 'additional_track_count', 1, 100,
        $options->{additional_track_count},
    );
    $options->{bridge_target_track_count} = _integer(
        $input, 'bridge_target_track_count', 3, 500,
        $options->{bridge_target_track_count},
    );
    $options->{target_track_count} = _integer(
        $input, 'target_track_count', 3, 500,
        $options->{target_track_count},
    );
    if ($legacy_fixed_source_extension_purpose) {
        $options->{bridge_target_track_count} = $options->{target_track_count};
        $options->{addition_purpose} = 'extend_playlist';
        $options->{addition_amount_mode} = 'target_count';
        $options->{extension_mode} = 'fixed_source_extension';
    }

    die "Preserve source order requires an addition mode with a non-zero target"
        if $options->{ordering_policy} eq 'preserve_order'
            && $options->{extension_mode} ne 'destination_route'
            && ($options->{extension_mode} eq 'none'
                || ($options->{extension_mode} eq 'automatic'
                    && $options->{max_added_tracks} == 0));
    $options->{output_mode} = $input->{output_mode}
        if defined $input->{output_mode};
    die "Output mode must be Create optimized copy, Overwrite source, or Send to player queue"
        unless $options->{output_mode} eq 'create_copy'
            || $options->{output_mode} eq 'overwrite_source'
            || $options->{output_mode} eq 'player_queue';

    $options->{queue_player_id} = $input->{queue_player_id}
        if defined $input->{queue_player_id};
    $options->{queue_player_id} =~ s/^\s+|\s+$//g;
    $options->{queue_action} = $input->{queue_action}
        if defined $input->{queue_action};
    die "Queue action must be Replace queue, Replace upcoming tracks, Append to queue, or Play next"
        unless $options->{queue_action} eq 'replace'
            || $options->{queue_action} eq 'replace_upcoming'
            || $options->{queue_action} eq 'append'
            || $options->{queue_action} eq 'play_next';
    $options->{queue_start_playback} = $input->{queue_start_playback} ? 1 : 0
        if exists $input->{queue_start_playback};
    die "Choose a player for queue output"
        if $options->{output_mode} eq 'player_queue'
            && !length($options->{queue_player_id} || '');

    if (defined $input->{output_name}) {
        my $name = $input->{output_name};
        $name =~ s/[\x00-\x1f]+/ /g;
        $name =~ s/^\s+|\s+$//g;
        die "Output playlist name is too long" if length($name) > 255;
        $options->{output_name} = $name;
    }
    $options->{output_name_generated} =
        length($options->{output_name} || '') ? 0 : 1;

    return $options;
}

1;
