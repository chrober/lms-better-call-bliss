use strict;
use warnings;
use FindBin;
use Test::More;

BEGIN {
    package TestExtrasPrefs;
    sub get { return $_[0]->{$_[1]} }
    sub set { $_[0]->{$_[1]} = $_[2] }
    package Slim::Utils::Prefs;
    sub preferences { return bless {}, 'TestExtrasPrefs' }
    sub import { no strict 'refs'; *{caller() . '::preferences'} = \&preferences; }
    $INC{'Slim/Utils/Prefs.pm'} = __FILE__;
}

use lib "$FindBin::Bin/..";
require Plugins::BetterCallBliss::ExtrasDefaults;

my $profile = Plugins::BetterCallBliss::ExtrasDefaults::capture(
    { artist_window => 0, learned_percent => 25, playlist_id => 123,
      generation_seed => 42, queue_player_id => 'player' },
    { static_weight_sliders => {tempo => 4, timbre => 30, loudness => 9, chroma => 57},
      discovered_guidance_providers => [] },
);
is($profile->{schema_version}, 1, 'profile has a schema version');
is($profile->{options}->{artist_window}, 0, 'zero repeat window is retained');
is($profile->{options}->{learned_percent}, 25, 'desired learned percentage is retained');
ok(!exists $profile->{options}->{playlist_id}, 'source playlist is excluded');
ok(!exists $profile->{options}->{queue_player_id}, 'player is excluded');
ok(!exists $profile->{options}->{generation_seed}, 'generation seed is excluded');
is($profile->{static_weights}->{tempo}, 4, 'static scoring weights are captured');

my $provider = {
    provider_id => 'library-signals', available => 1,
    descriptor => { controls => [
        { key => 'library_age_influence', type => 'integer', minimum => -100,
          maximum => 100, factory_default => 0, host_overridable => 1 },
        { key => 'use_alternative_play_count', type => 'boolean',
          factory_default => 0, host_overridable => 1 },
        { key => 'api_key', type => 'enum', factory_default => 'secret',
          values => ['secret'], host_overridable => 0 },
    ] },
    host_state => { enabled => 1, overrides => {} },
    host_policy => { valid => 1, enabled => 1, effective => {
        library_age_influence => 10, use_alternative_play_count => 1,
        api_key => 'secret',
    } },
};
my $with_provider = Plugins::BetterCallBliss::ExtrasDefaults::capture(
    { 'guidance_provider_library-signals_library_age_influence' => 0,
      'guidance_provider_library-signals_use_alternative_play_count_present' => 1 },
    { discovered_guidance_providers => [$provider] },
);
is($with_provider->{providers}->{'library-signals'}->{overrides}->{library_age_influence}, 0,
    'explicit neutral guidance is saved');
is($with_provider->{providers}->{'library-signals'}->{overrides}->{use_alternative_play_count}, 0,
    'unchecked boolean guidance is saved as false');
ok(!exists $with_provider->{providers}->{'library-signals'}->{overrides}->{api_key},
    'provider-wide credentials are excluded');

my $invalid = eval {
    Plugins::BetterCallBliss::ExtrasDefaults::capture(
        { artist_window => -1 },
        { seed_limit => 3, learned_percent => 0, artist_window => 5,
          album_window => 5, track_window => 5, matrix_available => 1,
          discovered_guidance_providers => [] },
    );
    1;
};
ok(!$invalid, 'invalid reusable options are rejected before a profile can be saved');

my $expanded = Plugins::BetterCallBliss::ExtrasDefaults::expand_weights(
    { tempo => 4, timbre => 30, loudness => 9, chroma => 57 },
);
is(scalar @$expanded, 23, 'four static sliders expand to 23 features');
cmp_ok(abs($expanded->[0] - 1), '<', 0.000001, 'tempo weight is normalized');
ok(!eval { Plugins::BetterCallBliss::ExtrasDefaults::expand_weights(
    { tempo => -1, timbre => 30, loudness => 9, chroma => 57 }); 1 },
    'invalid static weight is rejected');

my ($loaded, $warnings) = Plugins::BetterCallBliss::ExtrasDefaults::apply(
    $with_provider, {},
    { discovered_guidance_providers => [$provider] },
);
is($loaded->{'guidance_provider_library-signals_library_age_influence'}, 0,
    'loading preserves neutral provider override');
is($loaded->{'guidance_provider_library-signals_use_alternative_play_count'}, 0,
    'loading preserves false provider override');
is($loaded->{'guidance_provider_library-signals_enabled'}, 1,
    'loading preserves provider enablement');
is_deeply($warnings, [], 'valid provider profile needs no warning');

my $changed_provider = { %$provider, descriptor => { controls => [
    {key => 'library_age_influence', type => 'integer', minimum => 20,
     maximum => 100, factory_default => 20, host_overridable => 1},
] }, host_state => {enabled => 0, overrides => {}},
    host_policy => {valid => 1, enabled => 0, effective => {library_age_influence => 20}} };
my ($changed, $changed_warnings) = Plugins::BetterCallBliss::ExtrasDefaults::apply(
    $with_provider, {}, {discovered_guidance_providers => [$changed_provider]},
);
ok(!exists $changed->{'guidance_provider_library-signals_library_age_influence'},
    'invalid changed provider value falls back to current default');
ok(@$changed_warnings, 'changed provider values are reported');

my $disabled = Plugins::BetterCallBliss::ExtrasDefaults::capture(
    { 'guidance_provider_library-signals_enabled_present' => 1,
      extras_weight_tempo => 8, extras_weight_timbre => 30,
      extras_weight_loudness => 9, extras_weight_chroma => 57 },
    { static_weight_sliders => {tempo => 4, timbre => 30, loudness => 9, chroma => 57},
      discovered_guidance_providers => [$provider] },
);
is($disabled->{providers}->{'library-signals'}->{enabled}, 0,
    'unchecked provider is saved as disabled');
is($disabled->{static_weights}->{tempo}, 8,
    'saving keeps the scoring weights currently loaded into the editor');

my $plugin_values = Plugins::BetterCallBliss::ExtrasDefaults::apply_plugin_defaults(
    { artist_window => 9, playlist_id => 123, extras_weight_tempo => 8,
      'guidance_provider_library-signals_library_age_influence' => 99 },
    { artist_window => 5 },
);
is($plugin_values->{artist_window}, 5, 'loading plugin defaults replaces reusable options');
is($plugin_values->{playlist_id}, 123, 'loading plugin defaults retains source');
ok(!exists $plugin_values->{extras_weight_tempo}, 'plugin defaults use live BlissMixer weights');
ok(!exists $plugin_values->{'guidance_provider_library-signals_library_age_influence'},
    'plugin defaults restore provider inheritance');

my $prefs = bless {}, 'TestExtrasPrefs';
my $simple_capability = {seed_limit => 3, learned_percent => 0, artist_window => 5,
    album_window => 5, track_window => 5, matrix_available => 1,
    static_weight_sliders => {tempo => 4, timbre => 30, loudness => 9, chroma => 57},
    discovered_guidance_providers => []};
my $base = {artist_window => 5};
my ($saved, $view) = Plugins::BetterCallBliss::ExtrasDefaults::prepare_editor(
    $prefs, {save_extras_defaults => 1}, {artist_window => 12, playlist_id => 123},
    $base, $simple_capability,
);
is($prefs->get('extras_defaults_source'), 'extras', 'save selects Extras defaults');
is($prefs->get('extras_defaults')->{options}->{artist_window}, 12, 'save persists reusable option');
is($saved->{playlist_id}, 123, 'save retains the current source');
is($saved->{extras_weight_tempo}, 4, 'saved weights remain captured in the current editor');
my ($new_form) = Plugins::BetterCallBliss::ExtrasDefaults::prepare_editor(
    $prefs, {}, {artist_window => 5}, $base, $simple_capability,
);
is($new_form->{artist_window}, 12, 'a new Extras editor loads saved defaults');
my ($job_form) = Plugins::BetterCallBliss::ExtrasDefaults::prepare_editor(
    $prefs, {job_id => 'existing'}, {artist_window => 6}, $base, $simple_capability,
);
is($job_form->{artist_window}, 6, 'job views are not replaced by saved defaults');
my ($route_form) = Plugins::BetterCallBliss::ExtrasDefaults::prepare_editor(
    $prefs, {quick_route => 1}, {source_mode => 'route_to_track', artist_window => 5},
    $base, $simple_capability,
);
is($route_form->{artist_window}, 5, 'destination routes never load Extras defaults');
Plugins::BetterCallBliss::ExtrasDefaults::prepare_editor(
    $prefs, {load_extras_defaults => 1, extras_defaults_source => 'plugin'},
    {artist_window => 12, playlist_id => 123}, $base, $simple_capability,
);
is($prefs->get('extras_defaults_source'), 'plugin', 'loading plugin defaults selects them for future previews');

$prefs->set('extras_defaults', {schema_version => 1, options => {learned_percent => 45}, providers => {},
    static_weights => {tempo => 4, timbre => 30, loudness => 9, chroma => 57}});
$prefs->set('extras_defaults_source', 'extras');
my %without_matrix = (%$simple_capability, matrix_available => 0);
Plugins::BetterCallBliss::ExtrasDefaults::prepare_editor(
    $prefs, {save_extras_defaults => 1}, {learned_percent => 0}, $base, \%without_matrix,
);
is($prefs->get('extras_defaults')->{options}->{learned_percent}, 45,
    'saving a job with an unavailable matrix preserves the desired Extras blend');

my $prior_profile = $prefs->get('extras_defaults');
my $saved_invalid = eval {
    Plugins::BetterCallBliss::ExtrasDefaults::prepare_editor(
        $prefs, {save_extras_defaults => 1}, {artist_window => -3}, $base, $simple_capability,
    ); 1;
};
ok(!$saved_invalid, 'invalid save is rejected');
is($prefs->get('extras_defaults'), $prior_profile, 'invalid save leaves existing profile untouched');

$prefs->set('extras_defaults', $with_provider);
my ($missing_form, $missing_view) = Plugins::BetterCallBliss::ExtrasDefaults::prepare_editor(
    $prefs, {}, {}, {}, $simple_capability,
);
ok(@{$missing_view->{warnings}}, 'missing provider is reported when a saved profile loads');
Plugins::BetterCallBliss::ExtrasDefaults::prepare_editor(
    $prefs, {save_extras_defaults => 1}, {}, {}, $simple_capability,
);
is($prefs->get('extras_defaults')->{providers}->{'library-signals'}->{overrides}->{library_age_influence}, 0,
    'saving while a provider is absent retains its saved values');

my ($unchanged, $selection) = Plugins::BetterCallBliss::ExtrasDefaults::prepare_editor(
    $prefs, {select_extras_defaults => 1, extras_defaults_source => 'plugin'},
    {artist_window => 12}, $base, $simple_capability,
);
is($prefs->get('extras_defaults_source'), 'plugin', 'changing selector persists the source immediately');
is($unchanged->{artist_window}, 12, 'changing selector does not replace current editor values');

my %configured_without_matrix = (%without_matrix, configured_learned_percent => 35);
Plugins::BetterCallBliss::ExtrasDefaults::prepare_editor(
    $prefs, {save_extras_defaults => 1}, {learned_percent => 0}, $base, \%configured_without_matrix,
);
is($prefs->get('extras_defaults')->{options}->{learned_percent}, 35,
    'first save with unavailable matrix retains the configured plugin blend');

my ($invalid_form, $invalid_warnings) = Plugins::BetterCallBliss::ExtrasDefaults::apply(
    {schema_version => 1, options => {artist_window => -7}, providers => {}},
    {artist_window => 5}, $simple_capability,
);
is($invalid_form->{artist_window}, 5, 'invalid saved job options fall back to current plugin defaults');
ok(@$invalid_warnings, 'invalid saved job options are reported');

my ($new_provider_form, $new_provider_warnings) = Plugins::BetterCallBliss::ExtrasDefaults::apply(
    {schema_version => 1, options => {}, providers => {}}, {},
    { %$simple_capability, discovered_guidance_providers => [$provider] },
);
ok(@$new_provider_warnings, 'new provider defaults are identified on profile load');
my ($new_setting_form, $new_setting_warnings) = Plugins::BetterCallBliss::ExtrasDefaults::apply(
    {schema_version => 1, options => {artist_window => 7}, providers => {}},
    {artist_window => 5, variation_percent => 33}, $simple_capability,
);
is($new_setting_form->{variation_percent}, 33, 'new preview option uses the plugin default');
like(join(' ', @$new_setting_warnings), qr/variation percent/,
    'new preview option identifies its plugin default source');

ok(eval {
    Plugins::BetterCallBliss::ExtrasDefaults::capture(
        {artist_window => 5, generation_seed => 'not a seed',
         output_mode => 'player_queue', queue_player_id => ''}, $simple_capability,
    ); 1;
}, 'saving defaults ignores invalid run-specific output and seed fields');
my ($unrelated_form, $unrelated_warnings) = Plugins::BetterCallBliss::ExtrasDefaults::apply(
    {schema_version => 1, options => {artist_window => 7}, providers => {}},
    {artist_window => 5, generation_seed => 'not a seed'}, $simple_capability,
);
is($unrelated_form->{artist_window}, 7, 'loading saved defaults ignores invalid run-specific seed');

done_testing();
