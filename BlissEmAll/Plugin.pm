package Plugins::BlissEmAll::Plugin;

use strict;
use base qw(Slim::Plugin::OPMLBased);

use File::Basename qw(dirname);
use File::Spec::Functions qw(catdir);
use Slim::Control::Request;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

use Plugins::BlissEmAll::AppMenu;
use Plugins::BlissEmAll::BlissCompatibility;
use Plugins::BlissEmAll::Jobs;

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

    $prefs->init({output_suffix => 'Optimized', restart_count => 50});
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

    if (main::WEBUI) {
        require Plugins::BlissEmAll::Settings;
        Plugins::BlissEmAll::Settings->new;
    }

    $class->SUPER::initPlugin(
        feed   => \&Plugins::BlissEmAll::AppMenu::rootFeed,
        tag    => 'blissemall',
        is_app => 1,
        weight => 50,
    );
    Slim::Control::Request::addDispatch(
        ['blissemall', 'status'],
        [0, 1, 0, \&Plugins::BlissEmAll::AppMenu::statusCommand],
    );

    $initialized = 1;
    $log->info('initialized optimizer=' . ($optimizer_binary || 'missing'));
    return 1;
}

sub shutdownPlugin {
    Plugins::BlissEmAll::Jobs::shutdown();
    $initialized = 0;
}

sub optimizerBinary { return $optimizer_binary; }

1;
