package Plugins::BlissEmAll::BlissCompatibility;

use strict;
use Slim::Music::Import;
use Slim::Utils::Misc;
use Slim::Utils::PluginManager;
use Slim::Utils::Prefs;

my $bliss_prefs = preferences('plugin.blissmixer');
my $server_prefs = preferences('server');
my $optimizer_binary;

sub init { $optimizer_binary = shift; }

sub snapshot {
    my $prefs_dir = Slim::Utils::Prefs::dir();
    my $database = $prefs_dir . '/bliss.db';
    my $matrix = $prefs_dir . '/learned_matrix.json';
    my $music_roots = Slim::Utils::Misc::getAudioDirs() || [];
    my $music_root = @$music_roots ? $music_roots->[0] : '';
    my $bliss_enabled =
        Slim::Utils::PluginManager->isEnabled('Plugins::BlissMixer::Plugin') ? 1 : 0;
    my $scanning = Slim::Music::Import->stillScanning() ? 1 : 0;

    my @problems;
    push @problems, 'BlissMixer is not enabled' unless $bliss_enabled;
    push @problems, 'bliss.db is missing or unreadable' unless -r $database;
    push @problems, 'learned_matrix.json is required by the bundled optimizer'
        unless -r $matrix;
    push @problems, 'bliss-playlist-optimizer is not installed'
        unless $optimizer_binary && -x $optimizer_binary;
    push @problems, 'the LMS library scan is still running' if $scanning;
    push @problems, 'the LMS music folder is not configured' unless $music_root;

    return {
        ready             => @problems ? 0 : 1,
        problems          => \@problems,
        bliss_enabled     => $bliss_enabled,
        database          => $database,
        matrix            => $matrix,
        matrix_available  => -r $matrix ? 1 : 0,
        optimizer_binary  => $optimizer_binary,
        scanning          => $scanning,
        music_root        => $music_root,
        music_roots       => $music_roots,
        seed_limit        => int($bliss_prefs->get('num_seed_tracks') || 3),
        learned_percent   => int($bliss_prefs->get('learned_blend') || 50),
        artist_window     => int($bliss_prefs->get('no_repeat_artist') || 0),
        album_window      => int($bliss_prefs->get('no_repeat_album') || 0),
        track_window      => int($bliss_prefs->get('no_repeat_track') || 0),
        algorithm         => 'adaptive',
    };
}

1;
