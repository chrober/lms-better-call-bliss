use strict;
use warnings;
use Digest::SHA qw(sha256_hex);
use FindBin;
use Test::More;

my $root = "$FindBin::Bin/..";
my %canonical = (
    'BetterCallBliss/Plugins/BlissGuidance/SettingsModel.pm'
        => '83f9442e379b2707afe7a693eef02988093067e5aa3ad8a14a5cec40230d4952',
    'BetterCallBliss/Plugins/BlissGuidance/Policy.pm'
        => 'f25caefbea85a538ccfa05c851e78d10bfb7a4f8dbb0f9a01347931adffaf461',
    'BetterCallBliss/HTML/EN/plugins/BlissGuidance/settings/guidance-provider-controls.html'
        => 'd0b3dd3a4e03fe3f164de7b9e0a754d98a972a620d33ded045d6da481a0ca347',
    'BetterCallBliss/HTML/EN/plugins/BlissGuidance/settings/guidance-provider-controls.js'
        => '0957041d2ace48096e9ec101006a8f7185ade8e467b13a130170fb3488672c4e',
);

for my $relative (sort keys %canonical) {
    my $path = "$root/$relative";
    ok(-f $path, "$relative is vendored with the plugin");
    next unless -f $path;
    open my $fh, '<:raw', $path or die "cannot read $path: $!";
    my $content = do { local $/; <$fh> };
    close $fh;
    is(sha256_hex($content), $canonical{$relative},
        "$relative is byte-for-byte pinned to the canonical shared-host asset");
}

my $settings_template = "$root/BetterCallBliss/HTML/EN/plugins/BetterCallBliss/settings/bettercallbliss.html";
open my $template_fh, '<', $settings_template or die "cannot read $settings_template: $!";
my $template = do { local $/; <$template_fh> };
close $template_fh;
like($template, qr/PROCESS\s+"plugins\/BlissGuidance\/settings\/guidance-provider-controls\.html"/,
    'settings page renders the shared guidance partial');
like($template, qr/BlissGuidanceHostControls\.bindGuidanceProviderControls/,
    'settings page binds the shared guidance interaction asset');
like($template, qr/SET\s+guidance_ui\.available_token\s*=\s*"PLUGIN_BETTERCALLBLISS_GUIDANCE_PROVIDER_AVAILABLE"/,
    'settings page supplies the established Better Call Bliss labels for installed Settings.pm compatibility');

done_testing;
