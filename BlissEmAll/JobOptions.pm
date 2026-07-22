package Plugins::BlissEmAll::JobOptions;

use strict;
use Slim::Utils::Prefs;

my $plugin_prefs = preferences('plugin.blissemall');

sub defaults {
    my $capability = shift;
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
        output_mode => 'create_copy',
        output_name => '',
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
    die "Only Optimize order is connected"
        unless $options->{ordering_policy} eq 'optimize_order';

    $options->{extension_mode} = $input->{extension_mode}
        if defined $input->{extension_mode};
    die "Only Reorder only is connected"
        unless $options->{extension_mode} eq 'none';

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

    return $options;
}

1;
