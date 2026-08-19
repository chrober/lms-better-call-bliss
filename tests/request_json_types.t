use strict;
use warnings;
use FindBin;
use Test::More tests => 31;
use JSON::XS ();

BEGIN {
    package Slim::Schema;
    our $playlist;
    sub find { return $playlist }
    $INC{'Slim/Schema.pm'} = __FILE__;

    package Slim::Player::Client;
    $INC{'Slim/Player/Client.pm'} = __FILE__;

    package Slim::Player::Playlist;
    $INC{'Slim/Player/Playlist.pm'} = __FILE__;

    package Slim::Player::Source;
    $INC{'Slim/Player/Source.pm'} = __FILE__;
    package Plugins::BetterCallBliss::BlissCompatibility;
    sub snapshot {
        return {
            ready => 1,
            problems => [],
            database => '/tmp/bliss-2026.db',
            matrix_available => 0,
            music_roots => ['/music'],
            seed_limit => '3',
            learned_percent => '20',
            artist_window => '5',
            album_window => '10',
            track_window => '100',
            use_adaptive_weights => 1,
            use_forest => 0,
            static_weight_sliders => {
                tempo => '25',
                timbre => '25',
                loudness => '25',
                chroma => '25',
            },
        };
    }
    $INC{'Plugins/BetterCallBliss/BlissCompatibility.pm'} = __FILE__;

    package Plugins::BetterCallBliss::CandidateInventory;
    sub database_file_for_track { return '/music/1999.flac' }
    $INC{'Plugins/BetterCallBliss/CandidateInventory.pm'} = __FILE__;

    package Plugins::BetterCallBliss::JobOptions;
    our $extension_mode = 'exact_count';
    our $additional_track_count = '1';
    our $bridge_target_track_count = '25';
    sub normalize {
        return {
            ordering_policy => 'preserve_order',
            extension_mode => $extension_mode,
            algorithm => 'adaptive',
            seed_limit => '3',
            learned_percent => '20',
            artist_window => '5',
            album_window => '10',
            track_window => '100',
            restart_count => '50',
            variation_percent => '25',
            generation_seed => '123456',
            generation_seed_supplied => 1,
            lastfm_enabled => 1,
            lastfm_track_guidance_percent => '75',
            lastfm_artist_guidance_percent => '75',
            max_added_tracks => '8',
            trigger_percent => '70',
            additional_track_count => $additional_track_count,
            bridge_target_track_count => $bridge_target_track_count,
            target_track_count => '25',
            route_length_policy => 'automatic',
            route_min_intermediates => '0',
            route_max_intermediates => '4',
            route_exact_intermediates => '2',
            route_search_effort => 'fast',
            output_mode => 'create_copy',
            output_name => '',
            output_name_generated => 0,
        };
    }
    $INC{'Plugins/BetterCallBliss/JobOptions.pm'} = __FILE__;
}

{
    package TestTrack;
    sub new { return bless {id => $_[1], title => $_[2]}, $_[0] }
    sub remote { return 0 }
    sub id { return $_[0]->{id} }
    sub artistName { return 'Numeric Artist' }
    sub title { return $_[0]->{title} }
    sub path { return '/music/' . $_[0]->{title} . '.flac' }
    sub albumname { return '1984' }
    sub url { return 'file:///music/' . $_[0]->{title} . '.flac' }
    sub musicbrainz_id { return undef }
    sub artist { return undef }
}

{
    package TestPlaylist;
    sub new { return bless {}, $_[0] }
    sub tracks {
        return (
            TestTrack->new(42, '1999'),
            TestTrack->new(43, '1234'),
        );
    }
    sub title { return 'Numeric titles' }
    sub name { return 'Numeric titles' }
}

$Slim::Schema::playlist = TestPlaylist->new();
use lib "$FindBin::Bin/..";
require Plugins::BetterCallBliss::RequestBuilder;

my $built = Plugins::BetterCallBliss::RequestBuilder::build_reorder_request(
    7, 'preview-json-types', '/tmp/semantic-evidence.json', {},
);
my $logged_shortlist = "$built->{request}->{extension}->{shortlist_limit}";
$built->{request}->{extension}->{allow_opening_track} = 0;
Plugins::BetterCallBliss::RequestBuilder::normalize_request_types(
    $built->{request},
);
my $json = JSON::XS->new->canonical->pretty->encode($built->{request});
my $request = JSON::XS->new->decode($json);

is($request->{extension}->{shortlist_limit}, 256, 'shortlist is numeric');
like(
    $json,
    qr/"shortlist_limit"\s*:\s*256\b/,
    'shortlist is serialized as a JSON integer',
);
unlike(
    $json,
    qr/"shortlist_limit"\s*:\s*"256"/,
    'shortlist is never serialized as a JSON string',
);
is($request->{selection}->{lastfm_track_guidance_percent}, 75,
    'track guidance is a JSON integer');
is($request->{selection}->{lastfm_artist_guidance_percent}, 75,
    'artist guidance is a JSON integer');
ok(
    JSON::XS::is_bool($request->{extension}->{allow_opening_track}),
    'opening flag remains a JSON boolean',
);
ok(
    !$request->{extension}->{allow_opening_track},
    'opening flag is false',
);
like(
    $json,
    qr/"allow_opening_track"\s*:\s*false\b/,
    'opening flag is serialized as JSON false',
);
ok(
    JSON::XS::is_bool($request->{output}->{include_private_paths}),
    'output flag remains a JSON boolean',
);
like(
    $json,
    qr/"title"\s*:\s*"1999"/,
    'digit-only track titles remain JSON strings',
);
like(
    $json,
    qr/"album"\s*:\s*"1984"/,
    'digit-only album names remain JSON strings',
);

$Plugins::BetterCallBliss::JobOptions::extension_mode = 'double_count';
$Plugins::BetterCallBliss::JobOptions::additional_track_count = '1';
$Plugins::BetterCallBliss::JobOptions::bridge_target_track_count = '25';
my $double = Plugins::BetterCallBliss::RequestBuilder::build_reorder_request(
    7, 'preview-json-types-double', '/tmp/semantic-evidence.json', {},
);
my $double_json = JSON::XS->new->canonical->pretty->encode($double->{request});
my $double_request = JSON::XS->new->decode($double_json);
is($double_request->{extension}->{mode}, 'exact_count',
    'double track count uses the native exact-count request');
is($double_request->{extension}->{additional_track_count}, 2,
    'double track count derives one addition per source track');
ok(JSON::XS::is_bool($double_request->{extension}->{allow_opening_track}),
    'double-count opening flag is a JSON boolean');
ok($double_request->{extension}->{allow_opening_track},
    'double-count enables an endpoint slot when internal gaps are insufficient');
like($double_json, qr/"allow_opening_track"\s*:\s*true\b/,
    'double-count opening flag is serialized as JSON true');
$Plugins::BetterCallBliss::JobOptions::extension_mode = 'destination_route';
my $destination = Plugins::BetterCallBliss::RequestBuilder::build_sequence_request(
    'Bliss me there test',
    [TestTrack->new(42, '1999'), TestTrack->new(43, '1234')],
    'preview-json-types-destination',
    '/tmp/semantic-evidence.json',
    {},
);
my $destination_json = JSON::XS->new->canonical->pretty->encode($destination->{request});
my $destination_request = JSON::XS->new->decode($destination_json);
is($destination_request->{route}->{ordering_policy}, 'queue_destination',
    'destination route uses its first-class locked ordering policy');
is($destination_request->{route}->{start_track_id}, 'lms-track-42',
    'destination route locks the queue-tail source track');
is($destination_request->{route}->{destination_track_id}, 'lms-track-43',
    'destination route locks the selected target track');
is($destination_request->{extension}->{mode}, 'destination_route',
    'destination route uses the dedicated native extension mode');
is($destination_request->{extension}->{destination_mode}, 'automatic',
    'destination route carries the automatic length policy');
is($destination_request->{extension}->{max_added_tracks}, 4,
    'destination maximum is serialized as a JSON integer');
is($destination_request->{extension}->{min_added_tracks}, 0,
    'destination minimum is serialized as a JSON integer');
is($destination_request->{extension}->{search_effort}, 'fast',
    'destination route carries its selected search effort');
is($destination_request->{extension}->{candidate_limit}, 6,
    'Fast destination search uses the bounded candidate width');
is($destination_request->{extension}->{shortlist_limit}, 128,
    'Fast destination search uses the bounded shortlist');
is($destination_request->{extension}->{trigger_percentile}, 0.7,
    'destination quality threshold is serialized as a JSON number');
is($destination_request->{selection}->{variation_percent}, 25,
    'destination route carries per-job variation');
is($destination_request->{selection}->{generation_seed}, 123456,
    'destination route carries its reproducible generation seed');
unlike($destination_json, qr/"max_added_tracks"\s*:\s*"4"/,
    'destination numeric fields are never serialized as strings');
unlike($destination_json, qr/"min_added_tracks"\s*:\s*"0"/,
    'destination minimum is never serialized as a string');
