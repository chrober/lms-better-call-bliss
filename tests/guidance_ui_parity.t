use strict;
use warnings;
use Digest::SHA qw(sha256_hex);
use FindBin;
use Test::More;

my $root = "$FindBin::Bin/..";
my %canonical = (
    'BetterCallBliss/Plugins/BlissGuidance/SettingsModel.pm'
        => '22646fb99551748cac14df242a1b2281eb569b295b2e82d1296370222afa4e31',
    'BetterCallBliss/Plugins/BlissGuidance/Policy.pm'
        => 'b8e5a91ad0014cfb2a2ab1ed4dc7227bc77c23a9e605bd55fff3a593c7ec3790',
    'BetterCallBliss/HTML/EN/plugins/BlissGuidance/settings/guidance-provider-controls.html'
        => '6e1e58263d0313f8a0a85aca0e8da3fd1848c40d132668d5afe8ff083c2dfb24',
    'BetterCallBliss/HTML/EN/plugins/BlissGuidance/settings/guidance-provider-controls.js'
        => 'cdcb46a952ffc48d83948bb295312e6a0b07ed42a5bf5af7dffdb7118c247c2c',
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

done_testing;
