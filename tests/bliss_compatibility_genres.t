use strict;
use warnings;
use FindBin;
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

BEGIN {
    package TestBlissPrefs;
    our %values = (
        filter_genres => 1,
        filter_xmas => 1,
        genre_groups => " Rock ; Hard Rock \n Jazz* ; \n ; Ambient ",
        match_all_genres => 1,
        use_track_genre => 1,
        use_adaptive_weights => 1,
        use_forest => 0,
        num_seed_tracks => 3,
        no_repeat_artist => 5,
        no_repeat_album => 10,
        no_repeat_track => 100,
    );
    sub get { return $values{$_[1]} }

    package TestBlissExtPrefs;
    our %values = (
        learned_blend => 20,
        lastfm_track_guidance_percent => 68,
    );
    sub get { return $values{$_[1]} }

    package TestServerPrefs;
    sub get { return undef }

    package Slim::Utils::Prefs;
    our $directory;
    sub preferences {
        return bless({}, 'TestBlissPrefs')
            if $_[0] eq 'plugin.blissmixer';
        return bless({}, 'TestBlissExtPrefs')
            if $_[0] eq 'plugin.blissmixerext';
        return bless({}, 'TestServerPrefs');
    }
    sub dir { return $directory }
    sub import {
        no strict 'refs';
        *{caller() . '::preferences'} = \&preferences;
    }
    $INC{'Slim/Utils/Prefs.pm'} = __FILE__;

    package Slim::Music::Import;
    sub stillScanning { return 0 }
    $INC{'Slim/Music/Import.pm'} = __FILE__;

    package Slim::Utils::Misc;
    sub getAudioDirs { return ['/music'] }
    $INC{'Slim/Utils/Misc.pm'} = __FILE__;

    package Slim::Utils::PluginManager;
    our %enabled = (
        'Plugins::BlissMixer::Plugin' => 1,
        'Plugins::BlissMixerExt::Plugin' => 1,
    );
    our %versions = (
        'Plugins::BlissMixer::Plugin' => '0.10.0',
        'Plugins::BlissMixerExt::Plugin' => '0.3.0',
    );
    sub isEnabled { return $enabled{$_[1]} || 0 }
    sub dataForPlugin {
        return {version => $versions{$_[1]}} if exists $versions{$_[1]};
        return undef;
    }
    $INC{'Slim/Utils/PluginManager.pm'} = __FILE__;

    package Slim::Utils::Versions;
    sub compareVersions {
        my @left = split /\./, $_[1];
        my @right = split /\./, $_[2];
        for my $index (0 .. 2) {
            my $comparison = ($left[$index] || 0) <=> ($right[$index] || 0);
            return $comparison if $comparison;
        }
        return 0;
    }
    $INC{'Slim/Utils/Versions.pm'} = __FILE__;
}

use lib "$FindBin::Bin/..";
require Plugins::BetterCallBliss::BlissCompatibility;

my $temporary = tempdir(CLEANUP => 1);
$Slim::Utils::Prefs::directory = $temporary;
my $database = File::Spec->catfile($temporary, 'bliss.db');
my $matrix = File::Spec->catfile($temporary, 'learned_matrix.json');
my $binary = File::Spec->catfile($temporary, 'bliss-playlist-optimizer');
for my $path ($database, $matrix, $binary) {
    open my $fh, '>', $path or die "Cannot create $path: $!";
    close $fh;
}
chmod 0755, $binary;

Plugins::BetterCallBliss::BlissCompatibility::init($binary, 1, 1);
my $snapshot = Plugins::BetterCallBliss::BlissCompatibility::snapshot();

ok($snapshot->{ready}, 'compatible optimizer and readable Bliss database are ready');
ok($snapshot->{bliss_compatible}, 'original BlissMixer satisfies the required base version');
ok($snapshot->{blissmixerext_compatible}, 'BlissMixerExt is detected independently');
is($snapshot->{matrix_provider}, 'BlissMixerExt', 'BlissMixerExt owns the learned matrix capability');
is($snapshot->{learned_percent}, 20, 'learned blend is read from BlissMixerExt');
ok($snapshot->{lastfm_track_guidance_available},
    'BlissMixerExt track-guidance capability is detected');
is($snapshot->{lastfm_track_guidance_percent}, 68,
    'Last.fm track guidance is read from BlissMixerExt');
ok($snapshot->{filter_genres}, 'genre restriction is captured');
ok($snapshot->{filter_xmas}, 'configured Christmas preference is captured');
is($snapshot->{exclude_christmas}, (localtime())[4] == 11 ? 0 : 1,
    'Christmas exclusion is disabled only during December');
is_deeply(
    $snapshot->{genre_groups},
    [['Rock', 'Hard Rock'], ['Jazz*'], ['Ambient']],
    'genre groups preserve rows and patterns while trimming empty values',
);
ok($snapshot->{match_all_genres}, 'match-all mode is captured');
ok($snapshot->{use_track_genre}, 'per-track genre mode is captured');

unlink $matrix or die "Cannot remove $matrix: $!";
my $without_matrix = Plugins::BetterCallBliss::BlissCompatibility::snapshot();
ok($without_matrix->{ready}, 'a missing optional learned matrix does not block previews');
is($without_matrix->{personalization_state}, 'matrix_not_trained',
    'an enabled extension without training has a distinct state');
is($without_matrix->{configured_learned_percent}, 20,
    'the configured extension blend remains visible without a matrix');
is($without_matrix->{learned_percent}, 0,
    'the effective learned blend is forced to zero without a matrix');

$Slim::Utils::PluginManager::enabled{'Plugins::BlissMixerExt::Plugin'} = 0;
my $without_extension = Plugins::BetterCallBliss::BlissCompatibility::snapshot();
ok($without_extension->{ready}, 'the optional extension does not gate base readiness');
is($without_extension->{personalization_state}, 'extension_not_enabled',
    'the missing optional extension is reported explicitly');
is($without_extension->{learned_percent}, 0,
    'the extension preference is ignored when the extension is disabled');
ok(!$without_extension->{lastfm_track_guidance_available},
    'disabled BlissMixerExt does not provide track guidance');
is($without_extension->{lastfm_track_guidance_percent}, 25,
    'disabled BlissMixerExt uses the safe track-guidance fallback');
ok(@{$without_extension->{notices}}, 'optional personalization fallback is explained');
$Slim::Utils::PluginManager::enabled{'Plugins::BlissMixerExt::Plugin'} = 1;

$Slim::Utils::PluginManager::versions{'Plugins::BlissMixerExt::Plugin'} = '0.2.0';
my $before_track_guidance = Plugins::BetterCallBliss::BlissCompatibility::snapshot();
ok(!$before_track_guidance->{lastfm_track_guidance_available},
    'older BlissMixerExt releases do not claim the track-guidance capability');
is($before_track_guidance->{lastfm_track_guidance_percent}, 25,
    'older BlissMixerExt releases use the safe track-guidance fallback');
$Slim::Utils::PluginManager::versions{'Plugins::BlissMixerExt::Plugin'} = '0.3.0';

$Slim::Utils::PluginManager::enabled{'Plugins::BlissMixer::Plugin'} = 0;
my $without_base = Plugins::BetterCallBliss::BlissCompatibility::snapshot();
ok(!$without_base->{ready}, 'the original BlissMixer remains the required base plugin');
like(join('; ', @{$without_base->{problems}}), qr/BlissMixer is not enabled/,
    'the missing required base plugin is a blocking problem');
$Slim::Utils::PluginManager::enabled{'Plugins::BlissMixer::Plugin'} = 1;

Plugins::BetterCallBliss::BlissCompatibility::init($binary, 0, 1);
my $incompatible = Plugins::BetterCallBliss::BlissCompatibility::snapshot();
ok(!$incompatible->{ready}, 'an older optimizer is rejected instead of ignoring genre settings');
like(join('; ', @{$incompatible->{problems}}), qr/does not support BlissMixer genre settings/,
    'the compatibility failure explains the required optimizer capability');

Plugins::BetterCallBliss::BlissCompatibility::init($binary, 1, 0);
my $old_candidate_scope = Plugins::BetterCallBliss::BlissCompatibility::snapshot();
ok(!$old_candidate_scope->{ready},
    'an optimizer without candidate-library scoping is rejected');
like(join('; ', @{$old_candidate_scope->{problems}}),
    qr/does not support candidate-library scoping/,
    'candidate-library compatibility failure names the missing capability');

done_testing();
