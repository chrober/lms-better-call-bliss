package Plugins::BetterCallBliss::RepeatConflicts;

use strict;
use warnings;

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
    my ($tracks, $artist_window, $album_window) = @_;
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

1;
