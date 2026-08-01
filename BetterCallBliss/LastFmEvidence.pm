package Plugins::BetterCallBliss::LastFmEvidence;

use strict;
use POSIX qw(strftime);
use Slim::Utils::Log;
use Slim::Utils::PluginManager;

my $log = Slim::Utils::Log::logger('plugin.bettercallbliss');

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

sub _normalize_artist {
    my $artist = lc(shift || '');
    $artist =~ s/^\s+|\s+$//g;
    $artist =~ s/\s+/ /g;
    return $artist;
}

sub _service_wide_error {
    my $code = shift;
    return defined $code && "$code" =~ /^(?:11|16|29)$/;
}

sub _artist_entity {
    my ($name, $mbid) = @_;
    my $normalized = _normalize_artist($name);
    my $entity = {
        kind => 'artist',
        id => 'artist:' . $normalized,
        name => $name,
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
            dataset_or_algorithm => 'LastMix artist.getSimilar',
            state => $state,
            request_count => 0 + ($requests || 0),
            failure_count => 0 + ($failures || 0),
            error_codes => $errors || [],
        }],
        edges => $edges || [],
    };
}

sub prepare {
    my ($enabled, $source_tracks, $callback) = @_;
    return $callback->(_bundle('disabled', 0, 0, [], [])) unless $enabled;
    unless (available()) {
        $log->warn('Last.fm artist weighting requested but LastMix is unavailable; using Bliss only');
        return $callback->(_bundle('unavailable', 0, 0, ['LASTMIX_UNAVAILABLE'], []));
    }

    my (%seen, @sources);
    for my $track (@{$source_tracks || []}) {
        my $artist = $track->{artist} || '';
        next unless length _normalize_artist($artist);
        my $key = _normalize_artist($artist);
        next if $seen{$key}++;
        push @sources, {
            artist => $artist,
            artist_mbid => ref($track->{artist_mbids}) eq 'ARRAY'
                ? $track->{artist_mbids}->[0] : undef,
        };
    }

    my (@edges, %edge_keys, @errors);
    my $stats = {requests => 0, failures => 0, successes => 0};
    my $next;
    $next = sub {
        unless (@sources) {
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

        my $source = shift @sources;
        $stats->{requests}++;
        main::DEBUGLOG && $log->is_debug && $log->debug(
            'Last.fm: getSimilarArtists for "' . $source->{artist} . '"'
        );
        my $request_ok = eval {
            Plugins::LastMix::LFM->getSimilarArtists(sub {
            my $result = shift;
            if (!$result || ref($result) ne 'HASH' || $result->{error}) {
                my $raw_code = ref($result) eq 'HASH'
                    ? $result->{error} : undef;
                my $code = $raw_code
                    ? 'LASTFM_' . $raw_code : 'LASTFM_NO_RESULT';
                push @errors, $code unless grep { $_ eq $code } @errors;
                $stats->{failures}++;
                $log->warn(
                    'Last.fm error for "' . $source->{artist} . '": '
                    . (ref($result) eq 'HASH' && $result->{message}
                        ? $result->{message} : $code)
                );
                if (_service_wide_error($raw_code) && @sources) {
                    $log->warn(
                        "Last.fm service-wide error $raw_code; skipping "
                        . scalar(@sources) . ' remaining artist requests'
                    );
                    @sources = ();
                }
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
                $rank++;
                my $candidate = _artist_entity($artist->{name}, $artist->{mbid});
                for my $scope (qw(endpoint_local collection_fallback)) {
                    my $key = join('|', $source_entity->{id}, $candidate->{id}, $scope);
                    next if $edge_keys{$key}++;
                    my $edge = {
                        provider => 'last.fm',
                        dataset_or_algorithm => 'LastMix artist.getSimilar',
                        source => {%$source_entity},
                        candidate => $candidate,
                        scope => $scope,
                        raw_rank => $rank,
                        identity_confidence => 1.0,
                        observed_at => _timestamp(),
                        cache_state => 'fresh',
                    };
                    $edge->{raw_score} = 0 + $artist->{match}
                        if defined $artist->{match} && "$artist->{match}" =~ /^\d+(?:\.\d+)?$/;
                    push @edges, $edge;
                }
            }
            main::DEBUGLOG && $log->is_debug && $log->debug(
                'Last.fm: got ' . scalar(@$artists)
                . ' similar artists for "' . $source->{artist} . '"'
            );
            $next->();
            }, {
                artist => $source->{artist},
                mbid => _valid_mbid($source->{artist_mbid}),
            });
            1;
        };
        unless ($request_ok) {
            my $message = $@ || 'LastMix request failed before dispatch';
            $message =~ s/\s+/ /g;
            push @errors, 'LASTMIX_DISPATCH_FAILED'
                unless grep { $_ eq 'LASTMIX_DISPATCH_FAILED' } @errors;
            $stats->{failures}++;
            $log->warn(
                'Last.fm dispatch error for "' . $source->{artist}
                . '": ' . $message
            );
            $next->();
        }
    };
    $next->();
}

1;
