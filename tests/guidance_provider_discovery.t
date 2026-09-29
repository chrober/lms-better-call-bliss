use strict;
use warnings;
use Test::More;
use lib '.';

{
    package Slim::Utils::PluginManager;
    our @enabled;
    sub enabledPlugins { @enabled }
    $INC{'Slim/Utils/PluginManager.pm'} = __FILE__;

    package Plugins::GuidanceGood::Plugin;
    sub guidance_provider_descriptor_v1 {
        return {
            protocol_version => 1,
            provider_id => 'library-signals',
            display_name => 'Local library signals',
            capabilities => [qw(play_count last_played library_age)],
            scopes => ['global_candidate'],
            settings_schema_version => 1,
            controls => [{
                key => 'playcount_influence', type => 'integer',
                minimum => -100, maximum => 100, factory_default => 0,
                host_overridable => 1, render_as => 'number',
            }],
            native_spi => {
                provider_id => 'library-signals-guidance', spi_version => 2,
                protocol => 'bliss-guidance-jsonl-v2',
                channels => { play_count => 'playcount' },
                artifact_kinds => ['eligible-candidate-identities-v1'],
                resource_kinds => ['lms-persist-sqlite-v1'],
            },
        };
    }
    sub guidance_provider_defaults_v1 { return { playcount_influence => 0, settings_revision => 4 } }
    sub guidance_provider_status_v1 { return { available => 1 } }

    package Plugins::GuidanceMalformed::Plugin;
    sub guidance_provider_descriptor_v1 { return { provider_id => 'bad' } }

    package Plugins::GuidanceInvalidPresentation::Plugin;
    sub guidance_provider_descriptor_v1 {
        my $descriptor = Plugins::GuidanceGood::Plugin::guidance_provider_descriptor_v1();
        $descriptor->{provider_id} = 'invalid-presentation';
        $descriptor->{controls}->[0]->{render_as} = 'dial';
        return $descriptor;
    }

    package Plugins::GuidanceDuplicate::Plugin;
    sub guidance_provider_descriptor_v1 { return Plugins::GuidanceGood::Plugin::guidance_provider_descriptor_v1() }
    sub guidance_provider_defaults_v1 { return { playcount_influence => 0, settings_revision => 1 } }
    sub guidance_provider_status_v1 { return { available => 1 } }
}

require 'BetterCallBliss/GuidanceProviderDiscovery.pm';

@Slim::Utils::PluginManager::enabled = (
    'Plugins::GuidanceMalformed::Plugin',
    'Plugins::GuidanceInvalidPresentation::Plugin',
    'Plugins::GuidanceGood::Plugin',
    'Plugins::Unrelated::Plugin',
);
my $first = Plugins::BetterCallBliss::GuidanceProviderDiscovery::discover();
is(scalar @{$first->{providers}}, 3,
    'discovery records malformed descriptor diagnostics without hiding valid providers');
my ($good) = grep { $_->{provider_id} eq 'library-signals' } @{$first->{providers}};
ok($good->{available}, 'valid enabled provider is available');
is($good->{module}, 'Plugins::GuidanceGood::Plugin',
    'provider module is preserved for later trusted factory invocation');
is($good->{defaults}->{settings_revision}, 4,
    'provider defaults and revision are discovered through its public method');
is($good->{descriptor}->{controls}->[0]->{render_as}, 'number',
    'valid provider descriptor preserves its requested plain-number rendering');
my ($bad) = grep { $_->{module} eq 'Plugins::GuidanceMalformed::Plugin' } @{$first->{providers}};
ok(!$bad->{available}, 'malformed descriptor is visible as unavailable');
like($bad->{diagnostic}, qr/protocol_version/, 'malformed descriptor reports validation failure');
my ($invalid_presentation) = grep {
    $_->{module} eq 'Plugins::GuidanceInvalidPresentation::Plugin'
} @{$first->{providers}};
ok(!$invalid_presentation->{available}, 'invalid presentation metadata disables the provider');
like($invalid_presentation->{diagnostic}, qr/render_as/, 'invalid presentation metadata reports its key');

@Slim::Utils::PluginManager::enabled = (
    'Plugins::GuidanceGood::Plugin',
    'Plugins::GuidanceDuplicate::Plugin',
);
my $duplicate = Plugins::BetterCallBliss::GuidanceProviderDiscovery::discover();
is(scalar @{$duplicate->{providers}}, 2, 'both duplicate declarations are reported');
ok(!$_->{available}, 'duplicate provider IDs are rejected deterministically')
    for @{$duplicate->{providers}};

done_testing;
