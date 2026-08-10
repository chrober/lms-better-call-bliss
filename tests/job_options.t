use strict;
use warnings;
use FindBin;
use Test::More tests => 19;

BEGIN {
    package TestPrefs;
    our %values = (
        auto_bridge_budget => '12',
        auto_trigger_percent => '65',
        lastfm_enabled => 1,
        lastfm_track_guidance_percent => '75',
        lastfm_artist_guidance_percent => '75',
        restart_count => '80',
    );
    sub get { return $values{$_[1]} }

    package Slim::Utils::Prefs;
    sub preferences { return bless {}, 'TestPrefs' }
    sub import {
        no strict 'refs';
        *{caller() . '::preferences'} = \&preferences;
    }
    $INC{'Slim/Utils/Prefs.pm'} = __FILE__;
}

use lib "$FindBin::Bin/..";
require Plugins::BetterCallBliss::JobOptions;

my $capability = {
    algorithm => 'forest',
    seed_limit => '3',
    learned_percent => '20',
    artist_window => '5',
    album_window => '10',
    track_window => '100',
};

my $defaults = Plugins::BetterCallBliss::JobOptions::defaults($capability);
is($defaults->{algorithm}, 'adaptive',
    'unsupported Forest default falls back to Adaptive');
is($defaults->{restart_count}, 80,
    'restart count default is read from plugin preferences');
is($defaults->{lastfm_enabled}, 1,
    'Last.fm default is read from plugin preferences');
is($defaults->{lastfm_track_guidance_percent}, 75,
    'track guidance default is 75');
is($defaults->{lastfm_artist_guidance_percent}, 75,
    'artist guidance default is 75');
is($defaults->{max_added_tracks}, 12,
    'automatic addition budget default is read from plugin preferences');
is($defaults->{trigger_percent}, 65,
    'automatic trigger default is read from plugin preferences');

my $legacy_exact = Plugins::BetterCallBliss::JobOptions::normalize(
    $capability,
    { extension_mode => 'exact_count', additional_track_count => '7' },
);
is($legacy_exact->{addition_purpose}, 'none',
    'legacy exact-count extension remains accepted');
is($legacy_exact->{addition_amount_mode}, 'exact_count',
    'legacy exact-count extension maps to the amount selector');
is($legacy_exact->{additional_track_count}, 7,
    'additional count is normalized to an integer');

my $extend = Plugins::BetterCallBliss::JobOptions::normalize(
    $capability,
    {
        addition_purpose => 'extend_playlist',
        addition_amount_mode => 'target_count',
        bridge_target_track_count => '33',
    },
);
is($extend->{extension_mode}, 'fixed_source_extension',
    'extend playlist uses the native fixed-source extension');
is($extend->{bridge_target_track_count}, 33,
    'target track count input is normalized to an integer');

my $queue = Plugins::BetterCallBliss::JobOptions::normalize(
    $capability,
    {
        output_mode => 'player_queue',
        queue_player_id => '  aa:bb:cc  ',
        queue_action => 'play_next',
        queue_start_playback => '1',
    },
);
is($queue->{queue_player_id}, 'aa:bb:cc',
    'queue player id is trimmed');
is($queue->{queue_action}, 'play_next',
    'queue action is retained');
is($queue->{queue_start_playback}, 1,
    'queue start playback is normalized to a boolean-ish integer');

my $named = Plugins::BetterCallBliss::JobOptions::normalize(
    $capability,
    { output_name => "  My\x{0a}Copy  " },
);
is($named->{output_name}, 'My Copy',
    'copy names are trimmed and control characters are replaced');
is($named->{output_name_generated}, 0,
    'explicit copy name is not marked as generated');

eval {
    Plugins::BetterCallBliss::JobOptions::normalize(
        $capability,
        { ordering_policy => 'preserve_order', extension_mode => 'none' },
    );
};
like($@, qr/requires an addition mode/,
    'preserve order without additions is rejected');

eval {
    Plugins::BetterCallBliss::JobOptions::normalize(
        $capability,
        { output_mode => 'player_queue', queue_player_id => '   ' },
    );
};
like($@, qr/Choose a player/,
    'player queue output requires a selected player');
