use strict;
use warnings;
use FindBin;
use Test::More tests => 9;
use JSON::XS ();

BEGIN {
    package Slim::Schema;
    our $playlist;
    sub find { return $playlist }
    $INC{'Slim/Schema.pm'} = __FILE__;

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
        };
    }
    $INC{'Plugins/BetterCallBliss/BlissCompatibility.pm'} = __FILE__;

    package Plugins::BetterCallBliss::CandidateInventory;
    sub database_file_for_track { return '/music/1999.flac' }
    $INC{'Plugins/BetterCallBliss/CandidateInventory.pm'} = __FILE__;

    package Plugins::BetterCallBliss::JobOptions;
    sub normalize {
        return {
            ordering_policy => 'preserve_order',
            extension_mode => 'exact_count',
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
            lastfm_weighting_weight => '25',
            max_added_tracks => '8',
            trigger_percent => '70',
            additional_track_count => '1',
            target_track_count => '25',
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
