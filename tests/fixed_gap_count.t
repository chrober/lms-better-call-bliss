use strict;
use warnings;
use FindBin;
use Test::More;

BEGIN {
    package Slim::Schema;
    $INC{'Slim/Schema.pm'} = __FILE__;
    package Slim::Utils::Misc;
    $INC{'Slim/Utils/Misc.pm'} = __FILE__;
    package Slim::Utils::Unicode;
    $INC{'Slim/Utils/Unicode.pm'} = __FILE__;
}

use lib "$FindBin::Bin/..";
require Plugins::BetterCallBliss::BridgeResolver;

sub preview {
    return {
        mode => 'fixed_gap_count',
        processing_order => 'global-fixed-gap-beam-search',
        source_track_count => 3,
        source_gap_count => 2,
        tracks_per_gap => 2,
        requested_added_tracks => 4,
        feasible => 1,
        added_track_count => 4,
        no_endpoint_tracks => 1,
        original_subsequence_preserved => 1,
        unique_membership => 1,
        every_gap_exact_count => 1,
        repeat_windows_satisfied => 1,
        final_sequence => [
            {kind => 'original', track_id => 'a'},
            {kind => 'bridge', track_id => 'x1'},
            {kind => 'bridge', track_id => 'x2'},
            {kind => 'original', track_id => 'b'},
            {kind => 'bridge', track_id => 'y1'},
            {kind => 'bridge', track_id => 'y2'},
            {kind => 'original', track_id => 'c'},
        ],
        decisions => [
            {reason => 'selected', original_position => 1},
            {reason => 'selected', original_position => 1},
            {reason => 'selected', original_position => 2},
            {reason => 'selected', original_position => 2},
        ],
    };
}

my $valid = eval {
    Plugins::BetterCallBliss::BridgeResolver::_validate_fixed_gap_layout(
        preview(), [qw(a b c)], 2,
    );
    1;
};
ok($valid, 'exactly two bridges in every internal source gap are accepted');

my $opening = preview();
unshift @{$opening->{final_sequence}}, {kind => 'bridge', track_id => 'opening'};
ok(!eval {
    Plugins::BetterCallBliss::BridgeResolver::_validate_fixed_gap_layout(
        $opening, [qw(a b c)], 2,
    );
    1;
}, 'opening bridges are rejected');

my $misplaced = preview();
@{$misplaced->{final_sequence}}[2, 3] = @{$misplaced->{final_sequence}}[3, 2];
ok(!eval {
    Plugins::BetterCallBliss::BridgeResolver::_validate_fixed_gap_layout(
        $misplaced, [qw(a b c)], 2,
    );
    1;
}, 'bridges moved into the wrong source gap are rejected');

my $wrong_proof = preview();
$wrong_proof->{repeat_windows_satisfied} = 0;
ok(!eval {
    Plugins::BetterCallBliss::BridgeResolver::_validate_fixed_gap_layout(
        $wrong_proof, [qw(a b c)], 2,
    );
    1;
}, 'failed native acceptance proofs are rejected');

done_testing();
