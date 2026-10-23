use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/..";

sub slurp {
    my $path = shift;
    open my $fh, '<', $path or die "Could not read $path: $!";
    local $/;
    return <$fh>;
}

BEGIN {
    package Slim::Utils::Log;
    sub logger { return bless {}, 'TestLogger' }
    $INC{'Slim/Utils/Log.pm'} = __FILE__;

    package Slim::Utils::Timers;
    sub setTimer { }
    $INC{'Slim/Utils/Timers.pm'} = __FILE__;

    package Plugins::BetterCallBliss::CandidateIdentity;
    sub normalize_text { return defined $_[0] ? lc($_[0]) : '' }
    sub normalize_mbid { return defined $_[0] ? lc($_[0]) : '' }
    $INC{'Plugins/BetterCallBliss/CandidateIdentity.pm'} = __FILE__;
}

require "$FindBin::Bin/../BetterCallBliss/CandidateGuidance.pm";

my $native_bundle_builder =
    Plugins::BetterCallBliss::CandidateGuidance->can('native_provider_semantic_bundle');
ok($native_bundle_builder,
    'native providers have a semantic bundle that does not invent an acquisition state');
SKIP: {
    skip 'native provider semantic bundle is not implemented', 1
        unless $native_bundle_builder;
    is_deeply(
        $native_bundle_builder->(),
        {
            schema_version => 1,
            frozen_at => '1970-01-01T00:00:00Z',
            providers => [],
            edges => [],
        },
        'direct acquisition leaves lifecycle reporting to native provider diagnostics',
    );
}

my $native_state_reader =
    Plugins::BetterCallBliss::CandidateGuidance->can('native_provider_state');
ok($native_state_reader,
    'native provider diagnostics can update the host lifecycle state');
SKIP: {
    skip 'native provider state mapping is not implemented', 3
        unless $native_state_reader;
    is(
        $native_state_reader->({
            guidance_addon_diagnostics => [{
                configured_id => 'lastfm-guidance',
                state => 'prepared',
            }],
        }, 'lastfm-guidance'),
        'fresh',
        'a prepared native provider becomes fresh host evidence',
    );
    is(
        $native_state_reader->({
            guidance_addon_diagnostics => [{
                configured_id => 'lastfm-guidance',
                state => 'failed',
            }],
        }, 'lastfm-guidance'),
        'failed',
        'a failed native provider remains failed in host reporting',
    );
    is(
        $native_state_reader->({guidance_addon_diagnostics => []}, 'lastfm-guidance'),
        undef,
        'missing native diagnostics do not overwrite an existing host state',
    );
}

my $jobs = slurp("$FindBin::Bin/../BetterCallBliss/Jobs.pm");
like(
    $jobs,
    qr/CandidateGuidance::native_provider_semantic_bundle\(\)/,
    'direct acquisition launches with an empty host semantic bundle',
);
like(
    $jobs,
    qr/CandidateGuidance::native_provider_state\(/,
    'native diagnostics update the host Last.fm lifecycle state',
);
unlike(
    $jobs,
    qr/lastfm-guidance-v1\.json|cache_path\s*=>/,
    'the generic host no longer constructs or supplies a Last.fm cache path',
);

done_testing();
