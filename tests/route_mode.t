use strict;
use warnings;
use FindBin;
use Test::More tests => 15;

use lib "$FindBin::Bin/..";
require Plugins::BetterCallBliss::RouteMode;

is(Plugins::BetterCallBliss::RouteMode::normalize_source(), 'queue_end',
    'missing source preserves the original queue-end behavior');
is(Plugins::BetterCallBliss::RouteMode::normalize_source('queue_end'), 'queue_end',
    'queue-end source is valid');
is(Plugins::BetterCallBliss::RouteMode::normalize_source('now_playing'), 'now_playing',
    'now-playing source is valid');
is(Plugins::BetterCallBliss::RouteMode::normalize_source('round_trip'), 'round_trip',
    'round-trip source is valid');
ok(!defined Plugins::BetterCallBliss::RouteMode::normalize_source('other'),
    'unknown source is rejected');
is(Plugins::BetterCallBliss::RouteMode::queue_action('queue_end'), 'append',
    'queue-end routes can only append');
is(Plugins::BetterCallBliss::RouteMode::queue_action('now_playing'), 'replace_upcoming',
    'now-playing routes can only replace upcoming entries');
is(Plugins::BetterCallBliss::RouteMode::queue_action('round_trip'), 'play_next',
    'round-trip routes can only insert before the upcoming queue');
ok(!defined Plugins::BetterCallBliss::RouteMode::queue_action('other'),
    'unknown source has no queue action');
is(Plugins::BetterCallBliss::RouteMode::action_name('queue_end'),
    'Bliss me there... when we\'re through!',
    'queue-end action has a distinct deferred menu name');
is(Plugins::BetterCallBliss::RouteMode::action_name('now_playing'),
    'Bliss me there...',
    'now-playing action has the concise primary menu name');
is(Plugins::BetterCallBliss::RouteMode::action_name('round_trip'),
    'Bliss me there... and back again!',
    'round-trip action has a distinct menu name');
ok(!defined Plugins::BetterCallBliss::RouteMode::action_name('other'),
    'unknown source has no action name');
is(Plugins::BetterCallBliss::RouteMode::queue_action(), 'append',
    'legacy jobs without a source remain append-only');
is(Plugins::BetterCallBliss::RouteMode::action_name(),
    'Bliss me there... when we\'re through!',
    'legacy jobs retain queue-end semantics under the new label');
