use strict;
use warnings;
use FindBin;
use File::Path qw(make_path);
use File::Temp qw(tempdir);
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

require "$FindBin::Bin/../BetterCallBliss/JobHistory.pm";
my $history_root = tempdir(CLEANUP => 1);
make_path("$history_root/preview-1000-editor");
my $history = Plugins::BetterCallBliss::JobHistory->new($history_root);
$history->save({
    id => 'preview-1000-editor', state => 'completed', started_at => 1000,
    playlist_id => 42, source_mode => 'saved_playlist',
    capability => { static_weight_sliders => {tempo => 9, timbre => 30, loudness => 9, chroma => 57} },
    options => { ordering_policy => 'preserve_order', extension_mode => 'automatic_improvement',
        addition_purpose => 'automatic_improvement', satisfy_repeat_windows => 0,
        smooth_transitions => 1, artist_window => 4 },
    artifact => { artifact_kind => 'adaptive-route-v1' },
});
my ($restored_job) = $history->load;
my $restored_form = Plugins::BetterCallBliss::Web::_form_from_job($restored_job, {});
is($restored_form->{playlist_id}, 42, 'reopening restored preview retains playlist');
is($restored_form->{artist_window}, 4, 'reopening restored preview retains repeat window');
is($restored_form->{satisfy_repeat_windows}, 0, 'reopening restored preview retains disabled goal');
is($restored_form->{smooth_transitions}, 1, 'reopening restored preview retains enabled goal');
is($restored_form->{extras_weight_tempo}, 9, 'reopening restored preview retains captured weights');

my $goals = Plugins::BetterCallBliss::Web::_form_from_params({
    addition_purpose => 'automatic_improvement',
    satisfy_repeat_windows_present => 1,
    smooth_transitions_present => 1,
    smooth_transitions => 1,
}, {satisfy_repeat_windows => 1, smooth_transitions => 1});
is($goals->{satisfy_repeat_windows}, 0, 'unchecked spacing remains unchecked in the editor');
is($goals->{smooth_transitions}, 1, 'checked smoothing remains checked in the editor');

my $restored_goals = Plugins::BetterCallBliss::Web::_form_from_job({
    options => {satisfy_repeat_windows => 0, smooth_transitions => 1},
}, {satisfy_repeat_windows => 1, smooth_transitions => 1});
is($restored_goals->{satisfy_repeat_windows}, 0, 'reopened preview restores unchecked spacing');
is($restored_goals->{smooth_transitions}, 1, 'reopened preview restores checked smoothing');

my $legacy_goals = {addition_purpose => 'satisfy_constraints', extension_mode => 'repeat_window_repair'};
Plugins::BetterCallBliss::Web::_migrate_legacy_automatic_goals(
    $legacy_goals, {automatic_improvement_available => 1},
);
is($legacy_goals->{addition_purpose}, 'automatic_improvement', 'legacy spacing becomes combined editor');
is($legacy_goals->{satisfy_repeat_windows}, 1, 'legacy spacing selects spacing goal');
is($legacy_goals->{smooth_transitions}, 0, 'legacy spacing does not silently enable smoothing');
is(Plugins::BetterCallBliss::Web::_addition_reason_label('spacing'), 'Repeat-window spacing',
    'spacing additions explain their purpose');
is(Plugins::BetterCallBliss::Web::_addition_reason_label('smoothing'), 'Transition smoothing',
    'smoothing additions explain their purpose');
is(Plugins::BetterCallBliss::Web::_job_mode_label({options => {
    extension_mode => 'automatic_improvement', addition_purpose => 'automatic_improvement',
}}), 'Improve playlist automatically', 'running job identifies the combined workflow');

done_testing();
