package Plugins::BetterCallBliss::BlissCompatibility;

use strict;
use Slim::Music::Import;
use Slim::Utils::Misc;
use Slim::Utils::PluginManager;
use Slim::Utils::Prefs;

my $bliss_prefs = preferences('plugin.blissmixer');
my $server_prefs = preferences('server');
my $optimizer_binary;
my $optimizer_supports_genre_policy;
my $optimizer_supports_candidate_library_scope;

sub init {
    $optimizer_binary = shift;
    $optimizer_supports_genre_policy = shift ? 1 : 0;
    $optimizer_supports_candidate_library_scope = shift ? 1 : 0;
}

sub _int_pref {
    my ($name, $fallback) = @_;
    my $value = $bliss_prefs->get($name);
    $value = $fallback unless defined $value;
    return int($value);
}

sub _genre_groups {
    my $configured = $bliss_prefs->get('genre_groups') || '';
    my @groups;
    for my $line (split /\n/, $configured) {
        my @patterns;
        for my $pattern (split /;/, $line) {
            $pattern =~ s/^\s+|\s+$//g;
            push @patterns, $pattern if length $pattern;
        }
        push @groups, \@patterns if @patterns;
    }
    return \@groups;
}

sub _strategy_from_prefs {
    return 'adaptive' if _int_pref('use_adaptive_weights', 0);
    return 'forest' if _int_pref('use_forest', 0);
    return 'static';
}

sub _static_slider_weights {
    my %weights = (
        tempo    => _int_pref('weight_tempo', 4),
        timbre   => _int_pref('weight_timbre', 30),
        loudness => _int_pref('weight_loudness', 9),
        chroma   => _int_pref('weight_chroma', 57),
    );
    my $total = $weights{tempo} + $weights{timbre}
        + $weights{loudness} + $weights{chroma};
    if ($total <= 0) {
        %weights = (tempo => 4, timbre => 30, loudness => 9, chroma => 57);
        $total = 100;
    }
    return {
        raw => {%weights},
        expanded => [
            ((($weights{tempo} / $total) * 100.0) / 4.0),
            (((($weights{timbre} / $total) * 100.0) / 30.0)) x 7,
            (((($weights{loudness} / $total) * 100.0) / 9.0)) x 2,
            (((($weights{chroma} / $total) * 100.0) / 57.0)) x 13,
        ],
    };
}

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
    push @problems, 'bliss-playlist-optimizer is not installed'
        unless $optimizer_binary && -x $optimizer_binary;
    push @problems,
        'the installed bliss-playlist-optimizer does not support BlissMixer genre settings'
        if $optimizer_binary && -x $optimizer_binary
            && !$optimizer_supports_genre_policy;
    push @problems,
        'the installed bliss-playlist-optimizer does not support candidate-library scoping'
        if $optimizer_binary && -x $optimizer_binary
            && !$optimizer_supports_candidate_library_scope;
    push @problems,
        'an LMS library scan is updating the catalog; preview will resume when it finishes'
        if $scanning;
    push @problems, 'the LMS music folder is not configured' unless $music_root;

    my $strategy = _strategy_from_prefs();
    my $static_weights = _static_slider_weights();
    my $filter_xmas = _int_pref('filter_xmas', 1) ? 1 : 0;
    my $month = (localtime())[4] + 1;

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
        seed_limit        => _int_pref('num_seed_tracks', 3),
        learned_percent   => _int_pref('learned_blend', 50),
        artist_window     => _int_pref('no_repeat_artist', 0),
        album_window      => _int_pref('no_repeat_album', 0),
        track_window      => _int_pref('no_repeat_track', 0),
        algorithm         => $strategy,
        use_adaptive_weights => _int_pref('use_adaptive_weights', 0) ? 1 : 0,
        use_forest        => _int_pref('use_forest', 0) ? 1 : 0,
        static_weight_sliders => $static_weights->{raw},
        feature_weights   => $static_weights->{expanded},
        filter_genres     => _int_pref('filter_genres', 0) ? 1 : 0,
        filter_xmas       => $filter_xmas,
        exclude_christmas => $filter_xmas && $month != 12 ? 1 : 0,
        genre_groups      => _genre_groups(),
        match_all_genres  => _int_pref('match_all_genres', 0) ? 1 : 0,
        use_track_genre   => _int_pref('use_track_genre', 0) ? 1 : 0,
    };
}

1;
