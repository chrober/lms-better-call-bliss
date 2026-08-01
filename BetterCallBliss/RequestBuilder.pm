package Plugins::BetterCallBliss::RequestBuilder;

use strict;
use JSON::XS ();
use Slim::Schema;
use Plugins::BetterCallBliss::BlissCompatibility;
use Plugins::BetterCallBliss::CandidateInventory;
use Plugins::BetterCallBliss::JobOptions;

sub _job_seed {
    my $job_id = shift;
    my $hash = 2166136261;
    for my $byte (unpack('C*', $job_id || '')) {
        $hash ^= $byte;
        $hash = ($hash * 16777619) % 4294967296;
    }
    return $hash;
}

sub _database_file {
    my ($track, $roots) = @_;
    my $database_file =
        Plugins::BetterCallBliss::CandidateInventory::database_file_for_track(
            $track, $roots,
        );
    die "Track is outside the configured music folders"
        unless defined $database_file;
    return $database_file;
}

sub _json_integer {
    my ($value, $name) = @_;
    $name ||= 'JSON integer';
    die "$name is missing" unless defined $value;
    die "$name must be an integer"
        if ref($value) || "$value" !~ /^-?\d+$/;
    return int($value);
}

sub _json_number {
    my ($value, $name) = @_;
    $name ||= 'JSON number';
    die "$name is missing" unless defined $value;
    die "$name must be a number"
        if ref($value)
            || "$value" !~ /^-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/;
    return 0.0 + $value;
}

sub _normalize_integers {
    my ($object, @names) = @_;
    return unless ref($object) eq 'HASH';
    for my $name (@names) {
        $object->{$name} = _json_integer($object->{$name}, $name)
            if defined $object->{$name};
    }
}

sub _normalize_booleans {
    my ($object, @names) = @_;
    return unless ref($object) eq 'HASH';
    for my $name (@names) {
        next unless exists $object->{$name};
        $object->{$name} = $object->{$name}
            ? JSON::XS::true : JSON::XS::false;
    }
}

sub normalize_request_types {
    my $request = shift;
    die 'Optimizer request must be an object'
        unless ref($request) eq 'HASH';

    _normalize_integers($request, 'schema_version');
    _normalize_integers(
        $request->{scoring}->{adaptive},
        qw(seed_limit learned_percent),
    );
    _normalize_integers(
        $request->{scoring}->{captured_blissmixer_preferences},
        qw(
            num_seed_tracks learned_blend no_repeat_artist
            no_repeat_album no_repeat_track
        ),
    );
    _normalize_booleans(
        $request->{scoring}->{captured_blissmixer_preferences},
        'use_adaptive_weights',
    );
    _normalize_integers(
        $request->{selection},
        qw(
            variation_percent generation_seed
            lastfm_artist_probability
        ),
    );
    _normalize_integers(
        $request->{route}->{search},
        qw(
            deterministic_seed restart_count candidate_limit
            time_budget_ms
        ),
    );
    _normalize_integers(
        $request->{repeat_windows},
        qw(artist album track),
    );
    _normalize_integers(
        $request->{extension},
        qw(
            additional_track_count target_track_count candidate_limit
            max_tracks_per_gap max_added_tracks shortlist_limit
        ),
    );
    if (defined $request->{extension}->{trigger_percentile}) {
        $request->{extension}->{trigger_percentile} = _json_number(
            $request->{extension}->{trigger_percentile},
            'trigger_percentile',
        );
    }
    _normalize_booleans(
        $request->{extension},
        qw(allow_opening_track allow_closing_track),
    );
    _normalize_integers(
        $request->{output},
        'max_rejected_candidates',
    );
    _normalize_booleans(
        $request->{output},
        qw(include_private_paths include_rejected_candidates),
    );
    return $request;
}

sub build_reorder_request {
    my ($playlist_id, $job_id, $semantic_path, $job_input) = @_;
    my $capability = Plugins::BetterCallBliss::BlissCompatibility::snapshot();
    die join('; ', @{$capability->{problems}}) unless $capability->{ready};
    my $options = Plugins::BetterCallBliss::JobOptions::normalize(
        $capability, $job_input,
    );
    $options->{generation_seed} = _job_seed($job_id)
        unless defined $options->{generation_seed};

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
        my $recording_mbid = eval { $track->musicbrainz_id } || undef;
        my $artist_mbid = eval {
            $track->artist ? $track->artist->musicbrainz_id : undef
        } || undef;
        push @source_tracks, {
            id            => $id,
            lms_url       => $track->url,
            database_file => _database_file($track, $capability->{music_roots}),
            title         => $title,
            artist        => $artist,
            album         => $album,
            (defined $recording_mbid ? (recording_mbid => $recording_mbid) : ()),
            artist_mbids => defined $artist_mbid ? [$artist_mbid] : [],
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
            . 'addition per internal source-track transition.' . chr(10)
            if $options->{additional_track_count} > $maximum;
    }
    if ($options->{extension_mode} eq 'seed_growth') {
        die 'Grow from these seeds target must exceed the source playlist size'
            if $options->{target_track_count} <= @tracks;
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
                seed_limit => _json_integer($options->{seed_limit}, 'seed_limit'),
                learned_percent => _json_integer(
                    $options->{learned_percent}, 'learned_percent',
                ),
            },
            captured_blissmixer_preferences => {
                use_adaptive_weights => JSON::XS::true,
                num_seed_tracks => _json_integer($capability->{seed_limit}),
                learned_blend => _json_integer($capability->{learned_percent}),
                no_repeat_artist => _json_integer($capability->{artist_window}),
                no_repeat_album => _json_integer($capability->{album_window}),
                no_repeat_track => _json_integer($capability->{track_window}),
            },
        },
        selection => {
            variation_percent => _json_integer(
                $options->{variation_percent}, 'variation_percent',
            ),
            generation_seed => _json_integer(
                $options->{generation_seed}, 'generation_seed',
            ),
            lastfm_artist_probability => $options->{lastfm_enabled}
                && $options->{extension_mode} ne 'none'
                ? _json_integer($options->{lastfm_weighting_weight}) : 0,
        },
        route => {
            ordering_policy => $options->{ordering_policy},
            objective => 'bottleneck_then_sum',
            search => {
                deterministic_seed => $options->{variation_percent} > 0
                    ? _json_integer($options->{generation_seed}) : 20260721,
                restart_count => _json_integer($options->{restart_count}),
            },
        },
        repeat_windows => {
            artist => _json_integer($options->{artist_window}),
            album => _json_integer($options->{album_window}),
            track => _json_integer($options->{track_window}),
        },
        extension => $options->{extension_mode} eq 'automatic' ? {
                mode => 'automatic',
                candidate_limit => _json_integer(5),
                shortlist_limit => _json_integer(256),
                max_added_tracks => _json_integer($options->{max_added_tracks}),
                trigger_percentile => $options->{trigger_percent} / 100,
            }
            : $options->{extension_mode} eq 'exact_count' ? {
                mode => 'exact_count',
                candidate_limit => _json_integer(5),
                shortlist_limit => _json_integer(256),
                max_tracks_per_gap => _json_integer(1),
                allow_opening_track => JSON::XS::false,
                allow_closing_track => JSON::XS::false,
                additional_track_count => _json_integer($options->{additional_track_count}),
            }
            : $options->{extension_mode} eq 'seed_growth' ? {
                mode => 'seed_growth',
                shortlist_limit => _json_integer(256),
                target_track_count => _json_integer($options->{target_track_count}),
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
    normalize_request_types($request);

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
