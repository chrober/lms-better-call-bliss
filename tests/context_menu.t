use strict;
use warnings;
use FindBin;
use Test::More tests => 42;

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
    TestClient->new, undef, TestPlaylist->new, undef, undef,
    {library_id => '4d2ba37f'},
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
like($playlist_item->{weblink}, qr{candidate_library_id=4d2ba37f},
    'playlist context freezes the active virtual library');

my $track_item = Plugins::BetterCallBliss::ContextMenu::trackInfoHandler(
    TestClient->new, undef, TestTrack->new, undef, undef,
    {library_id => '4d2ba37f'},
);
ok($track_item, 'track context item is created');
is($track_item->{type}, 'text', 'track context invokes a non-browsing LMS action');
ok(!exists $track_item->{weblink}, 'track context does not navigate to the Extras page');
like($track_item->{title}, qr/Schlafzimmer/, 'track context title includes the player name');
ok($track_item->{jive}->{actions}->{go}, 'track context exposes a Jive go action');
is($track_item->{jive}->{actions}->{go}->{player}, 0, 'direct action targets the selected player');
is($track_item->{jive}->{actions}->{go}->{nextWindow}, 'parent', 'completed command returns to the existing context view');
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
is(
    $track_item->{jive}->{actions}->{go}->{params}->{route_source},
    'queue_end',
    'deferred destination action explicitly starts at the queue end',
);
is($track_item->{jive}->{actions}->{go}->{params}->{candidate_library_id},
    '4d2ba37f', 'direct destination action freezes the active virtual library');
is($track_item->{name}, 'Bliss me there... when we\'re through!',
    'queue-end action explains that it runs after the existing queue');
ok(
    !exists $track_item->{jive}->{actions}->{go}->{params}->{source_mode},
    'direct action does not carry obsolete web-preview parameters',
);
like(
    $track_item->{description},
    qr/append/i,
    'track context explains that the completed route is appended automatically',
);

my $now_item = Plugins::BetterCallBliss::ContextMenu::trackNowPlayingInfoHandler(
    TestClient->new, undef, TestTrack->new,
);
ok($now_item, 'now-playing track context item is created alongside the standard action');
is(
    $now_item->{name},
    'Bliss me there...',
    'now-playing action owns the concise primary label',
);
like($now_item->{title}, qr/Schlafzimmer/, 'now-playing title includes the player name');
ok($now_item->{jive}->{actions}->{go}, 'now-playing context exposes a Jive go action');
is_deeply(
    $now_item->{jive}->{actions}->{go}->{cmd},
    ['bettercallbliss', 'route_to'],
    'both destination actions share the route command',
);
is(
    $now_item->{jive}->{actions}->{go}->{params}->{target_track_id},
    456,
    'now-playing action freezes the same destination track',
);
is(
    $now_item->{jive}->{actions}->{go}->{params}->{route_source},
    'now_playing',
    'now-playing action selects the current song as route source',
);
is(
    $now_item->{jive}->{actions}->{go}->{nextWindow},
    'parent',
    'now-playing command returns to the existing context view',
);
like(
    $now_item->{description},
    qr/replace the upcoming queue/i,
    'now-playing action discloses its queue replacement behavior',
);

my $round_item = Plugins::BetterCallBliss::ContextMenu::trackRoundTripInfoHandler(
    TestClient->new, undef, TestTrack->new,
);
ok($round_item, 'round-trip track context item is created alongside both direct routes');
is($round_item->{name}, 'Bliss me there... and back again!',
    'round-trip action has its own menu label');
like($round_item->{title}, qr/Schlafzimmer/, 'round-trip title includes the player name');
ok($round_item->{jive}->{actions}->{go}, 'round-trip context exposes a Jive go action');
is_deeply($round_item->{jive}->{actions}->{go}->{cmd},
    ['bettercallbliss', 'route_to'], 'round-trip action shares the route command');
is($round_item->{jive}->{actions}->{go}->{params}->{target_track_id}, 456,
    'round-trip action freezes the selected waypoint');
is($round_item->{jive}->{actions}->{go}->{params}->{route_source}, 'round_trip',
    'round-trip action selects current-to-upcoming excursion semantics');
is($round_item->{jive}->{actions}->{go}->{nextWindow}, 'parent',
    'round-trip command returns to the existing context view');
like($round_item->{description}, qr/back to the existing upcoming queue/i,
    'round-trip action explains that the existing queue is preserved');
