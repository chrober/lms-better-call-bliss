package Plugins::BetterCallBliss::Plugin;

use strict;
use base qw(Slim::Plugin::Base);

use File::Basename qw(dirname);
use Config qw(%Config);
use File::Spec::Functions qw(catdir catfile);
use Slim::Control::Request;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::Strings;

use Plugins::BetterCallBliss::BlissCompatibility;
use Plugins::BetterCallBliss::CandidateInventory;
use Plugins::BetterCallBliss::ContextMenu;
use Plugins::BetterCallBliss::Jobs;
use Plugins::BetterCallBliss::Web;

my $log = Slim::Utils::Log->addLogCategory({
    category     => 'plugin.bettercallbliss',
    defaultLevel => 'INFO',
    description  => 'DEBUG_PLUGIN_BETTERCALLBLISS',
    logGroups    => 'SCANNER',
});
my $prefs = preferences('plugin.bettercallbliss');
my $initialized = 0;
my $optimizer_binary;

sub getDisplayName { return 'PLUGIN_BETTERCALLBLISS_NAME'; }

sub initPlugin {
    my $class = shift;
    return 1 if $initialized;

    $prefs->init({
        output_suffix => 'Optimized',
        extended_suffix => 'Extended',
        restart_count => 50,
        auto_bridge_budget => 8,
        auto_trigger_percent => 70,
        report_retention_days => 30,
        semantic_cache_days => 30,
        semantic_stale_days => 90,
        lastfm_enabled => 0,
        lastfm_track_guidance_percent => 75,
        lastfm_artist_guidance_percent => 75,
        listenbrainz_enabled => 0,
    });
    my $dir = dirname(__FILE__);
    _loadStrings($dir);
    if (main::ISWINDOWS) {
        Slim::Utils::Misc::addFindBinPaths(catdir($dir, 'Bin', 'windows'));
    } elsif (main::ISMAC) {
        Slim::Utils::Misc::addFindBinPaths(catdir($dir, 'Bin', 'mac'));
    } else {
        for my $platform (_linuxBinaryPlatforms()) {
            Slim::Utils::Misc::addFindBinPaths(catdir($dir, 'Bin', $platform));
        }
    }
    $optimizer_binary = Slim::Utils::Misc::findbin('bliss-playlist-optimizer');
    Plugins::BetterCallBliss::BlissCompatibility::init($optimizer_binary);
    Plugins::BetterCallBliss::Jobs::init($optimizer_binary);
    Plugins::BetterCallBliss::ContextMenu::init();

    if (main::WEBUI) {
        require Plugins::BetterCallBliss::Settings;
        Plugins::BetterCallBliss::Settings->new;
        Plugins::BetterCallBliss::Web::init();
    }

    $class->SUPER::initPlugin();
    Slim::Control::Request::addDispatch(
        ['bettercallbliss', 'status'],
        [0, 1, 0, \&statusCommand],
    );

    Slim::Control::Request::addDispatch(
        ['bettercallbliss', 'job', '_cmd'],
        [0, 0, 1, \&jobCommand],
    );
    $initialized = 1;
    $log->info('initialized optimizer=' . ($optimizer_binary || 'missing'));
    return 1;
}

sub _loadStrings {
    my $dir = shift;
    my $strings = catfile($dir, 'strings.txt');
    return unless -r $strings;

    Slim::Utils::Strings::loadFile($strings);
    _activateStringsFile($strings);
}

sub _activateStringsFile {
    my $strings = shift;
    my $language = uc(Slim::Utils::Strings::getLanguage() || 'EN');
    my ($base_language) = split /_/, $language;
    my ($token, %values_by_token);

    if (open my $fh, '<:utf8', $strings) {
        while (my $line = <$fh>) {
            chomp $line;
            $line =~ s/\r\z//;
            next if $line =~ /^\s*\z/ || $line =~ /^#/;
            if ($line =~ /^(\S+)\z/) {
                $token = $1;
                next;
            }
            if (defined $token && $line =~ /^\t(\S*)\t(.+)\z/) {
                my $lang = uc($1 || $language);
                $values_by_token{$token}{$lang} = $2;
            }
        }
        close $fh;
    }

    for my $name (keys %values_by_token) {
        my $values = $values_by_token{$name};
        my $value = $values->{$language}
            || $values->{$base_language}
            || $values->{EN}
            || $values->{DE};
        Slim::Utils::Strings::setString($name, $value) if defined $value;
    }
}

sub _linuxBinaryPlatforms {
    my $signature = lc($Config{archname} || '');

    return ('aarch64-linux') if $signature =~ /\b(aarch64|arm64)\b/;
    return ('x86_64-linux') if $signature =~ /\b(x86_64|amd64)\b/;
    return ('armhf-linux') if $signature =~ /\b(armv6|armv7|armhf)\b/ || $signature =~ /gnueabihf/;

    return ('x86_64-linux', 'aarch64-linux', 'armhf-linux');
}

sub shutdownPlugin {
    Plugins::BetterCallBliss::Web::shutdown() if main::WEBUI;
    Plugins::BetterCallBliss::ContextMenu::shutdown();
    Plugins::BetterCallBliss::Jobs::shutdown();
    $initialized = 0;
}

sub optimizerBinary { return $optimizer_binary; }

sub _job_mode_label {
    my $job = shift || {};
    my $options = ref($job->{options}) eq 'HASH' ? $job->{options} : {};
    my $purpose = $options->{addition_purpose} || '';
    return 'Bliss me there...' if $job->{route_to_track};
    return 'Reorder only' if ($options->{extension_mode} || 'none') eq 'none';
    return 'Improve difficult transitions' if $purpose eq 'automatic'
        || ($options->{extension_mode} || '') eq 'automatic';
    return 'Extend playlist' if $purpose eq 'extend_playlist'
        || ($options->{extension_mode} || '') eq 'fixed_source_extension';
    return 'Strict gap bridge placement';
}

sub _job_payload {
    my $job = shift || {};
    my $options = ref($job->{options}) eq 'HASH' ? $job->{options} : {};
    my $started = int($job->{started_at} || 0);
    my $finished = int($job->{finished_at} || 0);
    my $elapsed = int(($finished || time()) - ($job->{started_at} || time()));
    $elapsed = 0 if $elapsed < 0;
    my $state = $job->{state} || 'unknown';
    my $status = $job->{stage} || $state;
    if ($state eq 'failed') {
        $status = 'Failed: ' . ($job->{error_code} || 'UNKNOWN_FAILURE');
    } elsif ($state eq 'completed') {
        $status = 'Completed';
        $status .= ' - added ' . (0 + ($job->{added_track_count} || 0))
            if ($options->{extension_mode} || 'none') ne 'none';
    } elsif ($state eq 'cancelled') {
        $status = 'Cancelled';
    }
    return {
        id => $job->{id} || '',
        state => $state,
        stage => $job->{stage} || '',
        status => $status,
        title => $job->{playlist_title} || 'Untitled source',
        mode => _job_mode_label($job),
        started_at => $started,
        finished_at => $finished,
        elapsed_seconds => $elapsed,
        can_cancel => $state eq 'running' ? 1 : 0,
        error_code => $job->{error_code} || '',
        error => $job->{error} || '',
        write_state => $job->{write_state} || '',
        write_error_code => $job->{write_error_code} || '',
        write_error => $job->{write_error} || '',
        source_track_count => 0 + ($job->{track_count} || 0),
        final_track_count => 0 + ($job->{final_track_count} || 0),
        added_track_count => 0 + ($job->{added_track_count} || 0),
    };
}

sub _job_lists_payload {
    my @summaries = map { _job_payload($_) } Plugins::BetterCallBliss::Jobs::all();
    my @running = grep { ($_->{state} || '') eq 'running' } @summaries;
    my @recent = grep { ($_->{state} || '') ne 'running' } @summaries;
    splice(@recent, 8) if @recent > 8;
    return (\@running, \@recent);
}

sub jobCommand {
    my $request = shift;
    my $cmd = $request->getParam('_cmd') || '';
    if ($request->paramUndefinedOrNotOneOf($cmd, ['status', 'cancel']) ) {
        $request->setStatusBadParams();
        return;
    }

    my $job_id = $request->getParam('job_id') || '';
    if (!$job_id) {
        $request->setStatusBadParams();
        return;
    }

    my ($job, $error);
    if ($cmd eq 'cancel') {
        eval { $job = Plugins::BetterCallBliss::Jobs::cancel($job_id); };
        $error = $@;
    } else {
        $job = Plugins::BetterCallBliss::Jobs::get($job_id);
    }

    if ($error) {
        $error =~ s/\s+/ /g;
        $request->addResult('state', 'failed');
        $request->addResult('error_code', 'JOB_COMMAND_FAILED');
        $request->addResult('error', $error);
    } elsif (!$job) {
        $request->addResult('state', 'not_found');
        $request->addResult('error_code', 'JOB_NOT_FOUND');
        $request->addResult('error', 'Preview job is no longer available');
    } else {
        $request->addResult('job', _job_payload($job));
    }

    my ($running, $recent) = _job_lists_payload();
    $request->addResult('running_jobs', $running);
    $request->addResult('recent_jobs', $recent);
    $request->setStatusDone();
}

sub statusCommand {
    my $request = shift;
    my $status = Plugins::BetterCallBliss::BlissCompatibility::snapshot();
    $request->addResult('ready', 0 + $status->{ready});
    $request->addResult('problem_count', scalar @{$status->{problems}});
    my $inventory = Plugins::BetterCallBliss::CandidateInventory::status();
    $request->addResult('candidate_inventory_ready', 0 + $inventory->{ready});
    $request->addResult(
        'non_lms_bliss_row_count', 0 + $inventory->{unmatched_row_count},
    ) if defined $inventory->{unmatched_row_count};
    $request->addResult('non_lms_bliss_audit_path', $inventory->{audit_path})
        if $inventory->{audit_path};
    $request->addResult('ux_contract', 'extras-job-editor-v22');
    $request->addResult(
        'working_mode',
        'per-job-adaptive/optimize-or-preserve/none-auto-extend/context-route-to-track/playlist-or-queue-output',
    );
    $request->setStatusDone();
}

1;
