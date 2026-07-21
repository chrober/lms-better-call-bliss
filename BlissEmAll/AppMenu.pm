package Plugins::BlissEmAll::AppMenu;

use strict;
use Slim::Schema;
use Slim::Utils::Prefs;
use Time::HiRes qw(time);
use Plugins::BlissEmAll::BlissCompatibility;
use Plugins::BlissEmAll::Jobs;

my $plugin_prefs = preferences('plugin.blissemall');

sub _status_name {
    my $status = shift;
    return $status->{ready}
        ? 'System status: Ready'
        : 'System status: Attention required';
}

sub _unavailable_item {
    my ($name, $description) = @_;
    return {
        name => "$name [Not connected yet]",
        description => $description,
        type => 'text',
    };
}

sub _draft {
    my ($pt, %updates) = @_;
    return {%{$pt || {}}, %updates};
}

sub rootFeed {
    my ($client, $cb, $args) = @_;
    my $status = Plugins::BlissEmAll::BlissCompatibility::snapshot();
    my @jobs = Plugins::BlissEmAll::Jobs::all();
    my $active = scalar grep { $_->{state} eq 'running' } @jobs;
    my $recent = scalar grep { $_->{state} ne 'running' } @jobs;

    $cb->({items => [
        {
            name => 'Optimize a saved playlist',
            description => 'Choose ordering and extension policies; one read-only preview path is connected.',
            url => \&playlistFeed,
        },
        {name => "Active previews ($active) [Session only]", url => \&activeJobsFeed},
        {name => "Recent results ($recent) [Session only]", url => \&recentJobsFeed},
        {name => _status_name($status), url => \&statusFeed},
        {
            name => 'Settings',
            description => "Server Settings > Plugins > Bliss 'Em All",
            url => \&settingsHelpFeed,
        },
        {name => 'Feature availability and help', url => \&aboutFeed},
    ]});
}

sub playlistFeed {
    my ($client, $cb, $args) = @_;
    my @playlists = Slim::Schema->rs('Playlist')->getPlaylists('all')->all;
    my @items;
    for my $playlist (sort { lc($a->title || '') cmp lc($b->title || '') } @playlists) {
        next unless $playlist && $playlist->can('tracks');
        my $count = eval { $playlist->tracks->count } || 0;
        next unless $count >= 2;
        push @items, {
            name => ($playlist->title || $playlist->name) . " ($count tracks)",
            description => 'Saved playlist',
            url => \&orderingPolicyFeed,
            passthrough => [{
                playlist_id => 0 + $playlist->id,
                playlist_title => $playlist->title || $playlist->name,
                track_count => 0 + $count,
            }],
        };
    }
    push @items, {name => 'No eligible saved playlists found', type => 'text'}
        unless @items;
    $cb->({items => \@items});
}

sub orderingPolicyFeed {
    my ($client, $cb, $args, $pt) = @_;
    $cb->({items => [
        {
            name => 'Optimize order [Connected for Reorder only]',
            description => 'The optimizer may reorder original tracks to improve transitions.',
            url => \&extensionPolicyFeed,
            passthrough => [_draft($pt, ordering_policy => 'optimize')],
        },
        {
            name => 'Preserve order and fill gaps [Not connected yet]',
            description => 'Keep every original track in place and insert bridge tracks only between them.',
            url => \&extensionPolicyFeed,
            passthrough => [_draft($pt, ordering_policy => 'preserve')],
        },
    ]});
}

sub extensionPolicyFeed {
    my ($client, $cb, $args, $pt) = @_;
    my $connected = ($pt->{ordering_policy} || '') eq 'optimize';
    my @items;
    if ($connected) {
        push @items, {
            name => 'Reorder only [Working: read-only preview]',
            description => 'All original tracks remain exactly once; their order may change.',
            url => \&reviewFeed,
            passthrough => [_draft($pt, extension_policy => 'none')],
        };
    }
    push @items,
        {
            name => 'Extend automatically [Not connected yet]',
            description => 'Let the optimizer insert only bridges that materially improve difficult transitions.',
            url => \&extensionDraftFeed,
            passthrough => [_draft($pt, extension_policy => 'automatic')],
        },
        {
            name => 'Add exactly N tracks [Not connected yet]',
            description => 'Insert an exact user-selected number of additional tracks.',
            url => \&extensionDraftFeed,
            passthrough => [_draft($pt, extension_policy => 'exact')],
        },
        {
            name => 'One bridge per transition [Not connected yet]',
            description => 'Insert one track between every adjacent pair of original tracks.',
            url => \&extensionDraftFeed,
            passthrough => [_draft($pt, extension_policy => 'per_transition')],
        },
        {
            name => 'Target length [Not connected yet]',
            description => 'Grow the playlist to an exact user-selected total number of tracks.',
            url => \&extensionDraftFeed,
            passthrough => [_draft($pt, extension_policy => 'target')],
        },
        {
            name => 'Double length [Not connected yet]',
            description => 'Insert exactly as many tracks as the source contains.',
            url => \&extensionDraftFeed,
            passthrough => [_draft($pt, extension_policy => 'double')],
        };
    $cb->({items => \@items});
}

sub extensionDraftFeed {
    my ($client, $cb, $args, $pt) = @_;
    my $source = int($pt->{track_count} || 0);
    my $policy = $pt->{extension_policy} || 'none';
    my %details = (
        none => ['No additions', "$source original -> $source proposed"],
        automatic => ['Automatic bridge budget', "$source original -> between $source and " . ($source + int($plugin_prefs->get('auto_bridge_budget') || 8)) . ' proposed'],
        exact => ['Exact additions', 'N must be selected in a numeric editor'],
        per_transition => ['One bridge per transition', ($source - 1) . ' additions -> ' . (2 * $source - 1) . ' proposed'],
        target => ['Target length', 'A total target T must be selected; T cannot be smaller than the source'],
        double => ['Double length', "$source additions -> " . (2 * $source) . ' proposed'],
    );
    my $detail = $details{$policy} || ['Unknown policy', 'No calculation available'];
    my $ordering = ($pt->{ordering_policy} || '') eq 'preserve'
        ? 'Preserve original order and fill gaps'
        : 'Optimize order';
    my @items = (
        {name => "Playlist: $pt->{playlist_title}", type => 'text'},
        {name => "Ordering: $ordering", type => 'text'},
        {name => "Extension: $detail->[0]", type => 'text'},
        {name => "Planned size: $detail->[1]", type => 'text'},
    );
    push @items, _unavailable_item(
        'Numeric value editor',
        'Required before exact-N or target-length review.'
    ) if $policy eq 'exact' || $policy eq 'target';
    push @items,
        _unavailable_item('Candidate discovery and bridge selection', 'Will use local Bliss first and optional semantic evidence when available.'),
        _unavailable_item('Run preview', 'This screen is a UX contract preview and cannot start an optimizer job.');
    $cb->({items => \@items});
}

sub reviewFeed {
    my ($client, $cb, $args, $pt) = @_;
    my $status = Plugins::BlissEmAll::BlissCompatibility::snapshot();
    my $scoring = $status->{matrix_available}
        ? "Adaptive; seed $status->{seed_limit}; learned $status->{learned_percent}%"
        : "Unavailable: learned matrix is required by this optimizer build";
    my @items = (
        {name => '[Working path] Read-only reorder preview', type => 'text'},
        {name => "Playlist: $pt->{playlist_title}", type => 'text'},
        {name => 'Ordering: Optimize order', type => 'text'},
        {name => 'Extension: Reorder only', type => 'text'},
        {name => "Tracks: $pt->{track_count} original -> $pt->{track_count} proposed", type => 'text'},
        {name => "Scoring: $scoring", type => 'text'},
        {name => "Repeat windows: artist $status->{artist_window}; album $status->{album_window}; track $status->{track_window}", type => 'text'},
        {name => 'Search restarts: ' . int($plugin_prefs->get('restart_count') || 50) . '; large playlists may take several minutes', type => 'text'},
        {name => 'Semantic providers: Local Bliss only; Last.fm and ListenBrainz not connected yet', type => 'text'},
        {
            name => 'Advanced options and output',
            url => \&advancedOptionsFeed,
            passthrough => [$pt],
        },
    );
    if ($status->{ready}) {
        push @items, {
            name => 'Run preview',
            description => 'Read-only: no playlist will be created.',
            url => \&runPreviewFeed,
            passthrough => [$pt],
        };
    } else {
        push @items, {
            name => 'Preview unavailable - open System status',
            url => \&statusFeed,
        };
    }
    push @items, _unavailable_item(
        'Create optimized playlist',
        'Playlist writing stays disabled until preview, validation, rollback, and scanner behavior are connected.'
    );
    $cb->({items => \@items});
}

sub advancedOptionsFeed {
    my ($client, $cb, $args, $pt) = @_;
    my $suffix = $plugin_prefs->get('output_suffix') || 'Optimized';
    my $extended = $plugin_prefs->get('extended_suffix') || 'Extended';
    $cb->({items => [
        {name => 'Scoring and repeat windows are inherited read-only from BlissMixer', type => 'text'},
        {name => 'Search restarts: ' . int($plugin_prefs->get('restart_count') || 50) . ' [Working]', type => 'text'},
        _unavailable_item("Output suffix: $suffix", 'Stored in settings, but playlist creation is not connected.'),
        _unavailable_item("Extended suffix: $extended", 'Stored in settings, but extension modes are not connected.'),
        _unavailable_item('Last.fm semantic evidence', 'Optional provider; failures will be tolerated once connected.'),
        _unavailable_item('ListenBrainz semantic evidence', 'Optional MBID-aware provider; failures will be tolerated once connected.'),
        _unavailable_item('Transition diagnostics threshold', 'The future result UI will highlight difficult transitions.'),
    ]});
}

sub runPreviewFeed {
    my ($client, $cb, $args, $pt) = @_;
    my $job;
    eval {
        $job = Plugins::BlissEmAll::Jobs::start_reorder_preview($pt->{playlist_id});
    };
    if ($@ || !$job) {
        my $error = $@ || 'Could not start preview';
        $error =~ s/\s+/ /g;
        $cb->({items => [{name => "Preview failed to start: $error", type => 'text'}]});
        return;
    }
    $cb->({items => [
        {name => "Preview: $job->{playlist_title}", type => 'text'},
        {name => 'Stage: Optimizing', type => 'text'},
        {name => "Job ID: $job->{id}", type => 'text'},
        {name => "Return to Bliss 'Em All > Active previews to refresh", type => 'text'},
        _unavailable_item('Cancel preview', 'The native child-process cancellation path has not been connected.'),
    ]});
}

sub _jobsFeed {
    my ($cb, $wanted_state) = @_;
    my @jobs = grep {
        $wanted_state eq 'running'
            ? $_->{state} eq 'running'
            : $_->{state} ne 'running'
    } Plugins::BlissEmAll::Jobs::all();
    my @items = map {
        my $elapsed = int((($_->{finished_at} || time()) - $_->{started_at}));
        {
            name => "$_->{playlist_title} - $_->{stage}",
            description => "Reorder-only preview; $_->{track_count} tracks; ${elapsed}s elapsed; session memory only",
            url => \&jobFeed,
            passthrough => [{job_id => $_->{id}}],
        }
    } @jobs;
    my $empty = $wanted_state eq 'running'
        ? 'No active preview jobs'
        : 'No recent results in this server session [Persistent history not connected yet]';
    push @items, {name => $empty, type => 'text'}
        unless @items;
    $cb->({items => \@items});
}

sub activeJobsFeed {
    my ($client, $cb, $args) = @_;
    _jobsFeed($cb, 'running');
}

sub recentJobsFeed {
    my ($client, $cb, $args) = @_;
    _jobsFeed($cb, 'finished');
}

sub jobFeed {
    my ($client, $cb, $args, $pt) = @_;
    my $job = Plugins::BlissEmAll::Jobs::get($pt->{job_id});
    unless ($job) {
        $cb->({items => [{name => 'Preview job is no longer available', type => 'text'}]});
        return;
    }
    if ($job->{state} eq 'running') {
        my $elapsed = int(time() - $job->{started_at});
        $cb->({items => [
            {name => "Preview: $job->{playlist_title}", type => 'text'},
            {name => "Stage: Optimizing (${elapsed}s elapsed)", type => 'text'},
            {name => "Search restarts: $job->{restart_count}", type => 'text'},
            {
                name => 'Refresh status',
                url => \&jobFeed,
                passthrough => [$pt],
            },
            _unavailable_item('Cancel preview', 'The native process is not yet tracked with a cancellable job handle.'),
        ]});
        return;
    }
    if ($job->{state} eq 'failed') {
        my $code = $job->{error_code} || 'UNKNOWN_FAILURE';
        $cb->({items => [
            {name => "Preview failed [$code]", type => 'text'},
            {name => $job->{error}, type => 'text'},
            {name => "Job ID: $job->{id}", type => 'text'},
        ]});
        return;
    }

    my $artifact = $job->{artifact};
    my $elapsed = int($job->{finished_at} - $job->{started_at});
    my $selected = $artifact->{selected_strategy} || 'adaptive';
    my $candidate = $selected eq 'adaptive-arc' ? $artifact->{arc} : $artifact->{primary};
    $cb->({items => [
        {name => '[Preview only] No saved playlist has been changed', type => 'text'},
        {name => "Preview: $job->{playlist_title}", type => 'text'},
        {name => "Tracks: $job->{track_count} original -> $job->{track_count} proposed", type => 'text'},
        {name => "Completed in ${elapsed}s using $job->{restart_count} restarts", type => 'text'},
        {name => "Selected strategy: $selected", type => 'text'},
        {name => sprintf('Objective %.3f; worst transition %.3f', $candidate->{objective}, $candidate->{worst_transition}), type => 'text'},
        {name => $artifact->{repeat_validation}->{valid} ? 'Constraints: repeat windows satisfied' : 'Constraints: violation detected', type => 'text'},
        {
            name => 'Proposed order',
            url => \&proposedOrderFeed,
            passthrough => [$pt],
        },
        {
            name => 'Additions and reasons',
            url => \&additionsFeed,
            passthrough => [$pt],
        },
        {
            name => 'Transition summary [Aggregate only]',
            url => \&transitionSummaryFeed,
            passthrough => [$pt],
        },
        {
            name => 'Warnings',
            url => \&resultWarningsFeed,
            passthrough => [$pt],
        },
        {
            name => 'Full report [Session only]',
            url => \&reportFeed,
            passthrough => [$pt],
        },
        _unavailable_item('Create optimized playlist', 'Playlist writing and scanner verification are deliberately disabled.'),
        _unavailable_item('Change options and rerun', 'Draft restoration is not connected; return to Optimize a saved playlist.'),
        _unavailable_item('Discard result', 'Results are held only for this LMS process and disappear on restart.'),
    ]});
}

sub proposedOrderFeed {
    my ($client, $cb, $args, $pt) = @_;
    my $job = Plugins::BlissEmAll::Jobs::get($pt->{job_id});
    unless ($job && $job->{artifact}) {
        $cb->({items => [{name => 'Preview result unavailable', type => 'text'}]});
        return;
    }
    my @items;
    my $position = 0;
    for my $id (@{$job->{artifact}->{selected_track_ids} || []}) {
        my $label = $job->{labels}->{$id} || {};
        my $original = $job->{original_positions}->{$id} || 0;
        push @items, {
            name => sprintf('%02d. %s - %s [Original]', ++$position, $label->{artist} || '?', $label->{title} || $id),
            description => "Original position $original",
            type => 'text',
        };
    }
    $cb->({items => \@items});
}

sub additionsFeed {
    my ($client, $cb, $args, $pt) = @_;
    $cb->({items => [
        {name => 'No tracks added: this result used Reorder only', type => 'text'},
        _unavailable_item('Bridge provenance and reasons', 'This will list Bliss distance, local artist evidence, and optional provider evidence for every addition.'),
    ]});
}

sub _completed_job {
    my $pt = shift;
    my $job = Plugins::BlissEmAll::Jobs::get($pt->{job_id});
    return ($job && $job->{artifact}) ? $job : undef;
}

sub transitionSummaryFeed {
    my ($client, $cb, $args, $pt) = @_;
    my $job = _completed_job($pt);
    unless ($job) {
        $cb->({items => [{name => 'Preview result unavailable', type => 'text'}]});
        return;
    }
    my $artifact = $job->{artifact};
    my $selected = $artifact->{selected_strategy} || 'adaptive';
    my $candidate = $selected eq 'adaptive-arc' ? $artifact->{arc} : $artifact->{primary};
    $cb->({items => [
        {name => "Selected strategy: $selected", type => 'text'},
        {name => sprintf('Total objective: %.3f', $candidate->{objective}), type => 'text'},
        {name => sprintf('Worst transition: %.3f', $candidate->{worst_transition}), type => 'text'},
        {name => 'Contextual transition legs are included in the native artifact', type => 'text'},
        _unavailable_item('Per-transition drill-down', 'The UI adapter does not yet expose every leg and its scoring explanation.'),
    ]});
}

sub resultWarningsFeed {
    my ($client, $cb, $args, $pt) = @_;
    my $job = _completed_job($pt);
    unless ($job) {
        $cb->({items => [{name => 'Preview result unavailable', type => 'text'}]});
        return;
    }
    my $valid = $job->{artifact}->{repeat_validation}->{valid};
    $cb->({items => [
        {name => $valid ? 'No repeat-window violations detected' : 'Repeat-window validation reported a violation', type => 'text'},
        {name => 'Read-only preview: no playlist file or LMS playlist was changed', type => 'text'},
        _unavailable_item('Semantic-provider warnings', 'External providers are not connected, so there were no remote requests to report.'),
    ]});
}

sub reportFeed {
    my ($client, $cb, $args, $pt) = @_;
    my $job = _completed_job($pt);
    unless ($job) {
        $cb->({items => [{name => 'Preview result unavailable', type => 'text'}]});
        return;
    }
    my $artifact = $job->{artifact};
    $cb->({items => [
        {name => "Job ID: $job->{id}", type => 'text'},
        {name => "Source playlist ID: $job->{playlist_id}", type => 'text'},
        {name => "Source tracks: $job->{track_count}", type => 'text'},
        {name => 'Result artifact: validated native optimizer JSON [Available in job memory]', type => 'text'},
        {name => 'Selected strategy: ' . ($artifact->{selected_strategy} || 'adaptive'), type => 'text'},
        _unavailable_item('Persist report', 'Durable report storage and retention cleanup are not connected.'),
        _unavailable_item('Export JSON report', 'A downloadable report endpoint has not been connected.'),
    ]});
}

sub statusFeed {
    my ($client, $cb, $args) = @_;
    my $status = Plugins::BlissEmAll::BlissCompatibility::snapshot();
    my @items = (
        {name => 'Core preview capability', type => 'text'},
        {name => 'BlissMixer: ' . ($status->{bliss_enabled} ? 'enabled' : 'missing'), type => 'text'},
        {name => 'bliss.db: ' . (-r $status->{database} ? 'ready' : 'missing'), type => 'text'},
        {name => 'Learned matrix: ' . ($status->{matrix_available} ? 'ready' : 'missing (required by current optimizer build)'), type => 'text'},
        {name => 'Optimizer ARM64 binary: ' . ($status->{optimizer_binary} && -x $status->{optimizer_binary} ? 'ready' : 'missing'), type => 'text'},
        {name => 'Library scan: ' . ($status->{scanning} ? 'running - previews paused' : 'idle'), type => 'text'},
        {name => 'Feature adapters', type => 'text'},
        {name => 'Saved-playlist selection: ready', type => 'text'},
        {name => 'Reorder-only preview: ready when core capability is ready', type => 'text'},
        {name => 'Playlist and track context entries: visible; actions not connected yet', type => 'text'},
        {name => 'Last.fm similar artists/tracks: optional; not connected yet', type => 'text'},
        {name => 'ListenBrainz MBID evidence: optional; not connected yet', type => 'text'},
        {name => 'Playlist writer and scanner verification: not connected yet', type => 'text'},
        {name => 'Persistent jobs and reports: not connected yet', type => 'text'},
    );
    push @items, map { {name => "Attention: $_", type => 'text'} } @{$status->{problems}};
    $cb->({items => \@items});
}

sub settingsHelpFeed {
    my ($client, $cb, $args) = @_;
    $cb->({items => [
        {name => "Open Server Settings > Plugins > Bliss 'Em All", type => 'text'},
        {name => 'Inherited from BlissMixer [Working]: dynamic scoring, seed limit, learned percentage, artist/album/track windows', type => 'text'},
        {name => 'Search restarts [Working]: controls reorder-preview search effort', type => 'text'},
        _unavailable_item('Output suffixes', 'Stored for future playlist creation and extension modes.'),
        _unavailable_item('Automatic bridge budget', 'Stored for future automatic extension.'),
        _unavailable_item('Last.fm and ListenBrainz toggles/cache', 'Stored for future optional semantic providers.'),
        _unavailable_item('Report retention', 'Stored for future durable result history.'),
    ]});
}

sub aboutFeed {
    my ($client, $cb, $args) = @_;
    $cb->({items => [
        {name => "Bliss 'Em All 0.2.0 full UX shell", type => 'text'},
        {name => 'Safe prototype: this version never creates, replaces, or writes a playlist', type => 'text'},
        {name => 'Working now', type => 'text'},
        {name => 'Applications entry; saved-playlist selection; Optimize order + Reorder only; native preview; proposed order', type => 'text'},
        {name => 'Partially connected', type => 'text'},
        {name => 'Active/recent jobs and results are session-only; context-menu entries are informational shortcuts', type => 'text'},
        {name => 'Not connected yet', type => 'text'},
        {name => 'Preserve order; all bridge/extension modes; numeric inputs; playlist creation; cancellation; durable history/export', type => 'text'},
        {name => "'Bliss me there...' track action; Last.fm and ListenBrainz providers", type => 'text'},
        _unavailable_item('Complete localization', 'The current UX shell is English-first; settings labels have EN/DE translations.'),
        {name => 'Native scoring: bliss-mixer-core Adaptive model', type => 'text'},
    ]});
}

sub statusCommand {
    my $request = shift;
    my $status = Plugins::BlissEmAll::BlissCompatibility::snapshot();
    $request->addResult('ready', 0 + $status->{ready});
    $request->addResult('problem_count', scalar @{$status->{problems}});
    $request->addResult('ux_contract', 'full-shell-v1');
    $request->addResult('working_mode', 'optimize-order/reorder-only/read-only-preview');
    $request->setStatusDone();
}

1;
