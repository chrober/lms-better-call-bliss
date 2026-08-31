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
        learned_blend => 20,
        no_repeat_artist => 5,
        no_repeat_album => 10,
        no_repeat_track => 100,
    );
    sub get { return $values{$_[1]} }

    package TestServerPrefs;
    sub get { return undef }

    package Slim::Utils::Prefs;
    our $directory;
    sub preferences {
        return $_[0] eq 'plugin.blissmixer'
            ? bless({}, 'TestBlissPrefs')
            : bless({}, 'TestServerPrefs');
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
    sub isEnabled { return 1 }
    $INC{'Slim/Utils/PluginManager.pm'} = __FILE__;
}

use lib "$FindBin::Bin/..";
require Plugins::BetterCallBliss::BlissCompatibility;

my $temporary = tempdir(CLEANUP => 1);
$Slim::Utils::Prefs::directory = $temporary;
my $database = File::Spec->catfile($temporary, 'bliss.db');
my $binary = File::Spec->catfile($temporary, 'bliss-playlist-optimizer');
for my $path ($database, $binary) {
    open my $fh, '>', $path or die "Cannot create $path: $!";
    close $fh;
}
chmod 0755, $binary;

Plugins::BetterCallBliss::BlissCompatibility::init($binary, 1, 1);
my $snapshot = Plugins::BetterCallBliss::BlissCompatibility::snapshot();

ok($snapshot->{ready}, 'compatible optimizer and readable Bliss database are ready');
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
