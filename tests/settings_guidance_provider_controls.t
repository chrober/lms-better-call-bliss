use strict;
use warnings;
use Test::More;
use lib '.';

{
    package TestPrefs;
    sub new { bless { values => {} }, shift }
    sub get { $_[0]->{values}->{$_[1]} }
    sub set { $_[0]->{values}->{$_[1]} = $_[2]; return (undef, 1) }

    package Slim::Utils::Prefs;
    our $PREFS = TestPrefs->new;
    sub preferences { return $PREFS }
    sub import {
        my $caller = caller;
        no strict 'refs';
        *{"${caller}::preferences"} = \&preferences;
    }
    $INC{'Slim/Utils/Prefs.pm'} = __FILE__;

    package Slim::Web::Settings;
    sub handler { return }
    $INC{'Slim/Web/Settings.pm'} = __FILE__;

    package Slim::Utils::PluginManager;
    sub isEnabled { return 0 }
    $INC{'Slim/Utils/PluginManager.pm'} = __FILE__;

    package Slim::Utils::Strings;
    sub string { return $_[0] }
    sub import {
        my $caller = caller;
        no strict 'refs';
        *{"${caller}::string"} = \&string;
    }
    $INC{'Slim/Utils/Strings.pm'} = __FILE__;

    package Slim::Web::HTTP::CSRF;
    sub protectName { return $_[1] }
    sub protectURI { return $_[1] }

    package Plugins::BetterCallBliss::Defaults;
    sub import { }
    $INC{'Plugins/BetterCallBliss/Defaults.pm'} = __FILE__;

    package Plugins::BetterCallBliss::BlissCompatibility;
    sub snapshot { return {} }
    $INC{'Plugins/BetterCallBliss/BlissCompatibility.pm'} = __FILE__;

    package Plugins::BetterCallBliss::GuidanceProviderDiscovery;
    our $DISCOVERY = { providers => [] };
    sub discover { return $DISCOVERY }
    $INC{'Plugins/BetterCallBliss/GuidanceProviderDiscovery.pm'} = __FILE__;
}

require 'BetterCallBliss/GuidanceProviderPolicy.pm';
$INC{'Plugins/BetterCallBliss/GuidanceProviderPolicy.pm'}
    = $INC{'BetterCallBliss/GuidanceProviderPolicy.pm'};
require 'BetterCallBliss/Settings.pm';

my $provider = {
    provider_id => 'library-signals',
    available => 1,
    descriptor => {
        controls => [{
            key => 'playcount_influence', type => 'integer',
            minimum => -100, maximum => 100, factory_default => 0,
            host_overridable => 1,
        }],
    },
    defaults => { playcount_influence => -40 },
};
$Plugins::BetterCallBliss::GuidanceProviderDiscovery::DISCOVERY = {
    providers => [$provider],
};

Plugins::BetterCallBliss::Settings::_apply_guidance_provider_settings({
    saveSettings => 1,
    'pref_guidance_provider_library-signals_enabled' => 1,
    'pref_guidance_provider_library-signals_playcount_influence' => -20,
});

my $state = $Slim::Utils::Prefs::PREFS->get('guidance_provider_state');
is($state->{providers}->{'library-signals'}->{enabled}, 1,
    'checked provider checkbox enables the provider on an explicit save');
is($state->{providers}->{'library-signals'}->{overrides}->{playcount_influence}, -20,
    'provider control is persisted by the explicit save');

Plugins::BetterCallBliss::Settings::_apply_guidance_provider_settings({
    'pref_guidance_provider_library-signals_playcount_influence' => 42,
});
$state = $Slim::Utils::Prefs::PREFS->get('guidance_provider_state');
is($state->{providers}->{'library-signals'}->{overrides}->{playcount_influence}, -20,
    'non-save requests do not persist provider changes');

Plugins::BetterCallBliss::Settings::_apply_guidance_provider_settings({
    saveSettings => 1,
    'pref_guidance_provider_library-signals_enabled' => 1,
    'pref_guidance_provider_library-signals_playcount_influence' => -40,
    'inherit_guidance_provider_library-signals_playcount_influence' => 1,
});
$state = $Slim::Utils::Prefs::PREFS->get('guidance_provider_state');
ok(!exists $state->{providers}->{'library-signals'}->{overrides}->{playcount_influence},
    'saving a requested inherited value removes the host override');
my $inherited_policy = Plugins::BetterCallBliss::GuidanceProviderPolicy::resolve(
    $provider, $state->{providers}->{'library-signals'}, {},
);
is($inherited_policy->{origins}->{playcount_influence}, 'provider_default',
    'removed host override restores the provider-default provenance');

Plugins::BetterCallBliss::Settings::_apply_guidance_provider_settings({
    saveSettings => 1,
    'pref_guidance_provider_library-signals_enabled' => 1,
    'pref_guidance_provider_library-signals_playcount_influence' => -40,
    'dirty_guidance_provider_library-signals_playcount_influence' => 0,
});
$state = $Slim::Utils::Prefs::PREFS->get('guidance_provider_state');
ok(!exists $state->{providers}->{'library-signals'}->{overrides}->{playcount_influence},
    'saving unrelated settings does not turn an inherited value into a host override');

Plugins::BetterCallBliss::Settings::_apply_guidance_provider_settings({
    saveSettings => 1,
    'pref_guidance_provider_library-signals_enabled' => 1,
    'pref_guidance_provider_library-signals_playcount_influence' => -20,
    'dirty_guidance_provider_library-signals_playcount_influence' => 0,
});
$state = $Slim::Utils::Prefs::PREFS->get('guidance_provider_state');
is($state->{providers}->{'library-signals'}->{overrides}->{playcount_influence}, -20,
    'a changed submitted value persists even when a client-side dirty marker is unavailable');

Plugins::BetterCallBliss::Settings::_apply_guidance_provider_settings({
    saveSettings => 1,
});
$state = $Slim::Utils::Prefs::PREFS->get('guidance_provider_state');
is($state->{providers}->{'library-signals'}->{enabled}, 0,
    'unchecked provider checkbox disables the provider on an explicit save');

my $sections = Plugins::BetterCallBliss::Settings::_guidance_provider_sections([{
    %$provider,
    host_policy => {
        enabled => 1,
        valid => 1,
        effective => { playcount_influence => -20 },
        origins => { playcount_influence => 'host_override' },
    },
}]);
is($sections->[0]->{controls}->[0]->{inherited}, -40,
    'rendered control exposes the provider default for client-side copy');

done_testing;
