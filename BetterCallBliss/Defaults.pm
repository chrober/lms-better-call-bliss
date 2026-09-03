package Plugins::BetterCallBliss::Defaults;

use strict;
use Exporter qw(import);

our @EXPORT_OK = qw(
    ensure_preference_defaults
    preference_defaults
    preference_names
);

my %PREFERENCE_DEFAULTS = (
    preference_defaults_version => 2,
    output_suffix => 'Optimized',
    extended_suffix => 'Extended',
    restart_count => 50,
    variation_percent => 25,
    auto_bridge_budget => 8,
    auto_trigger_percent => 70,
    route_length_policy => 'automatic',
    route_direct_caution => 'cautious',
    route_search_effort => 'fast',
    route_min_intermediates => 0,
    route_max_intermediates => 4,
    route_exact_intermediates => 2,
    report_retention_days => 30,
    semantic_cache_days => 30,
    semantic_stale_days => 90,
    lastfm_enabled => 0,
    lastfm_artist_guidance_percent => 25,
    listenbrainz_enabled => 0,
);

my %EMPTY_VALUE_IS_MISSING = map { $_ => 1 } qw(
    preference_defaults_version
    restart_count
    variation_percent
    auto_bridge_budget
    auto_trigger_percent
    route_length_policy
    route_direct_caution
    route_search_effort
    route_min_intermediates
    route_max_intermediates
    route_exact_intermediates
    report_retention_days
    semantic_cache_days
    semantic_stale_days
    lastfm_enabled
    lastfm_artist_guidance_percent
    listenbrainz_enabled
);

sub preference_defaults {
    return { %PREFERENCE_DEFAULTS };
}

sub preference_names {
    return sort keys %PREFERENCE_DEFAULTS;
}

sub ensure_preference_defaults {
    my $prefs = shift;
    return unless $prefs;

    for my $name (preference_names()) {
        my $value = $prefs->get($name);
        next if defined $value
            && (!$EMPTY_VALUE_IS_MISSING{$name} || $value ne '');
        $prefs->set($name, $PREFERENCE_DEFAULTS{$name});
    }
}

1;
