package Plugins::BetterCallBliss::RepeatIdentity;

use strict;
use warnings;
use Unicode::Normalize qw(NFKC);

use Plugins::BetterCallBliss::CandidateIdentity;

sub canonical_artist_key {
    my ($mbid, $contributor_id, $name) = @_;
    my $normalized_name = Plugins::BetterCallBliss::CandidateIdentity::normalize_text(
        NFKC(defined $name ? $name : ''),
    );
    return if $normalized_name eq 'various artists';

    my $normalized_mbid = Plugins::BetterCallBliss::CandidateIdentity::normalize_mbid(
        defined $mbid ? $mbid : '',
    );
    return 'artist-mbid:' . $normalized_mbid if length $normalized_mbid;
    return 'lms-contributor:' . int($contributor_id)
        if defined $contributor_id;
    return if !$normalized_name;
    return 'artist-name:' . $normalized_name;
}

sub contributor_artist_key {
    my $artist = shift;
    return unless $artist;
    return canonical_artist_key(
        eval { $artist->musicbrainz_id },
        eval { $artist->id },
        eval { $artist->name },
    );
}

sub repeat_keys_for_track {
    my ($track, $mode) = @_;
    $mode ||= 'exact_bliss_credit';
    if ($mode eq 'shared_artist') {
        my @keys = ref($track->{artist_identity_keys}) eq 'ARRAY'
            ? @{$track->{artist_identity_keys}} : ();
        push @keys, $track->{primary_artist_identity_key}
            if !@keys && defined $track->{primary_artist_identity_key};
        return @keys if @keys;
    } elsif ($mode eq 'primary_artist') {
        return ($track->{primary_artist_identity_key})
            if defined $track->{primary_artist_identity_key}
                && length $track->{primary_artist_identity_key};
    }

    my $credit = Plugins::BetterCallBliss::CandidateIdentity::normalize_text(
        NFKC(defined $track->{artist} ? $track->{artist} : ''),
    );
    return () if !$credit || $credit eq 'various artists';
    return ('artist-credit:' . $credit) if $mode eq 'exact_bliss_credit';
    return ('artist-name:' . $credit);
}

sub tracks_repeat_artist {
    my ($left, $right, $mode) = @_;
    my %left = map { $_ => 1 } repeat_keys_for_track($left, $mode);
    for my $key (repeat_keys_for_track($right, $mode)) {
        return 1 if $left{$key};
    }
    return 0;
}

1;
