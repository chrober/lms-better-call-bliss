use strict;
use warnings;
use Digest::SHA qw(sha256_hex);
use FindBin;
use Test::More;

my $root = "$FindBin::Bin/..";
my %canonical = (
    'BetterCallBliss/Plugins/BlissGuidance/SettingsModel.pm'
        => '7c016e487e45222102b20d9a4d231218c82ea1a7d2906ac4c92063530727ba90',
    'BetterCallBliss/Plugins/BlissGuidance/Policy.pm'
        => '6aef9836b94b48b1f702d66aad625b2556f8c91f69006033defff5e029a40f0a',
    'BetterCallBliss/HTML/EN/plugins/BlissGuidance/settings/guidance-provider-controls.html'
        => '51bc4d3a2aae742f767dd25d6191d5d1beacb06261034df0280340a74e4927ff',
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
