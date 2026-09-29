package Plugins::BetterCallBliss::Settings;

use strict;
use base qw(Slim::Web::Settings);
use Slim::Utils::Prefs;
use Slim::Utils::PluginManager;
use Plugins::BetterCallBliss::BlissCompatibility;
use Plugins::BetterCallBliss::Defaults qw(
    ensure_preference_defaults
    ensure_guidance_provider_state
    preference_names
);
use Plugins::BetterCallBliss::GuidanceProviderDiscovery;
use Plugins::BetterCallBliss::GuidanceProviderPolicy;

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
    my @sections;
    for my $provider (@$providers) {
        next unless ref($provider) eq 'HASH';
        my $descriptor = ref($provider->{descriptor}) eq 'HASH'
            ? $provider->{descriptor} : {};
        my $provider_defaults = ref($provider->{defaults}) eq 'HASH'
            ? $provider->{defaults} : {};
        my $policy = ref($provider->{host_policy}) eq 'HASH'
            ? $provider->{host_policy} : {};
        my @controls;
        for my $control (@{$descriptor->{controls} || []}) {
            next unless ref($control) eq 'HASH' && $control->{key};
            push @controls, {
                %$control,
                effective => $policy->{effective}->{$control->{key}},
                origin => $policy->{origins}->{$control->{key}} || 'factory_default',
                origin_label_token => _origin_label_token(
                    $policy->{origins}->{$control->{key}} || 'factory_default',
                ),
                field_name => _provider_field($provider->{provider_id}, $control->{key}),
                inherit_field_name => _provider_inherit_field(
                    $provider->{provider_id}, $control->{key},
                ),
                dirty_field_name => _provider_dirty_field(
                    $provider->{provider_id}, $control->{key},
                ),
                inherited => exists $provider_defaults->{$control->{key}}
                    ? $provider_defaults->{$control->{key}}
                    : $control->{factory_default},
                inherited_origin_label_token => exists $provider_defaults->{$control->{key}}
                    ? 'PLUGIN_BETTERCALLBLISS_GUIDANCE_PROVIDER_ORIGIN_PROVIDER'
                    : 'PLUGIN_BETTERCALLBLISS_GUIDANCE_PROVIDER_ORIGIN_FACTORY',
                inherited_origin => exists $provider_defaults->{$control->{key}}
                    ? 'provider_default' : 'factory_default',
                render_as => $control->{render_as}
                    || ($control->{type} eq 'integer' ? 'slider' : ''),
            };
        }
        push @sections, {
            provider_id => $provider->{provider_id},
            display_name => $descriptor->{display_name} || $provider->{provider_id},
            settings_uri => $descriptor->{settings_uri} || '',
            available => $provider->{available} ? 1 : 0,
            diagnostic => $provider->{diagnostic} || '',
            enabled => $policy->{enabled} ? 1 : 0,
            policy_valid => $policy->{valid} ? 1 : 0,
            policy_diagnostic => $policy->{diagnostic} || '',
            enable_field_name => _provider_enable_field($provider->{provider_id}),
            controls => \@controls,
        };
    }
    return \@sections;
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
                && (!exists $params->{$dirty_field} || $params->{$dirty_field})) {
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
