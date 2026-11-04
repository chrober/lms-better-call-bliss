package Plugins::BetterCallBliss::RepeatConflicts;

use strict;
use warnings;

use Plugins::BetterCallBliss::RepeatIdentity;

sub _repeat_key {
    my ($value) = @_;
    return '' unless defined $value;
    $value =~ s/^\s+|\s+$//g;
    return lc $value;
}

sub _display_value {
    my ($value) = @_;
    return '' unless defined $value;
    $value =~ s/^\s+|\s+$//g;
    return $value;
}

sub first_preserved_order_conflict {
    my ($tracks, $artist_window, $album_window, $artist_repeat_mode) = @_;
    return unless ref($tracks) eq 'ARRAY';

    $artist_window = 0 + ($artist_window || 0);
    $album_window = 0 + ($album_window || 0);
    for my $right (0 .. $#$tracks) {
        my $right_track = $tracks->[$right] || {};
        for my $left (0 .. $right - 1) {
            my $left_track = $tracks->[$left] || {};
            my $distance = $right - $left;
            for my $rule (
                [artist => $artist_window],
                [album  => $album_window],
            ) {
                my ($kind, $window) = @$rule;
                next unless $window > 0 && $distance <= $window;
                if ($kind eq 'artist') {
                    next unless
                        Plugins::BetterCallBliss::RepeatIdentity::tracks_repeat_artist(
                            $left_track, $right_track, $artist_repeat_mode,
                        );
                    return {
                        kind => $kind,
                        value => _display_value($right_track->{$kind}),
                        positions => [$left + 1, $right + 1],
                        window => $window,
                    };
                }
                my $right_key = _repeat_key($right_track->{$kind});
                next unless length $right_key;
                next unless $right_key eq _repeat_key($left_track->{$kind});
                return {
                    kind => $kind,
                    value => _display_value($right_track->{$kind}),
                    positions => [$left + 1, $right + 1],
                    window => $window,
                };
            }
        }
    }
    return;
}

sub preserved_order_conflict_message {
    my ($conflict) = @_;
    return '' unless $conflict && ref($conflict) eq 'HASH';
    my $kind = $conflict->{kind} || 'repeat';
    my $window = 0 + ($conflict->{window} || 0);
    my $value = $conflict->{value} || 'an unknown value';
    my $positions = $conflict->{positions} || [];
    my ($left, $right) = @$positions;
    return "Preserve source order violates the $kind repeat window of $window: "
        . "$value occurs at source positions $left and $right. "
        . 'Improve difficult transitions cannot repair this fixed source spacing. '
        . 'Choose Add spacing tracks as needed or Optimize source order.';
}

# Only count conflicts between fixed boundary anchors. This is a necessary
# lower bound, not a claim that a route with this many candidates exists.
sub _repeat_window_for_pair {
    my ($left, $right, $artist, $album, $track, $mode) = @_;
    my ($maximum, $kind) = (0, '');
    if ($artist && Plugins::BetterCallBliss::RepeatIdentity::tracks_repeat_artist($left, $right, $mode)) {
        ($maximum, $kind) = ($artist, 'artist');
    }
    my $album_key = _repeat_key($left->{album});
    if ($album && length($album_key) && $album_key eq _repeat_key($right->{album}) && $album > $maximum) {
        ($maximum, $kind) = ($album, 'album');
    }
    if ($track && $track > $maximum && (
        (defined($left->{id}) && length($left->{id}) && defined($right->{id}) && $left->{id} eq $right->{id})
        || (defined($left->{database_file}) && defined($right->{database_file})
            && length($left->{database_file})
            && $left->{database_file} eq $right->{database_file})
    )) { ($maximum, $kind) = ($track, 'track') }
    return ($maximum, $kind);
}

sub destination_minimum_intermediates {
    my ($history, $tracks, $rejoin, $artist, $album, $track, $mode) = @_;
    return 0 unless ref($tracks) eq 'ARRAY' && @$tracks >= ($rejoin ? 3 : 2);
    my @prefix = (@{$history || []}, $tracks->[0]);
    my $last = $#$tracks - ($rejoin ? 1 : 0);
    my ($outward, $return) = (0, 0);
    for my $i (1 .. $last) {
        for my $p (0 .. $#prefix) {
            my ($window) = _repeat_window_for_pair($prefix[$p], $tracks->[$i], $artist, $album, $track, $mode);
            my $need = $window + 1 - (@prefix - $p + $i - 1);
            $outward = $need if $need > $outward;
        }
        if ($rejoin) {
            my ($window) = _repeat_window_for_pair($tracks->[$i], $tracks->[-1], $artist, $album, $track, $mode);
            my $need = $window + 1 - ($last - $i + 1);
            $return = $need if $need > $return;
        }
    }
    return $outward + $return;
}

sub round_trip_minimum_intermediates {
    my ($tracks, $artist, $album, $track, $mode) = @_;
    return destination_minimum_intermediates([], $tracks, 1, $artist, $album, $track, $mode);
}

sub fixed_gap_repeat_conflict {
    my ($tracks, $per_gap, $artist, $album, $track, $mode) = @_;
    for my $right (1 .. $#$tracks) {
        for my $left (0 .. $right - 1) {
            my ($window, $kind) = _repeat_window_for_pair($tracks->[$left], $tracks->[$right], $artist, $album, $track, $mode);
            my $distance = ($right - $left) * ($per_gap + 1);
            return {kind => $kind, left => $left + 1, right => $right + 1, window => $window, distance => $distance}
                if $window && $distance <= $window;
        }
    }
    return;
}

1;
