package Plugins::BetterCallBliss::Settings;

use strict;
use base qw(Slim::Web::Settings);
use Slim::Utils::Prefs;
use Slim::Utils::PluginManager;

my $prefs = preferences('plugin.bettercallbliss');

sub name {
    return Slim::Web::HTTP::CSRF->protectName('PLUGIN_BETTERCALLBLISS_NAME');
}

sub page {
    return Slim::Web::HTTP::CSRF->protectURI(
        'plugins/BetterCallBliss/settings/bettercallbliss.html'
    );
}

sub prefs {
    return ($prefs, qw(
        output_suffix
        extended_suffix
        restart_count
        variation_percent
        auto_bridge_budget
        auto_trigger_percent
        route_search_effort
        route_length_policy
        route_max_intermediates
        route_exact_intermediates
        report_retention_days
        semantic_cache_days
        semantic_stale_days
        lastfm_enabled
        lastfm_track_guidance_percent
        lastfm_artist_guidance_percent
        listenbrainz_enabled
    ));
}

sub beforeRender {
    my ($class, $params) = @_;
    $params->{lastmix_available} = Slim::Utils::PluginManager->isEnabled(
        'Plugins::LastMix::Plugin'
    ) ? 1 : 0;
}

sub _clamp {
    my ($params, $name, $minimum, $maximum) = @_;
    return unless defined $params->{$name};
    my $value = int($params->{$name});
    $value = $minimum if $value < $minimum;
    $value = $maximum if $value > $maximum;
    $params->{$name} = $value;
}

sub handler {
    my ($class, $client, $params) = @_;
    _clamp($params, 'pref_restart_count', 10, 500);
    _clamp($params, 'pref_variation_percent', 0, 100);
    _clamp($params, 'pref_auto_bridge_budget', 0, 100);
    _clamp($params, 'pref_auto_trigger_percent', 0, 100);
    _clamp($params, 'pref_route_max_intermediates', 0, 8);
    _clamp($params, 'pref_route_exact_intermediates', 0, 8);
    if (defined $params->{pref_route_length_policy}
        && $params->{pref_route_length_policy} ne 'automatic'
        && $params->{pref_route_length_policy} ne 'exact') {
        $params->{pref_route_length_policy} = 'automatic';
    }
    if (defined $params->{pref_route_search_effort}
        && $params->{pref_route_search_effort} ne 'fast'
        && $params->{pref_route_search_effort} ne 'balanced'
        && $params->{pref_route_search_effort} ne 'thorough') {
        $params->{pref_route_search_effort} = 'fast';
    }
    _clamp($params, 'pref_report_retention_days', 1, 3650);
    _clamp($params, 'pref_semantic_cache_days', 1, 365);
    _clamp($params, 'pref_semantic_stale_days', 1, 3650);
    _clamp($params, 'pref_lastfm_track_guidance_percent', 0, 100);
    _clamp($params, 'pref_lastfm_artist_guidance_percent', 0, 100);
    if (defined $params->{pref_semantic_cache_days}
        && defined $params->{pref_semantic_stale_days}
        && $params->{pref_semantic_stale_days} < $params->{pref_semantic_cache_days}) {
        $params->{pref_semantic_stale_days} = $params->{pref_semantic_cache_days};
    }
    return $class->SUPER::handler($client, $params);
}

1;
