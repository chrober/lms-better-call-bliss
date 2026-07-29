package Plugins::BetterCallBliss::ContextMenu;

use strict;
use Slim::Menu::PlaylistInfo;
use Slim::Menu::TrackInfo;

my $registered = 0;

sub init {
    return if $registered;
    Slim::Menu::PlaylistInfo->registerInfoProvider(
        bettercallbliss_playlist => (
            before => 'favorites',
            func => \&playlistInfoHandler,
        ),
    );
    Slim::Menu::TrackInfo->registerInfoProvider(
        bettercallbliss_route_to => (
            before => 'favorites',
            func => \&trackInfoHandler,
        ),
    );
    $registered = 1;
}

sub shutdown {
    return unless $registered;
    Slim::Menu::PlaylistInfo->deregisterInfoProvider('bettercallbliss_playlist');
    Slim::Menu::TrackInfo->deregisterInfoProvider('bettercallbliss_route_to');
    $registered = 0;
}

sub playlistInfoHandler {
    my ($client, $url, $playlist) = @_;
    return unless $playlist && $playlist->can('tracks');
    return {
        name => "Better Call Bliss... [shortcut not connected yet]",
        description => "Use Extras > Better Call Bliss to select this playlist manually.",
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
