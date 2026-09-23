package Plugins::BetterCallBliss::GuidanceReporting;

use strict;

sub summary {
    my $contributions = shift;
    return 'no optional guidance adjustment'
        unless ref($contributions) eq 'ARRAY' && @$contributions;

    my @parts;
    for my $item (@$contributions) {
        next unless ref($item) eq 'HASH';
        my $channel = $item->{channel} || '';
        my $label = $channel eq 'playcount' ? 'play-count'
            : $channel eq 'lastfm_track' ? 'Last.fm similar-track'
            : $channel eq 'lastfm_artist' ? 'Last.fm similar-artist'
            : ($item->{provider_id} || 'optional guidance') . " $channel";
        my $contribution = 0 + ($item->{contribution} || 0);
        my $effect = $contribution > 0 ? 'boost'
            : $contribution < 0 ? 'penalty' : 'neutral adjustment';
        my $amount = sprintf('%+.4f', $contribution);
        my $rationale = $item->{rationale};
        push @parts, "$label $effect $amount"
            . (defined $rationale && length $rationale ? " ($rationale)" : '');
    }
    return @parts ? join('; ', @parts) : 'no optional guidance adjustment';
}

1;
