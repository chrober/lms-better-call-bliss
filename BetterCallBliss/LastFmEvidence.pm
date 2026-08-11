package Plugins::BetterCallBliss::LastFmEvidence;

use strict;
use POSIX qw(strftime);
use Slim::Utils::Log;
use Slim::Utils::PluginManager;

my $log = Slim::Utils::Log::logger('plugin.bettercallbliss');
use constant MAX_SIMILAR_RESULTS => 25;

sub available {
    return 0 unless Slim::Utils::PluginManager->isEnabled(
        'Plugins::LastMix::Plugin'
    );
    return 1 if exists $INC{'Plugins/LastMix/LFM.pm'};
    return eval { require Plugins::LastMix::LFM; 1 } ? 1 : 0;
}

sub _timestamp {
    return strftime('%Y-%m-%dT%H:%M:%SZ', gmtime(time()));
}

sub _valid_mbid {
    my $value = shift || '';
    return $value =~ /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
        ? lc($value) : undef;
}

sub _normalize_text {
    my $value = lc(shift || '');
    $value =~ s/^\s+|\s+$//g;
    $value =~ s/\s+/ /g;
    return $value;
}

sub _service_wide_error {
    my $code = shift;
    return defined $code && "$code" =~ /^(?:11|16|29)$/;
}

sub _artist_entity {
    my ($name, $mbid) = @_;
    my $normalized = _normalize_text($name);
    my $entity = {
        kind => 'artist',
        id => 'artist:' . $normalized,
        name => $name,
    };
    my $valid_mbid = _valid_mbid($mbid);
    $entity->{mbid} = $valid_mbid if $valid_mbid;
    return $entity;
}

sub _recording_entity {
    my ($id, $artist, $title, $mbid) = @_;
    my $entity = {
        kind => 'recording',
        id => $id || 'recording:' . _normalize_text($artist)
            . '|' . _normalize_text($title),
        name => $artist,
        title => $title,
    };
    my $valid_mbid = _valid_mbid($mbid);
    $entity->{mbid} = $valid_mbid if $valid_mbid;
    return $entity;
}

sub _bundle {
    my ($state, $requests, $failures, $errors, $edges) = @_;
    return {
        schema_version => 1,
        frozen_at => _timestamp(),
        providers => [{
            provider => 'last.fm',
            dataset_or_algorithm =>
                'LastMix track.getSimilar + artist.getSimilar',
            state => $state,
            request_count => 0 + ($requests || 0),
            failure_count => 0 + ($failures || 0),
            error_codes => $errors || [],
        }],
        edges => $edges || [],
    };
}

sub _error_code {
    my $result = shift;
    my $raw_code = ref($result) eq 'HASH' ? $result->{error} : undef;
    return ($raw_code, $raw_code ? 'LASTFM_' . $raw_code : 'LASTFM_NO_RESULT');
}

sub _push_error {
    my ($errors, $code) = @_;
    push @$errors, $code unless grep { $_ eq $code } @$errors;
}

sub _edge {
    my (%args) = @_;
    my $edge = {
        provider => 'last.fm',
        dataset_or_algorithm => $args{algorithm},
        source => $args{source},
        candidate => $args{candidate},
        scope => $args{scope},
        raw_rank => 0 + $args{rank},
        identity_confidence => 0 + $args{identity_confidence},
        observed_at => _timestamp(),
        cache_state => 'fresh',
    };
    $edge->{raw_score} = 0 + $args{score}
        if defined $args{score} && "$args{score}" =~ /^\d+(?:\.\d+)?$/;
    return $edge;
}

sub prepare {
    my ($enabled, $source_tracks, $callback) = @_;
    return $callback->(_bundle('disabled', 0, 0, [], [])) unless $enabled;
    unless (available()) {
        $log->warn(
            'Last.fm guidance requested but LastMix is unavailable; using Bliss only'
        );
        return $callback->(
            _bundle('unavailable', 0, 0, ['LASTMIX_UNAVAILABLE'], [])
        );
    }

    my (%seen_tracks, %seen_artists, @requests);
    for my $track (@{$source_tracks || []}) {
        my $artist = $track->{artist} || '';
        my $title = $track->{title} || '';
        my $track_key = _normalize_text($artist) . '|' . _normalize_text($title);
        if ($track->{id} && length _normalize_text($artist)
            && length _normalize_text($title) && !$seen_tracks{$track_key}++) {
            push @requests, {
                kind => 'track',
                id => $track->{id},
                artist => $artist,
                title => $title,
                recording_mbid => $track->{recording_mbid},
            };
        }
        my $artist_key = _normalize_text($artist);
        next unless length $artist_key && !$seen_artists{$artist_key}++;
        push @requests, {
            kind => 'artist',
            artist => $artist,
            artist_mbid => ref($track->{artist_mbids}) eq 'ARRAY'
                ? $track->{artist_mbids}->[0] : undef,
        };
    }
    my @track_requests = grep { $_->{kind} eq 'track' } @requests;
    my @artist_requests = grep { $_->{kind} eq 'artist' } @requests;
    @requests = (@track_requests, @artist_requests);

    my (@edges, %edge_keys, @errors);
    my $total_requests = scalar @requests;
    my $stats = {requests => 0, failures => 0, successes => 0};
    my $report_progress = sub {
        return unless ref($progress) eq 'CODE';
        my %extra = @_;
        eval {
            $progress->({
                total => $total_requests,
                requests => 0 + $stats->{requests},
                successes => 0 + $stats->{successes},
                failures => 0 + $stats->{failures},
                edges => scalar(@edges),
                %extra,
            });
            1;
        };
    };
    $report_progress->(
        phase => 'queued',
        message => "Queued $total_requests Last.fm guidance requests",
    );
    my $next;
    $next = sub {
        unless (@requests) {
            my $state = $stats->{failures}
                ? ($stats->{successes} ? 'partial' : 'failed') : 'fresh';
            $log->info(
                'Last.fm evidence prepared requests=' . $stats->{requests}
                . ' failures=' . $stats->{failures}
                . ' edges=' . scalar(@edges)
                . " state=$state"
            );
            return $callback->(_bundle(
                $state, $stats->{requests}, $stats->{failures},
                \@errors, \@edges,
            ));
        }

        my $source = shift @requests;
        $stats->{requests}++;
        my $label = $source->{kind} eq 'track'
            ? $source->{artist} . ' - ' . $source->{title}
            : $source->{artist};
        my $method = $source->{kind} eq 'track'
            ? 'getSimilarTracks' : 'getSimilarArtists';
        $report_progress->(
            phase => 'requesting',
            kind => $source->{kind},
            method => $method,
            label => $label,
            message => "Last.fm $method for \"$label\"",
        );
        main::DEBUGLOG && $log->is_debug && $log->debug(
            "Last.fm: $method for \"$label\""
        );

        my $request_ok = eval {
            if ($source->{kind} eq 'track') {
                Plugins::LastMix::LFM->getSimilarTracks(sub {
                    my $result = shift;
                    if (!$result || ref($result) ne 'HASH' || $result->{error}) {
                        my ($raw_code, $code) = _error_code($result);
                        _push_error(\@errors, $code);
                        $stats->{failures}++;
                        $log->warn(
                            "Last.fm track error for \"$label\": "
                            . (ref($result) eq 'HASH' && $result->{message}
                                ? $result->{message} : $code)
                        );
                        if (_service_wide_error($raw_code) && @requests) {
                            $log->warn(
                                "Last.fm service-wide error $raw_code; skipping "
                                . scalar(@requests) . ' remaining requests'
                            );
                            @requests = ();
                        }
                        $report_progress->(
                            phase => 'failed',
                            kind => $source->{kind},
                            method => $method,
                            label => $label,
                            message => "Last.fm $method failed for \"$label\"",
                        );
                        return $next->();
                    }

                    $stats->{successes}++;
                    my $tracks = $result->{similartracks}->{track};
                    $tracks = [] unless ref($tracks) eq 'ARRAY';
                    my $source_entity = _recording_entity(
                        $source->{id}, $source->{artist}, $source->{title},
                        $source->{recording_mbid},
                    );
                    my $rank = 0;
                    for my $track (@$tracks) {
                        next unless ref($track) eq 'HASH' && $track->{name};
                        my $artist = ref($track->{artist}) eq 'HASH'
                            ? $track->{artist} : {};
                        next unless $artist->{name};
                        last if $rank >= MAX_SIMILAR_RESULTS;
                        $rank++;
                        my $candidate = _recording_entity(
                            undef, $artist->{name}, $track->{name}, $track->{mbid},
                        );
                        my $key = join('|', 'recording', $source_entity->{id},
                            $candidate->{id}, 'endpoint_local');
                        next if $edge_keys{$key}++;
                        push @edges, _edge(
                            algorithm => 'LastMix track.getSimilar',
                            source => {%$source_entity},
                            candidate => $candidate,
                            scope => 'endpoint_local',
                            rank => $rank,
                            score => $track->{match},
                            identity_confidence =>
                                _valid_mbid($track->{mbid}) ? 1.0 : 0.85,
                        );
                    }
                    main::DEBUGLOG && $log->is_debug && $log->debug(
                        "Last.fm: retained $rank similar tracks for \"$label\""
                    );
                    $report_progress->(
                        phase => 'received',
                        kind => $source->{kind},
                        method => $method,
                        label => $label,
                        retained => $rank,
                        message => "Last.fm retained $rank similar tracks for \"$label\"",
                    );
                    $next->();
                }, {
                    artist => $source->{artist},
                    title => $source->{title},
                    mbid => _valid_mbid($source->{recording_mbid}),
                });
            } else {
                Plugins::LastMix::LFM->getSimilarArtists(sub {
                    my $result = shift;
                    if (!$result || ref($result) ne 'HASH' || $result->{error}) {
                        my ($raw_code, $code) = _error_code($result);
                        _push_error(\@errors, $code);
                        $stats->{failures}++;
                        $log->warn(
                            "Last.fm artist error for \"$label\": "
                            . (ref($result) eq 'HASH' && $result->{message}
                                ? $result->{message} : $code)
                        );
                        if (_service_wide_error($raw_code) && @requests) {
                            $log->warn(
                                "Last.fm service-wide error $raw_code; skipping "
                                . scalar(@requests) . ' remaining requests'
                            );
                            @requests = ();
                        }
                        $report_progress->(
                            phase => 'failed',
                            kind => $source->{kind},
                            method => $method,
                            label => $label,
                            message => "Last.fm $method failed for \"$label\"",
                        );
                        return $next->();
                    }

                    $stats->{successes}++;
                    my $artists = $result->{similarartists}->{artist};
                    $artists = [] unless ref($artists) eq 'ARRAY';
                    my $source_entity = _artist_entity(
                        $source->{artist}, $source->{artist_mbid},
                    );
                    my $rank = 0;
                    for my $artist (@$artists) {
                        next unless ref($artist) eq 'HASH' && $artist->{name};
                        last if $rank >= MAX_SIMILAR_RESULTS;
                        $rank++;
                        my $candidate = _artist_entity(
                            $artist->{name}, $artist->{mbid},
                        );
                        for my $scope (qw(endpoint_local collection_fallback)) {
                            my $key = join('|', 'artist', $source_entity->{id},
                                $candidate->{id}, $scope);
                            next if $edge_keys{$key}++;
                            push @edges, _edge(
                                algorithm => 'LastMix artist.getSimilar',
                                source => {%$source_entity},
                                candidate => $candidate,
                                scope => $scope,
                                rank => $rank,
                                score => $artist->{match},
                                identity_confidence => 1.0,
                            );
                        }
                    }
                    main::DEBUGLOG && $log->is_debug && $log->debug(
                        "Last.fm: retained $rank similar artists for \"$label\""
                    );
                    $report_progress->(
                        phase => 'received',
                        kind => $source->{kind},
                        method => $method,
                        label => $label,
                        retained => $rank,
                        message => "Last.fm retained $rank similar artists for \"$label\"",
                    );
                    $next->();
                }, {
                    artist => $source->{artist},
                    mbid => _valid_mbid($source->{artist_mbid}),
                });
            }
            1;
        };
        unless ($request_ok) {
            my $message = $@ || 'LastMix request failed before dispatch';
            $message =~ s/\s+/ /g;
            _push_error(\@errors, 'LASTMIX_DISPATCH_FAILED');
            $stats->{failures}++;
            $log->warn(
                "Last.fm dispatch error for \"$label\": $message"
            );
            $report_progress->(
                phase => 'failed',
                kind => $source->{kind},
                method => $method,
                label => $label,
                message => "Last.fm dispatch failed for \"$label\"",
            );
            $next->();
        }
    };
    $next->();
}

1;
