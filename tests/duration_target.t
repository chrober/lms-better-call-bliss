use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use Test::More;

require Plugins::BetterCallBliss::DurationTarget;

is_deeply(
    [Plugins::BetterCallBliss::DurationTarget::bounds_seconds(120, 5, 10)],
    [6840, 7920],
    'asymmetric tolerance defines inclusive duration bounds in seconds',
);
is_deeply(
    [Plugins::BetterCallBliss::DurationTarget::bounds_seconds(1, 1, 1)],
    [59.4, 60.6],
    'fractional-second tolerance bounds retain precision',
);
is_deeply(
    [Plugins::BetterCallBliss::DurationTarget::bounds_seconds(120, 0, 0)],
    [7200, 7200],
    'zero tolerance requires the exact target',
);
is(Plugins::BetterCallBliss::DurationTarget::source_duration_seconds(
    [{duration => 120.25}, {duration => 239.75}]), 360,
    'source duration sums full-precision track lengths');
for my $duration (undef, 0, -1, 'unknown') {
    my $ok = eval {
        Plugins::BetterCallBliss::DurationTarget::source_duration_seconds(
            [{duration => $duration}]);
        1;
    };
    ok(!$ok, 'missing or invalid source duration is rejected');
}
is(Plugins::BetterCallBliss::DurationTarget::classify_source(6840, 6840, 7920),
    'within', 'source at the lower boundary needs no additions');
is(Plugins::BetterCallBliss::DurationTarget::classify_source(7920, 6840, 7920),
    'within', 'source at the upper boundary needs no additions');
is(Plugins::BetterCallBliss::DurationTarget::classify_source(6839.9, 6840, 7920),
    'short', 'source below the lower bound needs additions');
is(Plugins::BetterCallBliss::DurationTarget::classify_source(7920.1, 6840, 7920),
    'too_long', 'source above the upper bound cannot be extended into the interval');
my $preflight = Plugins::BetterCallBliss::DurationTarget::preflight(
    [{duration => 3500}, {duration => 3400}], 120, 5, 10);
is_deeply($preflight, {source_seconds => 6900, minimum_seconds => 6840,
    maximum_seconds => 7920, state => 'within'},
    'preflight captures source duration and both bounds');
{
    package TestDurationTrack;
    sub new { bless {secs => $_[1]}, $_[0] }
    sub secs { $_[0]->{secs} }
}
my $lms_preflight = Plugins::BetterCallBliss::DurationTarget::preflight_lms_tracks(
    [TestDurationTrack->new(3500), TestDurationTrack->new(3400)], 120, 5, 10);
is_deeply($lms_preflight, $preflight, 'Lyrion duration preflight reads secs from source tracks');
is(Plugins::BetterCallBliss::DurationTarget::lms_source_milliseconds(
    [TestDurationTrack->new(0.0016), TestDurationTrack->new(0.0016)]), 4,
    'source milliseconds use the same per-track rounding as candidate durations');
my $missing_lms_duration = eval {
    Plugins::BetterCallBliss::DurationTarget::preflight_lms_tracks(
        [TestDurationTrack->new(undef)], 120, 5, 10);
    1;
};
ok(!$missing_lms_duration, 'missing Lyrion source duration is rejected');
my $expected = {source_ms => 120000, minimum_ms => 216000, maximum_ms => 264000};
my $reported = {%$expected, actual_ms => 240000};
ok(Plugins::BetterCallBliss::DurationTarget::validate_result($expected, $reported, [120000]),
    'duration result matches the frozen target and actual candidate durations');
ok(!eval { Plugins::BetterCallBliss::DurationTarget::validate_result(
    $expected, {%$reported, actual_ms => 250000}, [120000]); 1 },
    'a misreported result duration is rejected');
ok(!eval { Plugins::BetterCallBliss::DurationTarget::validate_result(
    $expected, {%$reported, minimum_ms => 100000}, [120000]); 1 },
    'a result which changes the requested bounds is rejected');
ok(!eval { Plugins::BetterCallBliss::DurationTarget::validate_result(
    $expected, {%$reported, actual_ms => 210000}, [90000]); 1 },
    'a result outside the hard tolerance is rejected');
is_deeply(Plugins::BetterCallBliss::DurationTarget::report_values(120, {
    source_ms => 3000000, minimum_ms => 6480000, maximum_ms => 7920000, actual_ms => 7560000,
}), {target => '02:00:00', minimum => '01:48:00', maximum => '02:12:00',
    actual => '02:06:00', deviation_percent => '+5.0%'},
    'duration report shows the target, both bounds, actual duration, and signed deviation');
like(Plugins::BetterCallBliss::DurationTarget::failure_message({
    source_ms => 3000000, minimum_ms => 6480000, maximum_ms => 7920000,
}), qr/01:48:00.*02:12:00.*tolerance.*repeat/i,
    'duration failure shows the permitted range and actionable adjustments');
done_testing();
