use strict;
use warnings;
use FindBin;
use Test::More;

BEGIN {
    package DBI;
    sub connect { bless {}, 'TestBlissDB' }
    package TestBlissDB;
    sub prepare { bless {}, 'TestBlissStatement' }
    sub disconnect { 1 }
    package TestBlissStatement;
    sub execute { $_[0]->{row} = $_[1] }
    sub fetchrow_array { return ('track-' . $_[0]->{row}, 'Title', 'Artist', 'Album') }
    sub finish { 1 }
    package TestLmsTrack;
    sub new { bless {url => $_[1]}, $_[0] }
    sub url { $_[0]->{url} }
    sub remote { 0 }
    sub artistName { 'Artist' }
    sub title { 'Title' }
    sub albumname { 'Album' }
    $INC{'DBI.pm'} = __FILE__;
    $INC{'Slim/Schema.pm'} = __FILE__;
    $INC{'Slim/Utils/Misc.pm'} = __FILE__;
    $INC{'Slim/Utils/Unicode.pm'} = __FILE__;
}

use lib "$FindBin::Bin/..";
require Plugins::BetterCallBliss::BridgeResolver;

sub preview {
    return {
        max_added_tracks => 3, added_track_count => 2,
        spacing_additions => 1, smoothing_additions => 1,
        original_subsequence_preserved => 1, unique_membership => 1,
        repeat_windows_satisfied => 1,
        minimum_spacing_selected => 1,
        final_sequence => [
            {kind => 'original', track_id => 'a'},
            {kind => 'bridge', track_id => 'bliss-row-1'},
            {kind => 'bridge', track_id => 'bliss-row-2'},
            {kind => 'original', track_id => 'b'},
        ],
        addition_reasons => [
            {candidate_id => 'bliss-row-1', reason => 'spacing'},
            {candidate_id => 'bliss-row-2', reason => 'smoothing'},
        ],
    };
}

sub accepts {
    my ($candidate, $budget, $spacing, $smoothing) = @_;
    return eval {
        Plugins::BetterCallBliss::BridgeResolver::_validate_automatic_improvement_layout(
            $candidate, [qw(a b)], $budget, $spacing, $smoothing,
        );
        1;
    } || 0;
}

ok(accepts(preview(), 3, 1, 1), 'accepts a valid mixed internal-gap result');
ok(!accepts(preview(), 1, 1, 1), 'rejects additions above the submitted shared budget');
ok(!accepts(preview(), 3, 1, 0), 'rejects smoothing additions when smoothing was disabled');
my $missing = preview();
pop @{$missing->{addition_reasons}};
ok(!accepts($missing, 3, 1, 1), 'rejects additions without a reason');
my $mismatch = preview();
$mismatch->{addition_reasons}[1]{candidate_id} = 'bliss-row-9';
ok(!accepts($mismatch, 3, 1, 1), 'rejects reasons for tracks not in the result');
my $opening = preview();
unshift @{$opening->{final_sequence}}, {kind => 'bridge', track_id => 'bliss-row-3'};
ok(!accepts($opening, 3, 1, 1), 'rejects opening additions');
my $unproven = preview();
$unproven->{repeat_windows_satisfied} = 0;
ok(!accepts($unproven, 3, 1, 1), 'rejects a result without a repeat-window proof');
my $nonminimum = preview();
$nonminimum->{minimum_spacing_selected} = 0;
ok(!accepts($nonminimum, 3, 1, 1), 'rejects missing minimum-spacing proof');

my $result = preview();
$result->{mode} = 'automatic_improvement';
for my $index (0..$#{$result->{final_sequence}}) {
    $result->{final_sequence}[$index]{position} = $index;
}
$result->{decisions} = [map {
    {reason => 'selected', left_track_id => 'a', right_track_id => 'b',
        direct_percentile => 0.5,
        selected_bridge => {candidate_id => $_->{candidate_id}}}
} @{$result->{addition_reasons}}];
my $job = {
    artifact => {artifact_kind => 'contextual-bridge-analysis-v1',
        ordering_policy => 'preserve_order', selected_track_ids => [qw(a b)],
        selection_preview => $result},
    options => {extension_mode => 'automatic_improvement', ordering_policy => 'preserve_order',
        max_added_tracks => 3, satisfy_repeat_windows => 1, smooth_transitions => 1},
    source_track_ids => [qw(a b)], track_urls => {a => 'file:a', b => 'file:b'},
    capability => {database => 'ignored-test-db'},
};
{
    no warnings 'redefine';
    local *Plugins::BetterCallBliss::BridgeResolver::_track_for_database_file = sub {
        return TestLmsTrack->new('file:' . $_[1]);
    };
    my $resolved = Plugins::BetterCallBliss::BridgeResolver::resolve_bridge_preview($job);
    is_deeply([map { $_->{addition_reason} } @{$resolved->{additions}}],
        [qw(spacing smoothing)], 'resolved LMS additions retain native phase reasons');
    is_deeply($resolved->{final_track_ids}, [qw(a bliss-row-1 bliss-row-2 b)],
        'resolved final order retains both original and added identities');
}
done_testing();
