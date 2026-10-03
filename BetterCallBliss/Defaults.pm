package Plugins::BetterCallBliss::Defaults;

use strict;
use Exporter qw(import);

our @EXPORT_OK = qw(
    ensure_preference_defaults
    ensure_guidance_provider_state
    preference_defaults
    preference_names
);

my %PREFERENCE_DEFAULTS = (
    preference_defaults_version => 3,
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
    guidance_provider_state => { schema_version => 1, providers => {} },
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
    guidance_provider_state
    listenbrainz_enabled
);

sub preference_defaults {
    return { %PREFERENCE_DEFAULTS };
}

sub ensure_guidance_provider_state {
    my $prefs = shift;
    return unless $prefs;
    my $state = $prefs->get('guidance_provider_state');
    return if ref($state) eq 'HASH';

    # Preserve the formerly Better Call Bliss-owned local-signal values as
    # disabled sparse overrides. They cannot change selection until the new
    # independently installed provider is explicitly enabled in this host.
    my %overrides;
    for my $key (qw(
        last_played_influence
        last_played_horizon_days
        library_age_influence
        library_age_horizon_days
    )) {
        my $value = $prefs->get($key);
        $overrides{$key} = $value if defined $value && $value ne '';
    }
    $prefs->set('guidance_provider_state', {
        schema_version => 1,
        providers => {
            'library-signals' => { enabled => 0, overrides => \%overrides },
        },
    });
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
