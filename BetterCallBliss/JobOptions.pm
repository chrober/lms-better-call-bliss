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
    return {
        ordering_policy => 'optimize_order',
        extension_mode => 'none',
        algorithm => 'adaptive',
        seed_limit => int($capability->{seed_limit}),
        learned_percent => int($capability->{learned_percent}),
        artist_window => int($capability->{artist_window}),
        album_window => int($capability->{album_window}),
        track_window => int($capability->{track_window}),
        restart_count => int($plugin_prefs->get('restart_count') || 50),
        max_added_tracks => int($bridge_budget),
        trigger_percent => int($trigger_percent),
        additional_track_count => 1,
        target_track_count => 25,
        output_mode => 'create_copy',
        output_name => '',
        output_name_generated => 0,
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
    die "Extension mode must be Reorder only, Extend automatically, Add exactly N tracks, or Grow from these seeds"
        unless $options->{extension_mode} eq 'none'
            || $options->{extension_mode} eq 'automatic'
            || $options->{extension_mode} eq 'exact_count'
            || $options->{extension_mode} eq 'seed_growth';
    $options->{ordering_policy} = 'optimize_order'
        if $options->{extension_mode} eq 'seed_growth';

    $options->{algorithm} = $input->{algorithm}
        if defined $input->{algorithm};
    die "Only Adaptive scoring is connected"
        unless $options->{algorithm} eq 'adaptive';

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
    $options->{max_added_tracks} = _integer(
        $input, 'max_added_tracks', 0, 100, $options->{max_added_tracks},
    );
    $options->{trigger_percent} = _integer(
        $input, 'trigger_percent', 0, 100, $options->{trigger_percent},
    );
    $options->{additional_track_count} = _integer(
        $input, 'additional_track_count', 1, 100,
        $options->{additional_track_count},
    );
    $options->{target_track_count} = _integer(
        $input, 'target_track_count', 3, 500,
        $options->{target_track_count},
    );

    die "Preserve source order requires an addition mode with a non-zero target"
        if $options->{ordering_policy} eq 'preserve_order'
            && ($options->{extension_mode} eq 'none'
                || ($options->{extension_mode} eq 'automatic'
                    && $options->{max_added_tracks} == 0));
    $options->{output_mode} = $input->{output_mode}
        if defined $input->{output_mode};
    die "Output mode must be Create optimized copy or Overwrite source"
        unless $options->{output_mode} eq 'create_copy'
            || $options->{output_mode} eq 'overwrite_source';

    if (defined $input->{output_name}) {
        my $name = $input->{output_name};
        $name =~ s/[\x00-\x1f]+/ /g;
        $name =~ s/^\s+|\s+$//g;
        die "Output playlist name is too long" if length($name) > 255;
        $options->{output_name} = $name;
    }
    $options->{output_name_generated} =
        $input->{output_name_generated} ? 1 : 0;

    return $options;
}

1;
