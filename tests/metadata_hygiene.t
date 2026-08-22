use strict;
use warnings;
use FindBin;
use File::Find;
use File::Spec;
use Test::More tests => 36;

my $root = File::Spec->catdir($FindBin::Bin, '..');
my $plugin = File::Spec->catdir($root, 'BetterCallBliss');

sub slurp {
    my $path = shift;
    open my $fh, '<:raw', $path or die "Cannot read $path: $!";
    local $/;
    return <$fh>;
}

my $install = slurp(File::Spec->catfile($plugin, 'install.xml'));
like($install, qr/<name>PLUGIN_BETTERCALLBLISS_NAME<\/name>/,
    'install.xml uses the localized plugin name token');
like($install, qr/<description>PLUGIN_BETTERCALLBLISS_DESC<\/description>/,
    'install.xml uses the localized plugin description token');
like($install, qr/<creator>Christoph O'Bermair<\/creator>/,
    'install.xml carries the expected author name');

my ($icon) = $install =~ m{<icon>([^<]+)</icon>};
ok($icon, 'install.xml declares an icon');
my $icon_path = $icon;
$icon_path =~ s{^plugins/BetterCallBliss/}{};
my $classic_web_icon = File::Spec->catfile(
    $plugin, 'HTML', 'EN', 'plugins', 'BetterCallBliss', $icon_path,
);
ok(-f $classic_web_icon,
    'declared icon exists in the classic-web plugin tree');

my $strings_path = File::Spec->catfile($plugin, 'strings.txt');
my $strings = slurp($strings_path);
unlike($strings, qr/\r/,
    'strings.txt is LF-only so LMS does not retain carriage returns in tokens');

for my $token (qw(
    PLUGIN_BETTERCALLBLISS_NAME
    PLUGIN_BETTERCALLBLISS_DESC
    PLUGIN_BETTERCALLBLISS_SETTINGS
    PLUGIN_BETTERCALLBLISS_RESTART_COUNT
    PLUGIN_BETTERCALLBLISS_VARIATION_PERCENT
    PLUGIN_BETTERCALLBLISS_ROUTE_DIRECT_CAUTION
    PLUGIN_BETTERCALLBLISS_ROUTE_LENGTH_POLICY
    PLUGIN_BETTERCALLBLISS_ROUTE_SEARCH_EFFORT
    PLUGIN_BETTERCALLBLISS_ROUTE_MAX_INTERMEDIATES
    PLUGIN_BETTERCALLBLISS_ROUTE_EXACT_INTERMEDIATES
    PLUGIN_BETTERCALLBLISS_LASTFM_TRACK_GUIDANCE
    PLUGIN_BETTERCALLBLISS_LASTFM_ARTIST_GUIDANCE
)) {
    like($strings, qr/^$token\n\tEN\t[^\n]+\n\tDE\t[^\n]+/m,
        "$token has EN and DE localizations");
}

my @tokens = $strings =~ /^(PLUGIN_BETTERCALLBLISS_[A-Z0-9_]+)$/mg;
my %token_count;
$token_count{$_}++ for @tokens;
is_deeply(
    [sort grep { $token_count{$_} > 1 } keys %token_count],
    [],
    'strings.txt contains no duplicate localization tokens',
);

my $extras = slurp(File::Spec->catfile(
    $plugin, 'HTML', 'EN', 'plugins', 'BetterCallBliss', 'index.html',
));
my $plugin_module = slurp(File::Spec->catfile($plugin, 'Plugin.pm'));
my $settings = slurp(File::Spec->catfile(
    $plugin, 'HTML', 'EN', 'plugins', 'BetterCallBliss', 'settings',
    'bettercallbliss.html',
));
like(
    $settings,
    qr/job-defaults-section-header.*?route-section-header.*?lastfm-section-header.*?roadmap-section-header/s,
    'settings page groups preferences into collapsible sections',
);
like(
    $settings,
    qr/mskslider\..*?updateRouteLengthPolicy.*?route_min_intermediates.*?route_max_intermediates.*?route_exact_intermediates.*?route_direct_caution/s,
    'route policy disables both inapplicable inputs and Material sliders',
);
like(
    $settings,
    qr/updateLastFmGuidance.*?lastfm_track_guidance_percent.*?lastfm_artist_guidance_percent/s,
    'Last.fm guidance inputs follow the provider enable checkbox',
);
like(
    $plugin_module,
    qr/lastfm_track_guidance_percent\s*=>\s*25,.*?lastfm_artist_guidance_percent\s*=>\s*25,/s,
    'new installations default both Last.fm guidance controls to 25 percent',
);
like(
    $plugin_module,
    qr/preference_defaults_version.*?<\s*2.*?lastfm_track_guidance_percent.*?lastfm_artist_guidance_percent.*?set\(\$name,\s*25\).*?==\s*75/s,
    'legacy untouched 75 percent guidance defaults migrate once to 25 percent',
);
like(
    $plugin_module,
    qr/\['bettercallbliss',\s*'route_to'\]\s*,\s*\[1,\s*0,\s*1,\s*\\&routeToCommand\]/s,
    'route_to requires a player and permits tagged destination parameters',
);

my $context_menu = slurp(File::Spec->catfile($plugin, 'ContextMenu.pm'));
like(
    $context_menu,
    qr/cmd\s*=>\s*\['bettercallbliss',\s*'route_to'\]/,
    'Bliss me there invokes a direct LMS command instead of opening Extras',
);
my $jobs = slurp(File::Spec->catfile($plugin, 'Jobs.pm'));
like(
    $plugin_module,
    qr/my \$optimizer_supports_trusted_request\s*=\s*_optimizerSupportsTrustedRequest.*?Jobs::init\(.*?\$optimizer_supports_trusted_request/s,
    'plugin enables trusted requests only after optimizer capability detection',
);
like(
    $jobs,
    qr/push \@params,\s*'--trusted-request'\s+if \$optimizer_supports_trusted_request/,
    'optimizer launch adds the trusted flag only when the capability is advertised',
);
like(
    $jobs,
    qr/\$job->\{state\}\s+eq\s+'completed'\s+&&\s+\$job->\{auto_apply\}.*?send_to_queue\(\$job_id/s,
    'completed quick routes automatically send their suffix to the player queue',
);
unlike(
    $extras,
    qr/first route-to-track slice|native multi-bridge gap support/,
    'Extras page no longer describes Bliss me there as an incomplete first slice',
);
like(
    $extras,
    qr/route_best_effort.*?smoothest repeat-safe route/s,
    'Extras reports a quality-target miss as an explicit best-effort route',
);
my $web = slurp(File::Spec->catfile($plugin, 'Web.pm'));
like(
    $web,
    qr/route_best_effort.*?\$preview->\{best_effort\}/s,
    'Web view maps native best-effort metadata',
);
like(
    $web,
    qr/route_achieved_percent.*?achieved_max_leg_percentile/s,
    'Web view maps the achieved worst-leg percentile',
);
like(
    $web,
    qr/route_model_comparison.*?static-weights.*?learned-matrix/s,
    'Web view maps both acoustic views for destination-route diagnostics',
);
like(
    $extras,
    qr/Acoustic model check:.*?configured adaptive context.*?governed this route/s,
    'destination-route result explains that the configured adaptive context governed',
);

my @committed_binary_candidates;
find(
    {
        wanted => sub {
            return unless -f $_;
            return unless $File::Find::name =~ m{[\\/]Bin[\\/][^\\/]+[\\/]bliss-playlist-optimizer(?:\.exe)?$};
            push @committed_binary_candidates, $File::Find::name;
        },
        no_chdir => 1,
    },
    $plugin,
);
is_deeply(\@committed_binary_candidates, [],
    'source checkout does not commit native optimizer binaries');
