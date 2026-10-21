use strict;
use warnings;
use FindBin;
use Test::More;

BEGIN {
    package DBI;
    $INC{'DBI.pm'} = __FILE__;
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
        mode => 'repeat_window_repair',
        processing_order => 'global-minimum-repeat-window-repair',
        source_track_count => 4,
        source_gap_count => 3,
        max_added_tracks => 5,
        feasible => 1,
        added_track_count => 3,
        no_endpoint_tracks => 1,
        original_subsequence_preserved => 1,
        unique_membership => 1,
        repeat_windows_satisfied => 1,
        minimum_total_selected => 1,
        final_sequence => [
            {kind => 'original', track_id => 'a'},
            {kind => 'original', track_id => 'b'},
            {kind => 'bridge', track_id => 'x1'},
            {kind => 'bridge', track_id => 'x2'},
            {kind => 'original', track_id => 'c'},
            {kind => 'bridge', track_id => 'y1'},
            {kind => 'original', track_id => 'd'},
        ],
        decisions => [
            {reason => 'selected', original_position => 2,
                selected_bridge => {candidate_id => 'x1'}},
            {reason => 'selected', original_position => 2,
                selected_bridge => {candidate_id => 'x2'}},
            {reason => 'selected', original_position => 3,
                selected_bridge => {candidate_id => 'y1'}},
        ],
    };
}

my $valid = eval {
    Plugins::BetterCallBliss::BridgeResolver::_validate_repeat_window_repair_layout(
        preview(), [qw(a b c d)], 5,
    );
    1;
};
ok($valid, 'variable additions inside source gaps are accepted');

my $opening = preview();
unshift @{$opening->{final_sequence}}, {kind => 'bridge', track_id => 'opening'};
ok(!eval {
    Plugins::BetterCallBliss::BridgeResolver::_validate_repeat_window_repair_layout(
        $opening, [qw(a b c d)], 5,
    );
    1;
}, 'opening additions are rejected');

my $over_budget = preview();
$over_budget->{max_added_tracks} = 2;
ok(!eval {
    Plugins::BetterCallBliss::BridgeResolver::_validate_repeat_window_repair_layout(
        $over_budget, [qw(a b c d)], 5,
    );
    1;
}, 'artifact budgets cannot contradict the requested budget');

my $wrong_decisions = preview();
$wrong_decisions->{decisions}->[2]->{original_position} = 2;
ok(!eval {
    Plugins::BetterCallBliss::BridgeResolver::_validate_repeat_window_repair_layout(
        $wrong_decisions, [qw(a b c d)], 5,
    );
    1;
}, 'per-gap decisions must match actual bridge placement');

my $swapped_decisions = preview();
$swapped_decisions->{decisions}->[0]->{selected_bridge}->{candidate_id} = 'y1';
$swapped_decisions->{decisions}->[2]->{selected_bridge}->{candidate_id} = 'x1';
ok(!eval {
    Plugins::BetterCallBliss::BridgeResolver::_validate_repeat_window_repair_layout(
        $swapped_decisions, [qw(a b c d)], 5,
    );
    1;
}, 'each selected bridge identity must belong to its physical source gap');

my $failed_proof = preview();
$failed_proof->{minimum_total_selected} = 0;
ok(!eval {
    Plugins::BetterCallBliss::BridgeResolver::_validate_repeat_window_repair_layout(
        $failed_proof, [qw(a b c d)], 5,
    );
    1;
}, 'minimum-total proof is mandatory');

done_testing();
