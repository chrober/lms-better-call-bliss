package Plugins::BlissEmAll::AppMenu;

use strict;
use Slim::Schema;
use Plugins::BlissEmAll::BlissCompatibility;
use Plugins::BlissEmAll::Jobs;

sub _status_name {
    my $status = shift;
    return $status->{ready}
        ? 'System status: Ready'
        : 'System status: Attention required';
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
            description => 'Select a saved playlist and preview a Bliss-powered reorder.',
            url => \&playlistFeed,
        },
        {name => "Active previews ($active)", url => \&activeJobsFeed},
        {name => "Recent results ($recent)", url => \&recentJobsFeed},
        {name => _status_name($status), url => \&statusFeed},
        {
            name => 'Settings',
            description => "Server Settings > Plugins > Bliss 'Em All",
            url => \&settingsHelpFeed,
        },
        {name => 'Help and about', url => \&aboutFeed},
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
            url => \&modeFeed,
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

sub modeFeed {
    my ($client, $cb, $args, $pt) = @_;
    $cb->({items => [
        {
            name => 'Reorder only',
            description => 'All original tracks remain; their order may change.',
            url => \&reviewFeed,
            passthrough => [$pt],
        },
        {
            name => 'Preserve order and fill gaps - coming next',
            type => 'text',
        },
    ]});
}

sub reviewFeed {
    my ($client, $cb, $args, $pt) = @_;
    my $status = Plugins::BlissEmAll::BlissCompatibility::snapshot();
    my $scoring = $status->{matrix_available}
        ? "Adaptive; seed $status->{seed_limit}; learned $status->{learned_percent}%"
        : "Adaptive seed variance; learned matrix unavailable (optional)";
    my @items = (
        {name => "Playlist: $pt->{playlist_title}", type => 'text'},
        {name => "Tracks: $pt->{track_count} original -> $pt->{track_count} proposed", type => 'text'},
        {name => "Scoring: $scoring", type => 'text'},
        {name => "Repeat windows: artist $status->{artist_window}; album $status->{album_window}; track $status->{track_window}", type => 'text'},
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
    $cb->({items => \@items});
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
        {
            name => "$_->{playlist_title} - $_->{stage}",
            description => "Reorder only; $_->{track_count} tracks",
            url => \&jobFeed,
            passthrough => [{job_id => $_->{id}}],
        }
    } @jobs;
    my $empty = $wanted_state eq 'running'
        ? 'No active preview jobs'
        : 'No recent results in this server session';
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
        $cb->({items => [
            {name => "Preview: $job->{playlist_title}", type => 'text'},
            {name => 'Stage: Optimizing', type => 'text'},
            {
                name => 'Refresh status',
                url => \&jobFeed,
                passthrough => [$pt],
            },
        ]});
        return;
    }
    if ($job->{state} eq 'failed') {
        $cb->({items => [
            {name => "Preview failed: $job->{error}", type => 'text'},
            {name => "Job ID: $job->{id}", type => 'text'},
        ]});
        return;
    }

    my $artifact = $job->{artifact};
    my $selected = $artifact->{selected_strategy} || 'adaptive';
    my $candidate = $selected eq 'adaptive-arc' ? $artifact->{arc} : $artifact->{primary};
    $cb->({items => [
        {name => "Preview: $job->{playlist_title}", type => 'text'},
        {name => "Tracks: $job->{track_count} original -> $job->{track_count} proposed", type => 'text'},
        {name => "Selected strategy: $selected", type => 'text'},
        {name => sprintf('Objective %.3f; worst transition %.3f', $candidate->{objective}, $candidate->{worst_transition}), type => 'text'},
        {name => $artifact->{repeat_validation}->{valid} ? 'Constraints: repeat windows satisfied' : 'Constraints: violation detected', type => 'text'},
        {
            name => 'Proposed order',
            url => \&proposedOrderFeed,
            passthrough => [$pt],
        },
        {name => 'Create playlist - intentionally disabled in preview milestone', type => 'text'},
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
            name => sprintf('%02d. %s - %s', ++$position, $label->{artist} || '?', $label->{title} || $id),
            description => "Original position $original",
            type => 'text',
        };
    }
    $cb->({items => \@items});
}

sub statusFeed {
    my ($client, $cb, $args) = @_;
    my $status = Plugins::BlissEmAll::BlissCompatibility::snapshot();
    my @items = (
        {name => 'BlissMixer: ' . ($status->{bliss_enabled} ? 'enabled' : 'missing'), type => 'text'},
        {name => 'bliss.db: ' . (-r $status->{database} ? 'ready' : 'missing'), type => 'text'},
        {name => 'Learned matrix: ' . ($status->{matrix_available} ? 'ready' : 'not present (optional)'), type => 'text'},
        {name => 'Optimizer ARM64 binary: ' . ($status->{optimizer_binary} && -x $status->{optimizer_binary} ? 'ready' : 'missing'), type => 'text'},
        {name => 'Library scan: ' . ($status->{scanning} ? 'running - previews paused' : 'idle'), type => 'text'},
    );
    push @items, map { {name => "Attention: $_", type => 'text'} } @{$status->{problems}};
    $cb->({items => \@items});
}

sub settingsHelpFeed {
    my ($client, $cb, $args) = @_;
    $cb->({items => [
        {name => "Open Server Settings > Plugins > Bliss 'Em All", type => 'text'},
        {name => 'Bliss scoring and repeat settings are inherited read-only from BlissMixer.', type => 'text'},
    ]});
}

sub aboutFeed {
    my ($client, $cb, $args) = @_;
    $cb->({items => [
        {name => "Bliss 'Em All 0.1.0 preview milestone", type => 'text'},
        {name => 'This version previews real saved-playlist reordering and never writes a playlist.', type => 'text'},
        {name => 'Native scoring: bliss-mixer-core Adaptive model', type => 'text'},
    ]});
}

sub statusCommand {
    my $request = shift;
    my $status = Plugins::BlissEmAll::BlissCompatibility::snapshot();
    $request->addResult('ready', 0 + $status->{ready});
    $request->addResult('problem_count', scalar @{$status->{problems}});
    $request->setStatusDone();
}

1;
