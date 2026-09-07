package Plugins::BetterCallBliss::ContextMenu;

use strict;
use URI::Escape qw(uri_escape_utf8);
use Slim::Menu::AlbumInfo;
use Slim::Menu::PlaylistInfo;
use Slim::Menu::TrackInfo;

my $registered = 0;
my $album_registered = 0;
my $page = 'plugins/BetterCallBliss/index.html';

sub init {
    my $destination_blocks_supported = shift;
    return if $registered;
    Slim::Menu::PlaylistInfo->registerInfoProvider(
        bettercallbliss_playlist => (
            before => 'favorites',
            func => \&playlistInfoHandler,
        ),
    );
    Slim::Menu::TrackInfo->registerInfoProvider(
        bettercallbliss_route_to_now_playing => (
            before => 'favorites',
            func => \&trackNowPlayingInfoHandler,
        ),
    );
    Slim::Menu::TrackInfo->registerInfoProvider(
        bettercallbliss_route_round_trip => (
            after => 'bettercallbliss_route_to_now_playing',
            func => \&trackRoundTripInfoHandler,
        ),
    );
    Slim::Menu::TrackInfo->registerInfoProvider(
        bettercallbliss_route_to => (
            after => 'bettercallbliss_route_round_trip',
            func => \&trackInfoHandler,
        ),
    );
    if ($destination_blocks_supported) {
        Slim::Menu::AlbumInfo->registerInfoProvider(
            bettercallbliss_album_route_to_now_playing => (
                before => 'favorites',
                func => \&albumNowPlayingInfoHandler,
            ),
        );
        Slim::Menu::AlbumInfo->registerInfoProvider(
            bettercallbliss_album_route_round_trip => (
                after => 'bettercallbliss_album_route_to_now_playing',
                func => \&albumRoundTripInfoHandler,
            ),
        );
        Slim::Menu::AlbumInfo->registerInfoProvider(
            bettercallbliss_album_route_to => (
                after => 'bettercallbliss_album_route_round_trip',
                func => \&albumInfoHandler,
            ),
        );
        $album_registered = 1;
    }
    $registered = 1;
}

sub shutdown {
    return unless $registered;
    Slim::Menu::PlaylistInfo->deregisterInfoProvider('bettercallbliss_playlist');
    Slim::Menu::TrackInfo->deregisterInfoProvider('bettercallbliss_route_to');
    Slim::Menu::TrackInfo->deregisterInfoProvider(
        'bettercallbliss_route_to_now_playing',
    );
    Slim::Menu::TrackInfo->deregisterInfoProvider(
        'bettercallbliss_route_round_trip',
    );
    if ($album_registered) {
        Slim::Menu::AlbumInfo->deregisterInfoProvider(
            'bettercallbliss_album_route_to_now_playing',
        );
        Slim::Menu::AlbumInfo->deregisterInfoProvider(
            'bettercallbliss_album_route_round_trip',
        );
        Slim::Menu::AlbumInfo->deregisterInfoProvider(
            'bettercallbliss_album_route_to',
        );
        $album_registered = 0;
    }
    $registered = 0;
}

sub _link {
    my %params = @_;
    my @pairs;
    for my $name (sort keys %params) {
        next unless defined $params{$name};
        push @pairs, uri_escape_utf8($name) . '=' . uri_escape_utf8($params{$name});
    }
    return $page . (@pairs ? '?' . join('&', @pairs) : '');
}

sub _client_id {
    my ($client) = @_;
    return '' unless $client;
    return eval { $client->id } || '';
}

sub _client_name {
    my ($client) = @_;
    return '' unless $client;
    return eval { $client->name } || _client_id($client);
}

sub _title {
    my ($name, $client) = @_;
    my $client_name = _client_name($client);
    return length $client_name ? $name . ' ' . chr(0x2022) . ' ' . $client_name : $name;
}

sub _web_item {
    my ($name, $description, $href, $client) = @_;
    my $title = _title($name, $client);
    return {
        name => $name,
        title => $title,
        description => $description,
        type => 'text',
        weblink => $href,
        favorites => 0,
    };
}

sub playlistInfoHandler {
    my ($client, $url, $playlist, $remote_meta, $tags, $filter) = @_;
    return unless $playlist && $playlist->can('tracks') && $playlist->can('id');
    my $player_id = _client_id($client);
    return _web_item(
        'Better Call Bliss...',
        'Open Better Call Bliss with this saved playlist preselected.',
        _link(
            player => length $player_id ? $player_id : undef,
            source_mode => 'saved_playlist',
            playlist_id => 0 + $playlist->id,
            candidate_library_id => ref($filter) eq 'HASH'
                ? $filter->{library_id} : undef,
        ),
        $client,
    );
}

sub _destination_item {
    my ($client, $target_params, $name, $description, $route_source, $filter) = @_;
    return unless $client && ref($target_params) eq 'HASH';
    my $player_id = _client_id($client);
    return unless length $player_id;
    return {
        name => $name,
        title => _title($name, $client),
        description => $description,
        type => 'text',
        favorites => 0,
        jive => {
            actions => {
                go => {
                    player => 0,
                    cmd => ['bettercallbliss', 'route_to'],
                    params => {
                        %$target_params,
                        route_source => $route_source,
                        (ref($filter) eq 'HASH' && defined $filter->{library_id}
                            ? (candidate_library_id => $filter->{library_id}) : ()),
                    },
                    nextWindow => 'parent',
                },
            },
        },
    };
}

sub _route_item {
    my ($client, $track, $name, $description, $route_source, $filter) = @_;
    return unless $track && !$track->remote && $track->can('id');
    return _destination_item(
        $client,
        {target_track_id => 0 + $track->id},
        $name, $description, $route_source, $filter,
    );
}

sub _album_route_item {
    my ($client, $album, $name, $description, $route_source, $filter) = @_;
    return unless $album && $album->can('id');
    return _destination_item(
        $client,
        {target_album_id => 0 + $album->id},
        $name, $description, $route_source, $filter,
    );
}

sub trackInfoHandler {
    my ($client, $url, $track, $remote_meta, $tags, $filter) = @_;
    return _route_item(
        $client,
        $track,
        'Bliss me there... when we\'re through!',
        'Build a fluent route from the current queue end to this track and append it using the saved Bliss me there defaults.',
        'queue_end',
        $filter,
    );
}

sub trackNowPlayingInfoHandler {
    my ($client, $url, $track, $remote_meta, $tags, $filter) = @_;
    return _route_item(
        $client,
        $track,
        'Bliss me there...',
        'Keep the currently playing song and replace the upcoming queue with a fluent route to this track using the saved Bliss me there defaults.',
        'now_playing',
        $filter,
    );
}

sub trackRoundTripInfoHandler {
    my ($client, $url, $track, $remote_meta, $tags, $filter) = @_;
    return _route_item(
        $client,
        $track,
        'Bliss me there... and back again!',
        'Insert a fluent excursion from the currently playing song through this track and back to the existing upcoming queue.',
        'round_trip',
        $filter,
    );
}

sub albumInfoHandler {
    my ($client, $url, $album, $remote_meta, $tags, $filter) = @_;
    return _album_route_item(
        $client,
        $album,
        'Bliss me there... when we\'re through!',
        'Build a fluent route from the current queue end to this album, then append the complete album in disc and track order.',
        'queue_end',
        $filter,
    );
}

sub albumNowPlayingInfoHandler {
    my ($client, $url, $album, $remote_meta, $tags, $filter) = @_;
    return _album_route_item(
        $client,
        $album,
        'Bliss me there...',
        'Keep the currently playing song, replace the upcoming queue with a fluent route, then play this complete album in disc and track order.',
        'now_playing',
        $filter,
    );
}

sub albumRoundTripInfoHandler {
    my ($client, $url, $album, $remote_meta, $tags, $filter) = @_;
    return _album_route_item(
        $client,
        $album,
        'Bliss me there... and back again!',
        'Insert a fluent excursion through this complete album and back to the existing upcoming queue.',
        'round_trip',
        $filter,
    );
}

1;
