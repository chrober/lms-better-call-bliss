use strict;
use warnings;
use FindBin;
use File::Find;
use File::Spec;
use Test::More tests => 21;

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
    PLUGIN_BETTERCALLBLISS_ROUTE_LENGTH_POLICY
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
my $context_menu = slurp(File::Spec->catfile($plugin, 'ContextMenu.pm'));
like(
    $context_menu,
    qr/cmd\s*=>\s*\['bettercallbliss',\s*'route_to'\]/,
    'Bliss me there invokes a direct LMS command instead of opening Extras',
);
my $jobs = slurp(File::Spec->catfile($plugin, 'Jobs.pm'));
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
