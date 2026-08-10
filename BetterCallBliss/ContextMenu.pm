package Plugins::BetterCallBliss::ContextMenu;

use strict;
use URI::Escape qw(uri_escape_utf8);
use Slim::Menu::PlaylistInfo;
use Slim::Menu::TrackInfo;

my $registered = 0;
my $page = 'plugins/BetterCallBliss/index.html';

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
    my ($client, $url, $playlist) = @_;
    return unless $playlist && $playlist->can('tracks') && $playlist->can('id');
    my $player_id = _client_id($client);
    return _web_item(
        'Better Call Bliss...',
        'Open Better Call Bliss with this saved playlist preselected.',
        _link(
            player => length $player_id ? $player_id : undef,
            source_mode => 'saved_playlist',
            playlist_id => 0 + $playlist->id,
        ),
        $client,
    );
}

sub trackInfoHandler {
    my ($client, $url, $track) = @_;
    return unless $client && $track && !$track->remote && $track->can('id');
    my $player_id = _client_id($client);
    return unless length $player_id;
    return _web_item(
        'Bliss me there...',
        'Preview a fluent bridge from the current queue tail to this track, then append the accepted route to the player queue.',
        _link(
            player => $player_id,
            source_mode => 'route_to_track',
            route_player_id => $player_id,
            route_target_track_id => 0 + $track->id,
            queue_player_id => $player_id,
            queue_action => 'append',
            output_mode => 'player_queue',
            ordering_policy => 'preserve_order',
            extension_mode => 'exact_count',
            additional_track_count => 1,
        ),
        $client,
    );
}

1;
