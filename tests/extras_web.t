use strict;
use warnings;
use FindBin;
use Test::More;

BEGIN {
    package TestWebPrefs;
    our %values;
    sub get { $values{$_[1]} }
    sub set { $values{$_[1]} = $_[2] }
    package Slim::Utils::Prefs;
    sub preferences { bless {}, 'TestWebPrefs' }
    sub import { no strict 'refs'; *{caller() . '::preferences'} = \&preferences }
    $INC{'Slim/Utils/Prefs.pm'} = __FILE__;
    package Slim::Utils::Log;
    sub logger { bless {}, 'TestWebLog' }
    package TestWebLog;
    sub warn {}
    package Slim::Web::HTTP;
    sub filltemplatefile { return $_[1] }
    package Plugins::BetterCallBliss::BlissCompatibility;
    sub snapshot { return {seed_limit => 3, learned_percent => 0, artist_window => 5,
        album_window => 5, track_window => 5, matrix_available => 1,
        static_weight_sliders => {tempo => 4, timbre => 30, loudness => 9, chroma => 57},
        discovered_guidance_providers => []} }
    package Plugins::BetterCallBliss::Jobs;
    our $started = 0;
    sub note_web_activity {}
    sub finish_web_response {}
    sub start_reorder_preview { $started++; return undef }
    package Plugins::BetterCallBliss::CandidateLibrary;
    sub active_id { '' }
    sub choices { [] }
    package Plugins::BetterCallBliss::CandidateInventory;
    sub status { {} }
    for my $module (qw(
        Slim/Schema.pm Slim/Player/Client.pm Slim/Player/Playlist.pm
        Slim/Player/Source.pm Slim/Utils/Log.pm Slim/Utils/Misc.pm
        Slim/Utils/Unicode.pm Slim/Web/HTTP.pm Slim/Web/Pages.pm
        Plugins/BetterCallBliss/AlbumDestination.pm
        Plugins/BetterCallBliss/BlissCompatibility.pm
        Plugins/BetterCallBliss/CandidateInventory.pm
        Plugins/BetterCallBliss/CandidateLibrary.pm
        Plugins/BetterCallBliss/GuidanceReporting.pm
        Plugins/BlissGuidance/SettingsModel.pm
        Plugins/BetterCallBliss/Jobs.pm Plugins/BetterCallBliss/PlaylistWriter.pm
        Plugins/BetterCallBliss/RouteMode.pm
    )) { $INC{$module} = __FILE__ }
}

use lib "$FindBin::Bin/..";
require Plugins::BetterCallBliss::Web;
no warnings 'redefine';
*Plugins::BetterCallBliss::Web::_playlists = sub { [] };
*Plugins::BetterCallBliss::Web::_players = sub { [] };
*Plugins::BetterCallBliss::Web::_job_lists = sub { ([], []) };

my $response = Plugins::BetterCallBliss::Web::handler(undef, {
    save_extras_defaults => 1, run_preview => 1, playlist_id => 42,
});
is($Plugins::BetterCallBliss::Jobs::started, 0,
    'saving defaults never starts a preview even with a stale preview action');
ok($TestWebPrefs::values{extras_defaults}, 'save persists the profile');

Plugins::BetterCallBliss::Web::handler(undef, {
    load_extras_defaults => 1, extras_defaults_source => 'plugin',
    run_preview => 1, playlist_id => 42,
});
is($Plugins::BetterCallBliss::Jobs::started, 0,
    'loading defaults never starts a preview even with a stale preview action');

my $selection_result = Plugins::BetterCallBliss::Web::handler(undef, {
    select_extras_defaults => 1, extras_defaults_source => 'extras',
    run_preview => 1, playlist_id => 42,
});
is($$selection_result, 'ok', 'selector persistence returns a short success response');
is($TestWebPrefs::values{extras_defaults_source}, 'extras', 'selector persistence stores the choice');
is($Plugins::BetterCallBliss::Jobs::started, 0, 'selector persistence cannot start a preview');

my $job_form = Plugins::BetterCallBliss::Web::_form_from_job({
    options => {}, capability => {static_weight_sliders =>
        {tempo => 9, timbre => 30, loudness => 9, chroma => 57}},
}, {});
is($job_form->{extras_weight_tempo}, 9,
    'reopening a plugin-default job restores the captured static weights');

done_testing();
