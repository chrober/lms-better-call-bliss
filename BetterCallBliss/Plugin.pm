package Plugins::BetterCallBliss::Plugin;

use strict;
use base qw(Slim::Plugin::Base);

use File::Basename qw(dirname);
use File::Spec::Functions qw(catdir);
use Slim::Control::Request;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

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
        lastfm_weighting_weight => 25,
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

    $initialized = 1;
    $log->info('initialized optimizer=' . ($optimizer_binary || 'missing'));
    return 1;
}

sub shutdownPlugin {
    Plugins::BetterCallBliss::Web::shutdown() if main::WEBUI;
    Plugins::BetterCallBliss::ContextMenu::shutdown();
    Plugins::BetterCallBliss::Jobs::shutdown();
    $initialized = 0;
}

sub optimizerBinary { return $optimizer_binary; }

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
    $request->addResult('ux_contract', 'extras-job-editor-v14');
    $request->addResult(
        'working_mode',
        'per-job-adaptive/optimize-or-preserve/none-auto-exact-seed-growth/create-copy',
    );
    $request->setStatusDone();
}

1;
