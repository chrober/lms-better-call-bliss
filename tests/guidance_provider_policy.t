use strict;
use warnings;
use Test::More;
use lib '.';

require 'BetterCallBliss/GuidanceProviderPolicy.pm';

my $provider = {
    provider_id => 'library-signals',
    descriptor => {
        settings_schema_version => 1,
        controls => [
            { key => 'playcount_influence', type => 'integer', minimum => -100, maximum => 100, factory_default => 0, host_overridable => 1 },
            { key => 'last_played_horizon_days', type => 'integer', minimum => 30, maximum => 1825, factory_default => 180, host_overridable => 1 },
        ],
    },
    defaults => { playcount_influence => -40, last_played_horizon_days => 365, settings_revision => 7 },
};

my $disabled = Plugins::BetterCallBliss::GuidanceProviderPolicy::resolve(
    $provider, {}, {},
);
ok(!$disabled->{enabled}, 'a discovered provider remains disabled by default');
is($disabled->{effective}->{playcount_influence}, -40,
    'provider saved defaults are visible before host enablement');
is($disabled->{origins}->{playcount_influence}, 'provider_default',
    'provider-default origin is retained');

my $host = Plugins::BetterCallBliss::GuidanceProviderPolicy::resolve(
    $provider,
    { enabled => 1, overrides => { playcount_influence => 0 } },
    {},
);
ok($host->{enabled}, 'host can explicitly enable a discovered provider');
is($host->{effective}->{playcount_influence}, 0,
    'an explicit host zero is an override, not inheritance');
is($host->{origins}->{playcount_influence}, 'host_override',
    'host override provenance is retained');

my $job = Plugins::BetterCallBliss::GuidanceProviderPolicy::resolve(
    $provider,
    { enabled => 1, overrides => { playcount_influence => 30 } },
    { overrides => { playcount_influence => 0 } },
);
is($job->{effective}->{playcount_influence}, 0,
    'an explicit per-job zero overrides a host value');
is($job->{origins}->{playcount_influence}, 'job_override',
    'job override provenance wins');
is($job->{provider_revision}, 7, 'provider revision is frozen with the policy');
is($job->{descriptor_version}, 1, 'descriptor version is frozen with the policy');

my $invalid = Plugins::BetterCallBliss::GuidanceProviderPolicy::resolve(
    $provider,
    { enabled => 1, overrides => { last_played_horizon_days => 1 } },
    {},
);
ok(!$invalid->{valid}, 'invalid host override is rejected');
like($invalid->{diagnostic}, qr/last_played_horizon_days/, 'invalid control reports its key');

done_testing;
