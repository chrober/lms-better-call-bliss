use strict;
use warnings;
use FindBin;
use Test::More tests => 17;

BEGIN {
    package Slim::Menu::PlaylistInfo;
    sub registerInfoProvider { }
    sub deregisterInfoProvider { }
    $INC{'Slim/Menu/PlaylistInfo.pm'} = __FILE__;

    package Slim::Menu::TrackInfo;
    sub registerInfoProvider { }
    sub deregisterInfoProvider { }
    $INC{'Slim/Menu/TrackInfo.pm'} = __FILE__;
}

use lib "$FindBin::Bin/..";
require Plugins::BetterCallBliss::ContextMenu;

{
    package TestPlaylist;
    sub new { return bless {}, $_[0] }
    sub id { return 123 }
    sub tracks { return 1 }
}

{
    package TestClient;
    sub new { return bless {}, $_[0] }
    sub id { return 'aa:bb:cc:dd:ee:ff' }
    sub name { return 'Schlafzimmer' }
}

{
    package TestTrack;
    sub new { return bless {}, $_[0] }
    sub remote { return 0 }
    sub id { return 456 }
}

my $playlist_item = Plugins::BetterCallBliss::ContextMenu::playlistInfoHandler(
    TestClient->new, undef, TestPlaylist->new,
);
ok($playlist_item, 'playlist context item is created');
is($playlist_item->{type}, 'text', 'playlist context uses generic weblink handling to avoid Material extra URL loss');
ok(exists $playlist_item->{weblink}, 'playlist context exposes a weblink');
ok(!exists $playlist_item->{url}, 'playlist context does not rely on the Material-only url field');
like($playlist_item->{title}, qr/Schlafzimmer/, 'playlist context title includes the player name');
like($playlist_item->{weblink}, qr{^plugins/BetterCallBliss/index\.html\?}, 'playlist context uses the relative plugin page URL');
like($playlist_item->{weblink}, qr{playlist_id=123}, 'playlist context preselects the playlist');
like($playlist_item->{weblink}, qr{source_mode=saved_playlist}, 'playlist context preselects saved playlist mode');
like($playlist_item->{weblink}, qr{player=aa%3Abb%3Acc%3Add%3Aee%3Aff}, 'playlist context preserves the active player for Material Extras rendering');

my $track_item = Plugins::BetterCallBliss::ContextMenu::trackInfoHandler(
    TestClient->new, undef, TestTrack->new,
);
ok($track_item, 'track context item is created');
is($track_item->{type}, 'text', 'track context uses generic weblink handling to avoid Material extra URL loss');
ok(exists $track_item->{weblink}, 'track context exposes a weblink');
like($track_item->{title}, qr/Schlafzimmer/, 'track context title includes the player name');
like($track_item->{weblink}, qr{source_mode=route_to_track}, 'track context preselects route-to-track mode');
like($track_item->{weblink}, qr{route_player_id=aa%3Abb%3Acc%3Add%3Aee%3Aff}, 'track context freezes the route player');
like($track_item->{weblink}, qr{route_target_track_id=456}, 'track context freezes the destination track');
like($track_item->{weblink}, qr{player=aa%3Abb%3Acc%3Add%3Aee%3Aff}, 'track context preserves the active player for Material Extras rendering');
