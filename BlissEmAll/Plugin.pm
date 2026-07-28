package Plugins::BlissEmAll::Plugin;

use strict;
use base qw(Slim::Plugin::Base);

use File::Basename qw(dirname);
use File::Spec::Functions qw(catdir);
use Slim::Control::Request;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

use Plugins::BlissEmAll::BlissCompatibility;
use Plugins::BlissEmAll::CandidateInventory;
use Plugins::BlissEmAll::ContextMenu;
use Plugins::BlissEmAll::Jobs;
use Plugins::BlissEmAll::Web;

my $log = Slim::Utils::Log->addLogCategory({
    category     => 'plugin.blissemall',
    defaultLevel => 'INFO',
    description  => 'DEBUG_PLUGIN_BLISSEMALL',
    logGroups    => 'SCANNER',
});
my $prefs = preferences('plugin.blissemall');
my $initialized = 0;
my $optimizer_binary;

sub getDisplayName { return 'PLUGIN_BLISSEMALL_NAME'; }

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
        listenbrainz_enabled => 0,
    });
    my $dir = dirname(__FILE__);
    if (main::ISWINDOWS) {
        Slim::Utils::Misc::addFindBinPaths(catdir($dir, 'Bin', 'windows'));
    } elsif (main::ISMAC) {
        Slim::Utils::Misc::addFindBinPaths(catdir($dir, 'Bin', 'mac'));
    } else {
        Slim::Utils::Misc::addFindBinPaths(catdir($dir, 'Bin', 'aarch64-linux'));
        Slim::Utils::Misc::addFindBinPaths(catdir($dir, 'Bin', 'x86_64-linux'));
    }
    $optimizer_binary = Slim::Utils::Misc::findbin('bliss-playlist-optimizer');
    Plugins::BlissEmAll::BlissCompatibility::init($optimizer_binary);
    Plugins::BlissEmAll::Jobs::init($optimizer_binary);
    Plugins::BlissEmAll::ContextMenu::init();

    if (main::WEBUI) {
        require Plugins::BlissEmAll::Settings;
        Plugins::BlissEmAll::Settings->new;
        Plugins::BlissEmAll::Web::init();
    }

    $class->SUPER::initPlugin();
    Slim::Control::Request::addDispatch(
        ['blissemall', 'status'],
        [0, 1, 0, \&statusCommand],
    );

    $initialized = 1;
    $log->info('initialized optimizer=' . ($optimizer_binary || 'missing'));
    return 1;
}

sub shutdownPlugin {
    Plugins::BlissEmAll::Web::shutdown() if main::WEBUI;
    Plugins::BlissEmAll::ContextMenu::shutdown();
    Plugins::BlissEmAll::Jobs::shutdown();
    $initialized = 0;
}

sub optimizerBinary { return $optimizer_binary; }

sub statusCommand {
    my $request = shift;
    my $status = Plugins::BlissEmAll::BlissCompatibility::snapshot();
    $request->addResult('ready', 0 + $status->{ready});
    $request->addResult('problem_count', scalar @{$status->{problems}});
    my $inventory = Plugins::BlissEmAll::CandidateInventory::status();
    $request->addResult('candidate_inventory_ready', 0 + $inventory->{ready});
    $request->addResult(
        'non_lms_bliss_row_count', 0 + $inventory->{unmatched_row_count},
    ) if defined $inventory->{unmatched_row_count};
    $request->addResult('non_lms_bliss_audit_path', $inventory->{audit_path})
        if $inventory->{audit_path};
    $request->addResult('ux_contract', 'extras-job-editor-v10');
    $request->addResult(
        'working_mode',
        'per-job-adaptive/optimize-or-preserve/none-auto-exact/create-copy',
    );
    $request->setStatusDone();
}

1;
