package Plugins::BlissEmAll::Web;

use strict;
use Slim::Schema;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Web::HTTP;
use Slim::Web::Pages;
use Plugins::BlissEmAll::BlissCompatibility;
use Plugins::BlissEmAll::JobOptions;
use Plugins::BlissEmAll::Jobs;

my $log = Slim::Utils::Log::logger('plugin.blissemall');
my $plugin_prefs = preferences('plugin.blissemall');
my $page = 'plugins/BlissEmAll/index.html';

sub init {
    Slim::Web::Pages->addPageFunction($page, \&handler);
    Slim::Web::Pages->addPageLinks(
        'plugins', {'PLUGIN_BLISSEMALL_NAME' => $page},
    );
}

sub shutdown {
    Slim::Web::Pages->addPageLinks(
        'plugins', {'PLUGIN_BLISSEMALL_NAME' => undef},
    );
}

sub _playlists {
    my @rows;
    for my $playlist (sort {
        lc($a->title || $a->name || '') cmp lc($b->title || $b->name || '')
    } Slim::Schema->rs('Playlist')->getPlaylists('all')->all) {
        next unless $playlist && $playlist->can('tracks');
        my $count = eval { $playlist->tracks->count } || 0;
        next unless $count >= 2;
        push @rows, {
            id => 0 + $playlist->id,
            title => $playlist->title || $playlist->name,
            count => 0 + $count,
        };
    }
    return \@rows;
}

sub _form_from_params {
    my ($params, $defaults) = @_;
    my $form = {%$defaults};
    for my $name (qw(
        playlist_id ordering_policy extension_mode algorithm seed_limit
        learned_percent artist_window album_window track_window restart_count
        output_mode output_name
    )) {
        $form->{$name} = $params->{$name} if defined $params->{$name};
    }
    return $form;
}

sub _result_view {
    my $job = shift;
    return unless $job;
    my $view = {
        id => $job->{id},
        state => $job->{state},
        stage => $job->{stage},
        playlist_title => $job->{playlist_title},
        output_mode => $job->{options}->{output_mode},
        output_name => $job->{options}->{output_name},
        write_state => $job->{write_state},
        write_stage => $job->{write_stage},
        write_error_code => $job->{write_error_code},
        write_error => $job->{write_error},
        persistence => $job->{persistence},
    };
    if ($job->{state} eq 'failed') {
        $view->{error_code} = $job->{error_code};
        $view->{error} = $job->{error};
    } elsif ($job->{state} eq 'completed') {
        my $artifact = $job->{artifact};
        my $selected = $artifact->{selected_strategy} || 'adaptive';
        my $candidate = $selected eq 'adaptive-arc'
            ? $artifact->{arc} : $artifact->{primary};
        $view->{selected_strategy} = $selected;
        $view->{objective} = sprintf('%.3f', $candidate->{objective});
        $view->{worst_transition} = sprintf(
            '%.3f', $candidate->{worst_transition},
        );
        my @order;
        my $position = 0;
        for my $id (@{$artifact->{selected_track_ids} || []}) {
            my $label = $job->{labels}->{$id} || {};
            push @order, {
                position => ++$position,
                artist => $label->{artist} || 'Unknown Artist',
                title => $label->{title} || $id,
                original_position => $job->{original_positions}->{$id} || 0,
            };
        }
        $view->{order} = \@order;
    }
    return $view;
}

sub handler {
    my ($client, $params) = @_;
    $params ||= {};
    my $capability = Plugins::BlissEmAll::BlissCompatibility::snapshot();
    my $defaults = Plugins::BlissEmAll::JobOptions::defaults($capability);
    my $form = _form_from_params($params, $defaults);
    my $playlists = _playlists();

    if (defined $form->{playlist_id}
        && "$form->{playlist_id}" =~ /^\d+$/
        && !length($form->{output_name} || '')) {
        for my $playlist (@$playlists) {
            if ($playlist->{id} == $form->{playlist_id}) {
                my $suffix = $plugin_prefs->get('output_suffix') || 'Optimized';
                $form->{output_name} = $playlist->{title} . ' ' . $suffix;
                last;
            }
        }
    }

    my ($job, $error);
    if ($params->{create_copy}) {
        eval {
            die "Preview job is no longer available"
                unless $params->{job_id};
            $job = Plugins::BlissEmAll::Jobs::get($params->{job_id});
            die "Preview job is no longer available" unless $job;
            Plugins::BlissEmAll::Jobs::create_copy($params->{job_id});
        };
        $error = $@;
        $error =~ s/\s+/ /g if $error;
    } elsif ($params->{run_preview}) {
        eval {
            die "Choose a saved playlist"
                unless defined $form->{playlist_id} && "$form->{playlist_id}" =~ /^\d+$/;
            $job = Plugins::BlissEmAll::Jobs::start_reorder_preview(
                int($form->{playlist_id}), $form,
            );
        };
        $error = $@;
        $error =~ s/\s+/ /g if $error;
        $log->warn("Could not start web preview: $error") if $error;
    } elsif ($params->{job_id}) {
        $job = Plugins::BlissEmAll::Jobs::get($params->{job_id});
        $error = 'Preview job is no longer available' unless $job;
    }

    $params->{blissemall_playlists} = $playlists;
    $params->{blissemall_form} = $form;
    $params->{blissemall_defaults} = $defaults;
    $params->{blissemall_capability} = $capability;
    $params->{blissemall_job} = _result_view($job) if $job;
    $params->{blissemall_error} = $error if $error;
    return Slim::Web::HTTP::filltemplatefile($page, $params);
}

1;
