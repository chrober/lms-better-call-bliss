package Plugins::BetterCallBliss::Settings;

use strict;
use base qw(Slim::Web::Settings);
use Slim::Utils::Prefs;

my $prefs = preferences('plugin.bettercallbliss');

sub name {
    return Slim::Web::HTTP::CSRF->protectName('PLUGIN_BETTERCALLBLISS_SETTINGS');
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
        auto_bridge_budget
        auto_trigger_percent
        report_retention_days
        semantic_cache_days
        semantic_stale_days
        lastfm_enabled
        listenbrainz_enabled
    ));
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
    _clamp($params, 'pref_auto_bridge_budget', 0, 100);
    _clamp($params, 'pref_auto_trigger_percent', 0, 100);
    _clamp($params, 'pref_report_retention_days', 1, 3650);
    _clamp($params, 'pref_semantic_cache_days', 1, 365);
    _clamp($params, 'pref_semantic_stale_days', 1, 3650);
    if (defined $params->{pref_semantic_cache_days}
        && defined $params->{pref_semantic_stale_days}
        && $params->{pref_semantic_stale_days} < $params->{pref_semantic_cache_days}) {
        $params->{pref_semantic_stale_days} = $params->{pref_semantic_cache_days};
    }
    return $class->SUPER::handler($client, $params);
}

1;
