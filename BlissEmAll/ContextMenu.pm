package Plugins::BlissEmAll::ContextMenu;

use strict;
use Slim::Menu::PlaylistInfo;
use Slim::Menu::TrackInfo;

my $registered = 0;

sub init {
    return if $registered;
    Slim::Menu::PlaylistInfo->registerInfoProvider(
        blissemall_playlist => (
            before => 'favorites',
            func => \&playlistInfoHandler,
        ),
    );
    Slim::Menu::TrackInfo->registerInfoProvider(
        blissemall_route_to => (
            before => 'favorites',
            func => \&trackInfoHandler,
        ),
    );
    $registered = 1;
}

sub shutdown {
    return unless $registered;
    Slim::Menu::PlaylistInfo->deregisterInfoProvider('blissemall_playlist');
    Slim::Menu::TrackInfo->deregisterInfoProvider('blissemall_route_to');
    $registered = 0;
}

sub playlistInfoHandler {
    my ($client, $url, $playlist) = @_;
    return unless $playlist && $playlist->can('tracks');
    return {
        name => "Bliss 'Em All... [shortcut not connected yet]",
        description => "Use Extras > Bliss 'Em All to select this playlist manually.",
        type => 'text',
        favorites => 0,
    };
}

sub trackInfoHandler {
    my ($client, $url, $track) = @_;
    return unless $track && !$track->remote;
    return {
        name => 'Bliss me there... [not connected yet]',
        description => 'Planned: preview a fluent route from the selected queue tail to this track.',
        type => 'text',
        favorites => 0,
    };
}

1;
