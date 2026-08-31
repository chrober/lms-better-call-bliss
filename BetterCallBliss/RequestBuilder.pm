package Plugins::BetterCallBliss::RequestBuilder;

use strict;
use JSON::XS ();
use Scalar::Util qw(blessed);
use Slim::Schema;
use Slim::Player::Client;
use Slim::Player::Playlist;
use Slim::Player::Source;
use Plugins::BetterCallBliss::BlissCompatibility;
use Plugins::BetterCallBliss::CandidateInventory;
use Plugins::BetterCallBliss::CandidateLibrary;
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

sub _normalize_feature_weights {
    my $request = shift;
    return unless ref($request->{scoring}) eq 'HASH';
    return unless ref($request->{scoring}->{feature_weights}) eq 'ARRAY';
    my $index = 0;
    for my $weight (@{$request->{scoring}->{feature_weights}}) {
        $request->{scoring}->{feature_weights}->[$index] = _json_number(
            $weight, 'feature_weights[' . $index . ']',
        );
        $index++;
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
    _normalize_feature_weights($request);
    _normalize_integers(
        $request->{scoring}->{captured_blissmixer_preferences},
        qw(
            num_seed_tracks learned_blend no_repeat_artist
            no_repeat_album no_repeat_track weight_tempo weight_timbre
            weight_loudness weight_chroma
        ),
    );
    _normalize_booleans(
        $request->{scoring}->{captured_blissmixer_preferences},
        qw(
            use_adaptive_weights use_forest filter_genres filter_xmas
            match_all_genres use_track_genre
        ),
    );
    _normalize_booleans(
        $request->{candidate_policy}->{genre},
        qw(
            restrict_genres exclude_christmas match_all_genres
            use_track_genre
        ),
    );
    _normalize_integers(
        $request->{selection},
        qw(
            variation_percent generation_seed
            lastfm_track_guidance_percent lastfm_artist_guidance_percent
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

sub _queue_scope {
    my $scope = shift || 'full';
    die "Queue scope must be full queue, now-playing plus upcoming, or upcoming only"
        unless $scope eq 'full'
            || $scope eq 'current_and_upcoming'
            || $scope eq 'upcoming_only';
    return $scope;
}

sub _queue_client {
    my $player_id = shift || '';
    $player_id =~ s/^\s+|\s+$//g;
    die "Choose a player queue to use as input" unless length $player_id;
    my $client = Slim::Player::Client::getClient($player_id);
    die "The selected queue player is no longer connected" unless blessed($client);
    $client = $client->master if $client->can('master');
    return $client;
}

sub _queue_snapshot {
    my ($player_id, $scope) = @_;
    $scope = _queue_scope($scope);
    my $client = _queue_client($player_id);
    my $count = eval { Slim::Player::Playlist::count($client) } || 0;
    die "The selected player queue is empty" unless $count > 0;

    my $mode = eval { Slim::Player::Source::playmode($client) } || '';
    my $has_current = ($mode eq 'play' || $mode eq 'pause') ? 1 : 0;
    my $current = eval { Slim::Player::Source::playingSongIndex($client) };
    $current = 0 unless defined $current && "$current" =~ /^\d+$/;
    $current = 0 if $current < 0;
    $current = $count - 1 if $current >= $count;

    my $start = 0;
    if ($scope eq 'current_and_upcoming') {
        $start = $has_current ? $current : 0;
    } elsif ($scope eq 'upcoming_only') {
        $start = $has_current ? $current + 1 : 0;
    }
    die "The selected queue scope contains fewer than two upcoming local tracks"
        if $start >= $count;

    my @tracks;
    for my $index ($start .. $count - 1) {
        my $track = Slim::Player::Playlist::track($client, $index, 1, 0);
        die "Queue snapshot contains a stream or non-library item at position "
            . ($index + 1)
            unless $track && !$track->remote && $track->can('id');
        push @tracks, $track;
    }
    die "Queue snapshot requires at least two local tracks" unless @tracks >= 2;

    return {
        player_id => eval { $client->id } || $player_id,
        player_name => eval { $client->name } || $player_id,
        scope => $scope,
        queue_count => 0 + $count,
        current_index => 0 + $current,
        start_index => 0 + $start,
        active => $has_current,
        tracks => \@tracks,
        track_urls => [map { $_->url } @tracks],
        current_url => $has_current
            ? eval {
                my $track = Slim::Player::Playlist::track($client, $current, 1, 0);
                $track ? $track->url : undef;
            }
            : undef,
    };
}
sub _track_bundle {
    my ($tracks, $capability, $error_prefix, $minimum) = @_;
    $minimum = 2 unless defined $minimum;
    die "$error_prefix requires at least $minimum local tracks"
        unless ref($tracks) eq 'ARRAY' && @$tracks >= $minimum;

    my (@source_tracks, %labels, %original_positions, %track_urls);
    my $position = 0;
    for my $track (@$tracks) {
        die "$error_prefix contains a non-local item"
            unless $track && !$track->remote;
        die "$error_prefix contains a track without an LMS id"
            unless $track->can('id') && defined $track->id;
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

    return (\@source_tracks, \%labels, \%original_positions, \%track_urls);
}

sub _build_sequence_request {
    my ($args) = @_;
    my $job_id = $args->{job_id};
    my $semantic_path = $args->{semantic_path};
    my $job_input = $args->{job_input};
    my $tracks = $args->{tracks};
    my $title = $args->{title};
    my $playlist = $args->{playlist};
    my $error_prefix = $args->{error_prefix} || 'Source';
    my $route_rejoins_queue = $args->{route_rejoins_queue} ? 1 : 0;

    my $capability = Plugins::BetterCallBliss::BlissCompatibility::snapshot();
    die join('; ', @{$capability->{problems}}) unless $capability->{ready};
    my $options = Plugins::BetterCallBliss::JobOptions::normalize(
        $capability, $job_input,
    );
    my $candidate_library =
        Plugins::BetterCallBliss::CandidateLibrary::describe(
            $options->{candidate_library_id},
        );
    $options->{candidate_library_id} = $candidate_library->{id};
    $options->{candidate_library_name} = $candidate_library->{name};
    $options->{generation_seed} = _job_seed($job_id)
        unless defined $options->{generation_seed};

    my ($source_tracks, $labels, $original_positions, $track_urls)
        = _track_bundle($tracks, $capability, $error_prefix, 2);
    die "$error_prefix requires start, waypoint, and rejoin tracks"
        if $route_rejoins_queue && @$source_tracks < 3;
    my ($history_tracks, $history_labels, $history_positions, $history_urls)
        = _track_bundle($args->{history_tracks} || [], $capability,
            'Listening history', 0);
    $labels = {%$history_labels, %$labels};
    $track_urls = {%$history_urls, %$track_urls};
    my $source_count = scalar @$source_tracks;
    my $internal_gap_count = $source_count - 1;
    my $endpoint_capacity = 2;
    if (($options->{addition_purpose} || '') eq 'extend_playlist') {
        if (($options->{addition_amount_mode} || '') eq 'target_count') {
            die 'Target track count must exceed the source playlist size'
                if $options->{bridge_target_track_count} <= $source_count;
            $options->{target_track_count} = $options->{bridge_target_track_count};
            $options->{additional_track_count} =
                $options->{target_track_count} - $source_count;
        } elsif (($options->{addition_amount_mode} || '') eq 'double_count') {
            $options->{target_track_count} = 2 * $source_count;
            $options->{additional_track_count} = $source_count;
        } else {
            $options->{target_track_count} =
                $source_count + $options->{additional_track_count};
        }
        die 'Extended playlist final size must not exceed 500 tracks'
            if $options->{target_track_count} > 500;
        die 'Extend playlist target must exceed the source playlist size'
            if $options->{target_track_count} <= $source_count;
        $options->{extension_mode} = 'fixed_source_extension';
    }
    my $exact_like_extension = $options->{extension_mode} eq 'exact_count'
        || $options->{extension_mode} eq 'target_count'
        || $options->{extension_mode} eq 'double_count';
    if ($options->{extension_mode} eq 'target_count') {
        die 'Target track count must exceed the source playlist size'
            if $options->{bridge_target_track_count} <= $source_count;
        $options->{target_track_count} = $options->{bridge_target_track_count};
        $options->{additional_track_count} =
            $options->{target_track_count} - $source_count;
    } elsif ($options->{extension_mode} eq 'double_count') {
        $options->{target_track_count} = 2 * $source_count;
        $options->{additional_track_count} = $source_count;
    }
    if ($exact_like_extension) {
        my $maximum = $internal_gap_count;
        $maximum += $endpoint_capacity
            if $options->{extension_mode} eq 'target_count'
                || $options->{extension_mode} eq 'double_count';
        my $capacity_reason = $options->{extension_mode} eq 'exact_count'
            ? ' because Add exactly N uses one bridge per internal transition.'
            : ' with one bridge per internal transition plus opening/closing slots.';
        die 'The requested target needs ' . $options->{additional_track_count}
            . ($options->{additional_track_count} == 1 ? ' additional track' : ' additional tracks')
            . ', but this source currently supports at most ' . $maximum
            . ($maximum == 1 ? ' addition' : ' additions')
            . $capacity_reason
            . chr(10)
            if $options->{additional_track_count} > $maximum;
    }
    if ($options->{extension_mode} eq 'fixed_source_extension') {
        die 'Extend playlist target must exceed the source playlist size'
            if $options->{target_track_count} <= $source_count;
        die 'Extend playlist target must not exceed 500 tracks'
            if $options->{target_track_count} > 500;
    }

    my $artifacts = {
        database => {
            path => $capability->{database},
            schema_identity => 'TracksV2',
        },
    };
    $artifacts->{learned_matrix} = {path => $capability->{matrix}}
        if $capability->{matrix_available};

    my %adaptive_gap_context = $options->{algorithm} eq 'adaptive'
        ? (gap_context_mode => $options->{gap_context_mode}) : ();

    my $request = {
        schema_version => 1,
        job_id => $job_id,
        artifacts => $artifacts,
        source_tracks => $source_tracks,
        (@$history_tracks ? (history_tracks => $history_tracks) : ()),
        scoring => {
            algorithm => $options->{algorithm},
            adaptive => {
                seed_limit => _json_integer($options->{seed_limit}, 'seed_limit'),
                learned_percent => _json_integer(
                    $options->{learned_percent}, 'learned_percent',
                ),
            },
            feature_weights => [
                map { _json_number($_, 'feature_weight') }
                @{$capability->{feature_weights} || []}
            ],
            captured_blissmixer_preferences => {
                algorithm => $capability->{algorithm},
                use_adaptive_weights => $capability->{use_adaptive_weights}
                    ? JSON::XS::true : JSON::XS::false,
                use_forest => $capability->{use_forest}
                    ? JSON::XS::true : JSON::XS::false,
                filter_genres => $capability->{filter_genres}
                    ? JSON::XS::true : JSON::XS::false,
                filter_xmas => $capability->{filter_xmas}
                    ? JSON::XS::true : JSON::XS::false,
                genre_groups => $capability->{genre_groups} || [],
                match_all_genres => $capability->{match_all_genres}
                    ? JSON::XS::true : JSON::XS::false,
                use_track_genre => $capability->{use_track_genre}
                    ? JSON::XS::true : JSON::XS::false,
                num_seed_tracks => _json_integer($capability->{seed_limit}),
                learned_blend => _json_integer($capability->{learned_percent}),
                no_repeat_artist => _json_integer($capability->{artist_window}),
                no_repeat_album => _json_integer($capability->{album_window}),
                no_repeat_track => _json_integer($capability->{track_window}),
                weight_tempo => _json_integer(
                    $capability->{static_weight_sliders}->{tempo},
                ),
                weight_timbre => _json_integer(
                    $capability->{static_weight_sliders}->{timbre},
                ),
                weight_loudness => _json_integer(
                    $capability->{static_weight_sliders}->{loudness},
                ),
                weight_chroma => _json_integer(
                    $capability->{static_weight_sliders}->{chroma},
                ),
            },
        },
        candidate_policy => {
            genre => {
                restrict_genres => $capability->{filter_genres}
                    ? JSON::XS::true : JSON::XS::false,
                exclude_christmas => $capability->{exclude_christmas}
                    ? JSON::XS::true : JSON::XS::false,
                genre_groups => $capability->{genre_groups} || [],
                match_all_genres => $capability->{match_all_genres}
                    ? JSON::XS::true : JSON::XS::false,
                use_track_genre => $capability->{use_track_genre}
                    ? JSON::XS::true : JSON::XS::false,
            },
        },
        selection => {
            variation_percent => _json_integer(
                $options->{variation_percent}, 'variation_percent',
            ),
            generation_seed => _json_integer(
                $options->{generation_seed}, 'generation_seed',
            ),
            lastfm_track_guidance_percent => $options->{lastfm_enabled}
                && $options->{extension_mode} ne 'none'
                ? _json_integer($options->{lastfm_track_guidance_percent}) : 0,
            lastfm_artist_guidance_percent => $options->{lastfm_enabled}
                && $options->{extension_mode} ne 'none'
                ? _json_integer($options->{lastfm_artist_guidance_percent}) : 0,
        },
        route => {
            ordering_policy => $options->{extension_mode} eq 'destination_route'
                ? 'queue_destination' : $options->{ordering_policy},
            ($options->{extension_mode} eq 'destination_route' ? (
                start_track_id => $source_tracks->[
                    $route_rejoins_queue ? -3 : -2
                ]->{id},
                destination_track_id => $source_tracks->[
                    $route_rejoins_queue ? -2 : -1
                ]->{id},
                ($route_rejoins_queue ? (
                    rejoin_track_id => $source_tracks->[-1]->{id},
                ) : ()),
            ) : ()),
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
                %adaptive_gap_context,
                candidate_limit => _json_integer(5),
                shortlist_limit => _json_integer(256),
                max_added_tracks => _json_integer($options->{max_added_tracks}),
                trigger_percentile => $options->{trigger_percent} / 100,
            }
            : $exact_like_extension ? {
                mode => 'exact_count',
                %adaptive_gap_context,
                candidate_limit => _json_integer(5),
                shortlist_limit => _json_integer(256),
                max_tracks_per_gap => _json_integer(1),
                allow_opening_track => ($options->{extension_mode} ne 'exact_count'
                    && $options->{additional_track_count} > $internal_gap_count)
                    ? JSON::XS::true : JSON::XS::false,
                allow_closing_track => ($options->{extension_mode} ne 'exact_count'
                    && $options->{additional_track_count} > $internal_gap_count)
                    ? JSON::XS::true : JSON::XS::false,
                additional_track_count => _json_integer($options->{additional_track_count}),
            }
            : $options->{extension_mode} eq 'fixed_source_extension' ? {
                mode => 'fixed_source_extension',
                shortlist_limit => _json_integer(256),
                target_track_count => _json_integer($options->{target_track_count}),
            }
            : $options->{extension_mode} eq 'destination_route' ? {
                mode => 'destination_route',
                destination_mode => $options->{route_length_policy},
                search_effort => $options->{route_search_effort},
                ($options->{route_length_policy} eq 'automatic' ? (
                    direct_transition_caution => $options->{route_direct_caution},
                ) : ()),
                candidate_limit => _json_integer(
                    $options->{route_search_effort} eq 'thorough' ? 16
                        : $options->{route_search_effort} eq 'balanced' ? 8 : 6,
                ),
                shortlist_limit => _json_integer(
                    $options->{route_search_effort} eq 'thorough' ? 512
                        : $options->{route_search_effort} eq 'balanced' ? 256 : 128,
                ),
                max_added_tracks => _json_integer(
                    $options->{route_length_policy} eq 'exact'
                        ? $options->{route_exact_intermediates}
                        : $options->{route_max_intermediates},
                ),
                ($options->{route_length_policy} eq 'automatic' ? (
                    min_added_tracks => _json_integer(
                        $options->{route_min_intermediates},
                    ),
                ) : ()),
                trigger_percentile => $options->{trigger_percent} / 100,
                ($options->{route_length_policy} eq 'exact' ? (
                    additional_track_count => _json_integer(
                        $options->{route_exact_intermediates},
                    ),
                ) : ()),
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
        playlist_title => $title,
        labels => $labels,
        original_positions => $original_positions,
        track_urls => $track_urls,
        capability => $capability,
        history_track_ids => [map { $_->{id} } @$history_tracks],
        options => $options,
        candidate_library => $candidate_library,
    };
}

sub build_sequence_request {
    my ($title, $tracks, $job_id, $semantic_path, $job_input, $history_tracks,
        $route_rejoins_queue) = @_;
    return _build_sequence_request({
        title => $title,
        tracks => $tracks,
        job_id => $job_id,
        semantic_path => $semantic_path,
        history_tracks => $history_tracks,
        route_rejoins_queue => $route_rejoins_queue,
        job_input => $job_input,
        error_prefix => $title || 'Source',
    });
}

sub build_queue_request {
    my ($player_id, $scope, $job_id, $semantic_path, $job_input) = @_;
    my $snapshot = _queue_snapshot($player_id, $scope);
    my $title = 'Queue snapshot: ' . $snapshot->{player_name};
    $title .= ' (' . $snapshot->{scope} . ')';
    my $built = _build_sequence_request({
        title => $title,
        tracks => $snapshot->{tracks},
        job_id => $job_id,
        semantic_path => $semantic_path,
        job_input => $job_input,
        error_prefix => 'Queue snapshot',
    });
    $built->{queue_snapshot} = $snapshot;
    return $built;
}
sub build_reorder_request {
    my ($playlist_id, $job_id, $semantic_path, $job_input) = @_;
    my $playlist = Slim::Schema->find('Playlist', $playlist_id);
    die "Saved playlist not found" unless $playlist && $playlist->can('tracks');
    my @tracks = $playlist->tracks;
    die "At least two local tracks are required" unless @tracks >= 2;
    return _build_sequence_request({
        playlist => $playlist,
        title => undef,
        tracks => \@tracks,
        job_id => $job_id,
        semantic_path => $semantic_path,
        job_input => $job_input,
        error_prefix => 'Playlist',
    });
}

1;
