package Plugins::BetterCallBliss::CandidateIdentity;

use strict;

sub normalize_text {
    my $value = lc(shift || '');
    $value =~ s/^\s+|\s+$//g;
    $value =~ s/\s+/ /g;
    return $value;
}

sub normalize_mbid {
    my $value = lc(shift || '');
    return $value
        =~ /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
        ? $value : '';
}

1;
