package Plugins::BetterCallBliss::RouteMode;

use strict;

sub normalize_source {
    my $source = shift;
    $source = 'queue_end' unless defined $source && length $source;
    return $source if $source eq 'queue_end'
        || $source eq 'now_playing'
        || $source eq 'round_trip';
    return;
}

sub queue_action {
    my $source = normalize_source(shift);
    return unless defined $source;
    return 'replace_upcoming' if $source eq 'now_playing';
    return 'play_next' if $source eq 'round_trip';
    return 'append';
}

sub action_name {
    my $source = normalize_source(shift);
    return unless defined $source;
    return 'Bliss me there...' if $source eq 'now_playing';
    return 'Bliss me there... and back again!' if $source eq 'round_trip';
    return 'Bliss me there... when we\'re through!';
}

1;
