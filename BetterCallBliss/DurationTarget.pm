package Plugins::BetterCallBliss::DurationTarget;

use strict;
use warnings;
use Scalar::Util qw(looks_like_number);

sub bounds_seconds {
    my ($minutes, $below, $above) = @_;
    die 'Target duration must be positive' unless defined $minutes && $minutes > 0;
    die 'Duration tolerances must be between 0 and 100 percent'
        unless defined $below && defined $above
            && $below >= 0 && $below <= 100 && $above >= 0 && $above <= 100;
    my $seconds = $minutes * 60;
    return ($seconds * (100 - $below) / 100, $seconds * (100 + $above) / 100);
}

sub source_duration_seconds {
    my ($tracks) = @_;
    die 'Source tracks are missing' unless ref($tracks) eq 'ARRAY' && @$tracks;
    my $total = 0;
    for my $track (@$tracks) {
        my $duration = ref($track) eq 'HASH' ? $track->{duration} : undef;
        die 'A source track has no valid duration'
            unless defined $duration && !ref($duration)
                && looks_like_number($duration) && $duration > 0;
        $total += $duration;
    }
    return $total;
}

sub classify_source {
    my ($duration, $minimum, $maximum) = @_;
    return 'short' if $duration < $minimum;
    return 'too_long' if $duration > $maximum;
    return 'within';
}

sub preflight {
    my ($tracks, $minutes, $below, $above) = @_;
    my $source_seconds = source_duration_seconds($tracks);
    my ($minimum_seconds, $maximum_seconds) = bounds_seconds($minutes, $below, $above);
    return {
        source_seconds => $source_seconds,
        minimum_seconds => $minimum_seconds,
        maximum_seconds => $maximum_seconds,
        state => classify_source($source_seconds, $minimum_seconds, $maximum_seconds),
    };
}

sub preflight_lms_tracks {
    my ($tracks, @arguments) = @_;
    die 'Source tracks are missing' unless ref($tracks) eq 'ARRAY' && @$tracks;
    my @durations = map { {duration => eval { $_->secs }} } @$tracks;
    return preflight(\@durations, @arguments);
}

sub lms_source_milliseconds {
    my ($tracks) = @_;
    die 'Source tracks are missing' unless ref($tracks) eq 'ARRAY' && @$tracks;
    my $total = 0;
    for my $track (@$tracks) {
        my $seconds = eval { $track->secs };
        die 'A source track has no valid duration'
            unless defined $seconds && !ref($seconds)
                && looks_like_number($seconds) && $seconds > 0;
        my $milliseconds = int($seconds * 1000 + 0.5);
        die 'A source track has no valid duration' if $milliseconds <= 0;
        $total += $milliseconds;
    }
    return $total;
}

sub validate_result {
    my ($expected, $reported, $addition_ms) = @_;
    die 'Duration result is missing' unless ref($expected) eq 'HASH'
        && ref($reported) eq 'HASH' && ref($addition_ms) eq 'ARRAY';
    for my $key (qw(source_ms minimum_ms maximum_ms)) {
        die 'Duration result changed the requested bounds'
            unless defined $expected->{$key} && defined $reported->{$key}
                && "$reported->{$key}" =~ /^\d+$/ && $reported->{$key} == $expected->{$key};
    }
    my $actual = $expected->{source_ms};
    for my $duration (@$addition_ms) {
        die 'An added track has no valid duration'
            unless defined $duration && "$duration" =~ /^\d+$/ && $duration > 0;
        $actual += $duration;
    }
    die 'Duration result does not match the resolved tracks'
        unless defined $reported->{actual_ms} && "$reported->{actual_ms}" =~ /^\d+$/
            && $reported->{actual_ms} == $actual;
    die 'Duration result is outside the requested tolerance'
        if $actual < $expected->{minimum_ms} || $actual > $expected->{maximum_ms};
    return 1;
}

sub _format_ms {
    my $seconds = int(($_[0] + 500) / 1000);
    return sprintf('%02d:%02d:%02d', int($seconds / 3600), int(($seconds % 3600) / 60), $seconds % 60);
}

sub report_values {
    my ($target_minutes, $result) = @_;
    die 'Duration report is missing' unless $target_minutes && ref($result) eq 'HASH';
    my $target_ms = $target_minutes * 60000;
    return {
        target => _format_ms($target_ms),
        minimum => _format_ms($result->{minimum_ms}),
        maximum => _format_ms($result->{maximum_ms}),
        actual => _format_ms($result->{actual_ms}),
        deviation_percent => sprintf('%+.1f%%', 100 * ($result->{actual_ms} - $target_ms) / $target_ms),
    };
}

sub failure_message {
    my ($target) = @_;
    return 'No route was found within the requested duration range. Try a wider tolerance or less restrictive repeat windows.'
        unless ref($target) eq 'HASH' && defined $target->{minimum_ms} && defined $target->{maximum_ms};
    return 'No route was found within the requested duration range ('
        . _format_ms($target->{minimum_ms}) . ' to ' . _format_ms($target->{maximum_ms})
        . '). Try a wider tolerance or less restrictive repeat windows.';
}

1;
