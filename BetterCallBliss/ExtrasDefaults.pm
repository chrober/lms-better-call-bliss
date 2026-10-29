package Plugins::BetterCallBliss::ExtrasDefaults;

use strict;
use warnings;
use Plugins::BetterCallBliss::GuidanceProviderPolicy;
my @OPTION_KEYS = qw(
    ordering_policy extension_mode addition_purpose addition_amount_mode
    algorithm seed_limit learned_percent artist_window artist_repeat_mode
    album_window track_window restart_count variation_percent max_added_tracks
    trigger_percent gap_context_mode tracks_per_gap additional_track_count
    bridge_target_track_count target_track_count
);

sub expand_weights {
    my ($weights) = @_;
    die 'Invalid static scoring weights' unless ref($weights) eq 'HASH';
    for my $name (qw(tempo timbre loudness chroma)) {
        die "Invalid static scoring weight: $name"
            unless defined $weights->{$name} && $weights->{$name} =~ /^\d+$/
                && $weights->{$name} <= 100;
    }
    my $total = $weights->{tempo} + $weights->{timbre}
        + $weights->{loudness} + $weights->{chroma};
    die 'Static scoring weights cannot all be zero' unless $total;
    return [
        $weights->{tempo} / $total * 100 / 4,
        ($weights->{timbre} / $total * 100 / 30) x 7,
        ($weights->{loudness} / $total * 100 / 9) x 2,
        ($weights->{chroma} / $total * 100 / 57) x 13,
    ];
}

sub capture {
    my ($form, $capability) = @_;
    # Validate the reusable values through the same rules as a preview. A
    # missing matrix affects execution, not the user's saved desired blend.
    my %validation_capability = (
        seed_limit => 3, learned_percent => 0, artist_window => 0,
        album_window => 0, track_window => 0, %$capability,
        matrix_available => 1,
    );
    my %validation_input = (%$form, output_mode => 'create_copy');
    require Plugins::BetterCallBliss::JobOptions;
    Plugins::BetterCallBliss::JobOptions::normalize(
        \%validation_capability, \%validation_input,
    );
    my %options;
    for my $key (@OPTION_KEYS) {
        $options{$key} = $form->{$key} if exists $form->{$key};
    }
    my %providers;
    for my $provider (@{$capability->{discovered_guidance_providers} || []}) {
        my $id = $provider->{provider_id} || next;
        next unless $provider->{available};
        my %overrides;
        my $effective = $provider->{host_policy}->{effective} || {};
        for my $control (@{$provider->{descriptor}->{controls} || []}) {
            next unless $control->{host_overridable};
            my $key = $control->{key};
            my $field = 'guidance_provider_' . $id . '_' . $key;
            if ($control->{type} eq 'boolean' && exists $form->{$field . '_present'}) {
                $overrides{$key} = $form->{$field} ? 1 : 0;
            } elsif (exists $form->{$field}) {
                $overrides{$key} = $form->{$field};
            } elsif (exists $effective->{$key}) {
                $overrides{$key} = $effective->{$key};
            }
        }
        my $enabled_field = 'guidance_provider_' . $id . '_enabled';
        my $enabled = exists $form->{$enabled_field . '_present'}
            ? ($form->{$enabled_field} ? 1 : 0)
            : ($provider->{host_policy}->{enabled} ? 1 : 0);
        my $resolved = Plugins::BetterCallBliss::GuidanceProviderPolicy::resolve(
            $provider, $provider->{host_state}, {enabled => $enabled, overrides => \%overrides},
        );
        die "Guidance provider '$id' policy is invalid: $resolved->{diagnostic}"
            unless $resolved->{valid};
        $providers{$id} = { enabled => $enabled, overrides => \%overrides };
    }
    my %weights = %{$capability->{static_weight_sliders} || {}};
    for my $name (qw(tempo timbre loudness chroma)) {
        my $field = 'extras_weight_' . $name;
        $weights{$name} = $form->{$field} if exists $form->{$field};
    }
    expand_weights(\%weights) if keys %weights;
    return {
        schema_version => 1,
        options => \%options,
        static_weights => \%weights,
        providers => \%providers,
    };
}

sub apply {
    my ($profile, $defaults, $capability) = @_;
    my %result = %{$defaults || {}};
    my @warnings;
    unless (ref($profile) eq 'HASH' && ($profile->{schema_version} || 0) == 1) {
        return (\%result, ['Saved Extras defaults are unavailable or unsupported.']);
    }
    my $options = ref($profile->{options}) eq 'HASH' ? $profile->{options} : {};
    my @new_options = grep { !exists $options->{$_} && exists $defaults->{$_} } @OPTION_KEYS;
    if (@new_options) {
        s/_/ /g for @new_options;
        push @warnings, 'These preview settings use current plugin defaults: ' . join(', ', @new_options) . '.';
    }
    for my $key (@OPTION_KEYS) {
        $result{$key} = $options->{$key} if exists $options->{$key};
    }
    my %validation_capability = (
        seed_limit => 3, learned_percent => 0, artist_window => 0,
        album_window => 0, track_window => 0, %$capability,
        matrix_available => 1, discovered_guidance_providers => [],
    );
    my %validation_input = (%result, output_mode => 'create_copy');
    delete @validation_input{grep { /^extras_weight_/ } keys %validation_input};
    require Plugins::BetterCallBliss::JobOptions;
    unless (eval { Plugins::BetterCallBliss::JobOptions::normalize(
        \%validation_capability, \%validation_input); 1 }) {
        for my $key (@OPTION_KEYS) {
            if (exists $defaults->{$key}) { $result{$key} = $defaults->{$key}; }
            else { delete $result{$key}; }
        }
        push @warnings, 'Saved preview settings are no longer valid; current plugin defaults will be used.';
    }
    if (ref($profile->{static_weights}) eq 'HASH'
        && eval { expand_weights($profile->{static_weights}); 1 }) {
        $result{'extras_weight_' . $_} = $profile->{static_weights}->{$_}
            for qw(tempo timbre loudness chroma);
    } elsif (ref($profile->{static_weights}) eq 'HASH'
        && keys %{$profile->{static_weights}}) {
        push @warnings, 'Saved static scoring weights are invalid; current plugin weights will be used.';
    }
    my $stored = ref($profile->{providers}) eq 'HASH' ? $profile->{providers} : {};
    my %seen;
    for my $provider (@{$capability->{discovered_guidance_providers} || []}) {
        my $id = $provider->{provider_id} || next;
        $seen{$id} = 1;
        my $saved = $stored->{$id};
        unless (ref($saved) eq 'HASH') {
            push @warnings, "Provider $id uses current plugin defaults; it was not in the saved set.";
            next;
        }
        if (!$provider->{available}) {
            push @warnings, "Provider $id is unavailable; its saved settings are retained.";
            next;
        }
        $result{'guidance_provider_' . $id . '_enabled'} = $saved->{enabled} ? 1 : 0;
        $result{'guidance_provider_' . $id . '_enabled_present'} = 1;
        my $values = ref($saved->{overrides}) eq 'HASH' ? $saved->{overrides} : {};
        my %known;
        for my $control (@{$provider->{descriptor}->{controls} || []}) {
            next unless $control->{host_overridable};
            my $key = $control->{key};
            $known{$key} = 1;
            unless (exists $values->{$key}) {
                push @warnings, "New $id setting $key uses its current plugin default.";
                next;
            }
            if (Plugins::BetterCallBliss::GuidanceProviderPolicy::_validate_value($control, $values->{$key})) {
                push @warnings, "Saved $id setting $key is no longer valid; the plugin default will be used.";
                next;
            }
            my $field = 'guidance_provider_' . $id . '_' . $key;
            $result{$field} = $values->{$key};
            $result{$field . '_present'} = 1 if $control->{type} eq 'boolean';
        }
        push @warnings, "Some saved $id settings are no longer available."
            if grep { !$known{$_} } keys %$values;
    }
    push @warnings, "Saved provider $_ is not installed; its settings are retained."
        for grep { !$seen{$_} } keys %$stored;
    return (\%result, \@warnings);
}

sub apply_plugin_defaults {
    my ($form, $defaults) = @_;
    my %result = %{$form || {}};
    for my $key (@OPTION_KEYS) {
        if (exists $defaults->{$key}) { $result{$key} = $defaults->{$key}; }
        else { delete $result{$key}; }
    }
    delete @result{grep { /^guidance_provider_/ || /^extras_weight_/ } keys %result};
    return \%result;
}

sub prepare_editor {
    my ($prefs, $params, $form, $defaults, $capability) = @_;
    my $profile = $prefs->get('extras_defaults');
    my $has_profile = ref($profile) eq 'HASH' && ($profile->{schema_version} || 0) == 1;
    my $source = $prefs->get('extras_defaults_source') || 'plugin';
    $source = 'plugin' unless $has_profile && $source eq 'extras';
    my $view = { source => $source, has_profile => $has_profile, warnings => [] };
    return ($form, $view) if ($form->{source_mode} || '') eq 'route_to_track'
        || $params->{quick_route};

    if ($params->{select_extras_defaults}) {
        my $chosen = $params->{extras_defaults_source} || 'plugin';
        die 'Saved Extras defaults are not available' if $chosen eq 'extras' && !$has_profile;
        die 'Unknown Extras defaults selection' unless $chosen eq 'plugin' || $chosen eq 'extras';
        $prefs->set('extras_defaults_source', $chosen);
        $view->{source} = $chosen;
    } elsif ($params->{save_extras_defaults}) {
        my %save_form = %$form;
        if (!$capability->{matrix_available} && $source eq 'extras'
            && ref($profile->{options}) eq 'HASH'
            && exists $profile->{options}->{learned_percent}) {
            $save_form{learned_percent} = $profile->{options}->{learned_percent};
        } elsif (!$capability->{matrix_available}
            && defined $capability->{configured_learned_percent}) {
            $save_form{learned_percent} = $capability->{configured_learned_percent};
        }
        my $new = capture(\%save_form, $capability);
        # Retain settings for providers and controls temporarily unavailable.
        if ($has_profile && ref($profile->{providers}) eq 'HASH') {
            for my $id (keys %{$profile->{providers}}) {
                my $old = $profile->{providers}->{$id};
                next unless ref($old) eq 'HASH';
                if (!exists $new->{providers}->{$id}) {
                    $new->{providers}->{$id} = $old;
                } elsif (ref($old->{overrides}) eq 'HASH') {
                    for my $key (keys %{$old->{overrides}}) {
                        $new->{providers}->{$id}->{overrides}->{$key} = $old->{overrides}->{$key}
                            unless exists $new->{providers}->{$id}->{overrides}->{$key};
                    }
                }
            }
        }
        $prefs->set('extras_defaults', $new);
        $prefs->set('extras_defaults_source', 'extras');
        ($form, my $warnings) = apply($new, $form, $capability);
        $view = { source => 'extras', has_profile => 1, warnings => [],
            status => 'Extras defaults saved.' };
        $view->{warnings} = $warnings;
    } elsif ($params->{load_extras_defaults}) {
        my $chosen = $params->{extras_defaults_source} || 'plugin';
        die 'Saved Extras defaults are not available' if $chosen eq 'extras' && !$has_profile;
        die 'Unknown Extras defaults selection' unless $chosen eq 'plugin' || $chosen eq 'extras';
        $form = apply_plugin_defaults($form, $defaults);
        if ($chosen eq 'extras') {
            ($form, $view->{warnings}) = apply($profile, $form, $capability);
        }
        $prefs->set('extras_defaults_source', $chosen);
        $view->{source} = $chosen;
        $view->{status} = 'Selected defaults loaded.';
    } elsif (!$params->{job_id} && !$params->{run_preview}
        && !$params->{cancel_job} && !$params->{create_copy}
        && !$params->{overwrite_source} && !$params->{send_to_queue}
        && $source eq 'extras') {
        ($form, $view->{warnings}) = apply($profile, $form, $capability);
    }
    return ($form, $view);
}

1;
