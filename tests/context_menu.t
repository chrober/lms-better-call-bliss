use strict;
use warnings;
use FindBin;
use Test::More tests => 19;

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
is($track_item->{type}, 'redirect', 'track context invokes a direct LMS action');
ok(!exists $track_item->{weblink}, 'track context does not navigate to the Extras page');
like($track_item->{title}, qr/Schlafzimmer/, 'track context title includes the player name');
ok($track_item->{jive}->{actions}->{go}, 'track context exposes a Jive go action');
is($track_item->{jive}->{actions}->{go}->{player}, 0, 'direct action targets the selected player');
is_deeply(
    $track_item->{jive}->{actions}->{go}->{cmd},
    ['bettercallbliss', 'route_to'],
    'direct action invokes the Better Call Bliss destination command',
);
is(
    $track_item->{jive}->{actions}->{go}->{params}->{target_track_id},
    456,
    'direct action freezes the destination track',
);
ok(
    !exists $track_item->{jive}->{actions}->{go}->{params}->{source_mode},
    'direct action does not carry obsolete web-preview parameters',
);
like(
    $track_item->{description},
    qr/append/i,
    'track context explains that the completed route is appended automatically',
);