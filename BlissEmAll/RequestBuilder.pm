package Plugins::BlissEmAll::RequestBuilder;

use strict;
use JSON::XS ();
use Slim::Schema;
use Slim::Utils::Unicode;
use Plugins::BlissEmAll::BlissCompatibility;
use Plugins::BlissEmAll::JobOptions;

sub _database_file {
    my ($track, $roots) = @_;
    my $path = $track->path;
    $path =~ s{\\}{/}g;
    for my $configured_root (sort { length($b) <=> length($a) } @$roots) {
        my $root = $configured_root;
        $root =~ s{\\}{/}g;
        $root =~ s{/+$}{};
        if (index($path, $root . '/') == 0) {
            my $relative = substr($path, length($root) + 1);
            $relative = Slim::Utils::Unicode::utf8decode_locale($relative);
            my @url_parts = split(/#/, $track->url);
            $relative .= '.CUE_TRACK.' . $track->tracknum
                if @url_parts == 2;
            return $relative;
        }
    }
    die "Track is outside the configured music folders";
}

sub build_reorder_request {
    my ($playlist_id, $job_id, $semantic_path, $job_input) = @_;
    my $capability = Plugins::BlissEmAll::BlissCompatibility::snapshot();
    die join('; ', @{$capability->{problems}}) unless $capability->{ready};
    my $options = Plugins::BlissEmAll::JobOptions::normalize(
        $capability, $job_input,
    );

    my $playlist = Slim::Schema->find('Playlist', $playlist_id);
    die "Saved playlist not found" unless $playlist && $playlist->can('tracks');
    my @tracks = $playlist->tracks;
    die "At least two local tracks are required" unless @tracks >= 2;

    my (@source_tracks, %labels, %original_positions, %track_urls);
    my $position = 0;
    for my $track (@tracks) {
        die "Playlist contains a non-local item" unless $track && !$track->remote;
        my $id = 'lms-track-' . $track->id;
        my $artist = $track->artistName || 'Unknown Artist';
        my $title = $track->title || $track->path;
        my $album = $track->albumname || '';
        push @source_tracks, {
            id            => $id,
            lms_url       => $track->url,
            database_file => _database_file($track, $capability->{music_roots}),
            title         => $title,
            artist        => $artist,
            album         => $album,
        };
        $labels{$id} = {artist => $artist, title => $title, album => $album};
        $original_positions{$id} = ++$position;
        $track_urls{$id} = $track->url;
    }

    if ($options->{extension_mode} eq 'exact_count') {
        my $maximum = @tracks - 1;
        die 'Add exactly N tracks supports at most ' . $maximum
            . ($maximum == 1 ? ' additional track' : ' additional tracks')
            . ' for this playlist because the current workflow permits one '
            . 'addition per internal optimized transition.' . chr(10)
            if $options->{additional_track_count} > $maximum;
    }

    my $artifacts = {
        database => {
            path => $capability->{database},
            schema_identity => 'TracksV2',
        },
    };
    $artifacts->{learned_matrix} = {path => $capability->{matrix}}
        if $capability->{matrix_available};

    my $request = {
        schema_version => 1,
        job_id => $job_id,
        artifacts => $artifacts,
        source_tracks => \@source_tracks,
        scoring => {
            algorithm => $options->{algorithm},
            adaptive => {
                seed_limit => $options->{seed_limit},
                learned_percent => $options->{learned_percent},
            },
            captured_blissmixer_preferences => {
                use_adaptive_weights => 1,
                num_seed_tracks => $capability->{seed_limit},
                learned_blend => $capability->{learned_percent},
                no_repeat_artist => $capability->{artist_window},
                no_repeat_album => $capability->{album_window},
                no_repeat_track => $capability->{track_window},
            },
        },
        route => {
            ordering_policy => $options->{ordering_policy},
            objective => 'bottleneck_then_sum',
            search => {
                deterministic_seed => 20260721,
                restart_count => $options->{restart_count},
            },
        },
        repeat_windows => {
            artist => $options->{artist_window},
            album => $options->{album_window},
            track => $options->{track_window},
        },
        extension => $options->{extension_mode} eq 'automatic' ? {
                mode => 'automatic',
                candidate_limit => 5,
                shortlist_limit => 256,
                max_added_tracks => $options->{max_added_tracks},
                trigger_percentile => $options->{trigger_percent} / 100,
            }
            : $options->{extension_mode} eq 'exact_count' ? {
                mode => 'exact_count',
                candidate_limit => 5,
                shortlist_limit => 256,
                max_tracks_per_gap => 1,
                allow_opening_track => JSON::XS::false,
                allow_closing_track => JSON::XS::false,
                additional_track_count => $options->{additional_track_count},
            }
            : {mode => 'none'},
        semantic_evidence => {
            path => $semantic_path,
            schema_identity => 'semantic-evidence-v1',
        },
        output => {
            include_private_paths => JSON::XS::false,
            include_rejected_candidates => JSON::XS::false,
        },
    };

    return {
        request => $request,
        playlist => $playlist,
        labels => \%labels,
        original_positions => \%original_positions,
        track_urls => \%track_urls,
        capability => $capability,
        options => $options,
    };
}

1;
