package Plugins::BetterCallBliss::Settings;

use strict;
use base qw(Slim::Web::Settings);
use File::Basename qw(dirname);
use Slim::Utils::Prefs;
use Slim::Utils::PluginManager;
use Slim::Utils::Strings qw(string);
use Plugins::BetterCallBliss::BlissCompatibility;
use Plugins::BetterCallBliss::Defaults qw(
    ensure_preference_defaults
    ensure_guidance_provider_state
    preference_names
);
use Plugins::BetterCallBliss::GuidanceProviderDiscovery;
use Plugins::BetterCallBliss::GuidanceProviderPolicy;

# Vendored from lms-bliss-guidance-host so the release stays self-contained.
use lib dirname(__FILE__);
use Plugins::BlissGuidance::SettingsModel;
use Plugins::BlissGuidance::Policy;

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
        route_direct_caution
        route_min_intermediates
        route_max_intermediates
        route_exact_intermediates
        report_retention_days
        semantic_cache_days
        semantic_stale_days
        lastfm_track_guidance_percent
        lastfm_artist_guidance_percent
        lastfm_artist_mode
        listenbrainz_enabled
    ));
}

sub beforeRender {
    my ($class, $params) = @_;
    ensure_preference_defaults($prefs);
    ensure_guidance_provider_state($prefs);
    $params->{prefs} ||= {};
    for my $name (preference_names()) {
        $params->{prefs}->{$name} = $prefs->get($name);
    }
    $params->{lastmix_available} = Slim::Utils::PluginManager->isEnabled(
        'Plugins::LastMix::Plugin'
    ) ? 1 : 0;
    $params->{bliss_compatibility} =
        Plugins::BetterCallBliss::BlissCompatibility::snapshot();
    my $guidance_providers = ref($params->{bliss_compatibility}->{guidance_providers}) eq 'HASH'
        ? $params->{bliss_compatibility}->{guidance_providers} : {};
    my $lastfm = ref($guidance_providers->{lastfm}) eq 'HASH'
        ? $guidance_providers->{lastfm} : {};
    my $policies = ref($lastfm->{policies}) eq 'HASH'
        ? $lastfm->{policies} : {};
    my %artist_policies = map { $_ => 1 }
        @{ref($policies->{lastfm_artist}) eq 'ARRAY'
            ? $policies->{lastfm_artist} : []};
    $params->{lastfm_guidance_available} = $lastfm->{available} ? 1 : 0;
    $params->{lastfm_artist_target_available}
        = $artist_policies{target_share} ? 1 : 0;
    $params->{lastfm_artist_bounded_available}
        = $artist_policies{bounded_influence} ? 1 : 0;
    $params->{guidance_provider_sections} = _guidance_provider_sections(
        $params->{bliss_compatibility}->{discovered_guidance_providers},
    );
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
    _apply_guidance_provider_settings($params);
    _clamp($params, 'pref_restart_count', 10, 500);
    _clamp($params, 'pref_variation_percent', 0, 100);
    _clamp($params, 'pref_auto_bridge_budget', 0, 100);
    _clamp($params, 'pref_auto_trigger_percent', 0, 100);
    _clamp($params, 'pref_route_min_intermediates', 0, 8);
    _clamp($params, 'pref_route_max_intermediates', 0, 8);
    _clamp($params, 'pref_route_exact_intermediates', 0, 8);
    if (defined $params->{pref_route_min_intermediates}
        && defined $params->{pref_route_max_intermediates}
        && $params->{pref_route_min_intermediates}
            > $params->{pref_route_max_intermediates}) {
        $params->{pref_route_min_intermediates}
            = $params->{pref_route_max_intermediates};
    }
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
    if (defined $params->{pref_route_direct_caution}
        && $params->{pref_route_direct_caution} ne 'normal'
        && $params->{pref_route_direct_caution} ne 'cautious') {
        $params->{pref_route_direct_caution} = 'cautious';
    }
    _clamp($params, 'pref_report_retention_days', 1, 3650);
    _clamp($params, 'pref_semantic_cache_days', 1, 365);
    _clamp($params, 'pref_semantic_stale_days', 1, 3650);
    _clamp($params, 'pref_lastfm_track_guidance_percent', 0, 100);
    _clamp($params, 'pref_lastfm_artist_guidance_percent', 0, 100);
    if (defined $params->{pref_lastfm_artist_mode}
        && $params->{pref_lastfm_artist_mode} ne 'target_share'
        && $params->{pref_lastfm_artist_mode} ne 'bounded_influence') {
        $params->{pref_lastfm_artist_mode} = 'target_share';
    }
    if (defined $params->{pref_semantic_cache_days}
        && defined $params->{pref_semantic_stale_days}
        && $params->{pref_semantic_stale_days} < $params->{pref_semantic_cache_days}) {
        $params->{pref_semantic_stale_days} = $params->{pref_semantic_cache_days};
    }
    return $class->SUPER::handler($client, $params);
}

sub _guidance_provider_sections {
    my $providers = shift;
    $providers = [] unless ref($providers) eq 'ARRAY';
    return Plugins::BlissGuidance::SettingsModel::provider_sections(
        { providers => $providers },
        $prefs->get('guidance_provider_state'),
        {
            source_labels => {
                host_override => 'Better Call Bliss setting',
                provider_default => 'Provider setting',
                factory_default => 'Provider factory default',
                job_override => 'Job setting',
            },
            field_names => {
                enabled => \&_provider_enable_field,
                control => \&_provider_field,
                inherit => \&_provider_inherit_field,
                dirty => \&_provider_dirty_field,
            },
            origin_label_token => \&_origin_label_token,
            ui_labels => {
                available => string('PLUGIN_BETTERCALLBLISS_GUIDANCE_PROVIDER_AVAILABLE'),
                unavailable => sub {
                    return string('PLUGIN_BETTERCALLBLISS_GUIDANCE_PROVIDER_UNAVAILABLE', $_[0]);
                },
                settings => sub {
                    return string('PLUGIN_BETTERCALLBLISS_GUIDANCE_PROVIDER_SETTINGS', $_[0]);
                },
                enabled => string('PLUGIN_BETTERCALLBLISS_GUIDANCE_PROVIDER_ENABLED'),
                enabled_desc => string('PLUGIN_BETTERCALLBLISS_GUIDANCE_PROVIDER_ENABLED_DESC'),
                origin_prefix => string('PLUGIN_BETTERCALLBLISS_GUIDANCE_PROVIDER_ORIGIN'),
                host_origin => string('PLUGIN_BETTERCALLBLISS_GUIDANCE_PROVIDER_ORIGIN_HOST'),
                origin_pending => string('PLUGIN_BETTERCALLBLISS_GUIDANCE_PROVIDER_ORIGIN_PENDING'),
                reset => string('PLUGIN_BETTERCALLBLISS_GUIDANCE_PROVIDER_RESET'),
            },
        },
    );
}

sub _apply_guidance_provider_settings {
    my $params = shift;
    return unless $params->{saveSettings};
    my $discovery = Plugins::BetterCallBliss::GuidanceProviderDiscovery::discover();
    my $all_state = $prefs->get('guidance_provider_state');
    for my $provider (@{$discovery->{providers} || []}) {
        next unless $provider->{provider_id};
        my $id = $provider->{provider_id};
        my $state = Plugins::BetterCallBliss::GuidanceProviderPolicy::host_state(
            $all_state, $id,
        );
        my $changed = 0;
        my $enable_field = _provider_enable_field($id);
        if ($provider->{available}) {
            $state->{enabled} = exists $params->{$enable_field} ? 1 : 0;
            $changed = 1;
        }
        my $current = Plugins::BetterCallBliss::GuidanceProviderPolicy::resolve(
            $provider, $state, {},
        );
        for my $control (@{$provider->{descriptor}->{controls} || []}) {
            next unless $control->{host_overridable};
            my $key = $control->{key};
            my $field = _provider_field($id, $key);
            my $inherit_field = _provider_inherit_field($id, $key);
            my $dirty_field = _provider_dirty_field($id, $key);
            if ($params->{$inherit_field}) {
                delete $state->{overrides}->{$key};
                $changed = 1;
            } elsif (exists $params->{$field}
                && (!exists $params->{$dirty_field} || $params->{$dirty_field}
                    || Plugins::BlissGuidance::Policy::submitted_value_differs_from_effective(
                        $current->{effective}->{$key}, $params->{$field},
                    ))) {
                $state->{overrides}->{$key} = $params->{$field};
                $changed = 1;
            }
        }
        next unless $changed;
        my $resolved = Plugins::BetterCallBliss::GuidanceProviderPolicy::resolve(
            $provider, $state, {},
        );
        next unless $resolved->{valid};
        $all_state = Plugins::BetterCallBliss::GuidanceProviderPolicy::replace_host_state(
            $all_state, $id, $state,
        );
    }
    $prefs->set('guidance_provider_state', $all_state)
        if ref($all_state) eq 'HASH';
}

sub _provider_enable_field {
    return 'pref_guidance_provider_' . $_[0] . '_enabled';
}

sub _provider_field {
    return 'pref_guidance_provider_' . $_[0] . '_' . $_[1];
}

sub _provider_inherit_field {
    return 'inherit_guidance_provider_' . $_[0] . '_' . $_[1];
}

sub _provider_dirty_field {
    return 'dirty_guidance_provider_' . $_[0] . '_' . $_[1];
}

sub _origin_label_token {
    my $origin = shift || '';
    return {
        host_override    => 'PLUGIN_BETTERCALLBLISS_GUIDANCE_PROVIDER_ORIGIN_HOST',
        provider_default => 'PLUGIN_BETTERCALLBLISS_GUIDANCE_PROVIDER_ORIGIN_PROVIDER',
        factory_default  => 'PLUGIN_BETTERCALLBLISS_GUIDANCE_PROVIDER_ORIGIN_FACTORY',
        job_override     => 'PLUGIN_BETTERCALLBLISS_GUIDANCE_PROVIDER_ORIGIN_JOB',
    }->{$origin} || 'PLUGIN_BETTERCALLBLISS_GUIDANCE_PROVIDER_ORIGIN_FACTORY';
}

1;
