use strict;
use warnings;
use utf8;
use FindBin;
use Test::More;

eval { require Template; 1 }
    or plan skip_all => 'Template Toolkit is required to render route results';
plan tests => 28;
my $base = "$FindBin::Bin/../BetterCallBliss";
open my $source_file, '<:encoding(UTF-8)', "$base/HTML/EN/plugins/BetterCallBliss/index.html" or die $!;
my $source = do { local $/; <$source_file> };
my ($route_template) = $source =~ /(\[% IF bettercallbliss_job\.route_to_track %\]\s*<div class="bea-info">.*?\[% END %\])\s*\[% IF bettercallbliss_job\.constraint_spacing_extension %\]/s;
die 'Could not locate route result' unless $route_template;
my ($weights_template) = $source =~ /(\[% IF bettercallbliss_form\.extras_weight_tempo\.defined %\]\s*<p class="bea-note">.*?<\/p>\s*\[% END %\])/s;
die 'Could not locate the Extras weights note' unless $weights_template;
open my $strings_file, '<:encoding(UTF-8)', "$base/strings.txt" or die $!;
my $strings = do { local $/; <$strings_file> };
my %strings;
while ($strings =~ /^(PLUGIN_BETTERCALLBLISS_[A-Z0-9_]+)\n\tEN\t([^\n]*)\n\tDE\t([^\n]*)/mg) {
    $strings{$1} = { EN => $2, DE => $3 };
}
for my $language (qw(EN DE)) {
    my $tt = Template->new({ FILTERS => { string => [ sub {
        my ($context, @args) = @_;
        return sub {
            my $key = shift;
            die "Missing $language translation for $key" unless exists $strings{$key}{$language};
            return sprintf($strings{$key}{$language}, @args);
        };
    }, 1 ] } });
    my $weights_out = '';
    ok($tt->process(\$weights_template, { bettercallbliss_form => {
        extras_weight_tempo => 20, extras_weight_timbre => 24,
        extras_weight_loudness => 3, extras_weight_chroma => 49,
    } }, \$weights_out), "$language Extras weights render") or diag($tt->error);
    like($weights_out, $language eq 'DE'
        ? qr/Gewichtungen.*Tempo 20.*Klangfarbe 24.*Lautstärke 3.*Chroma 49.*statisch/is
        : qr/weights.*tempo 20.*timbre 24.*loudness 3.*chroma 49.*static/is,
        "$language Extras weights are translated and all four values remain in order");
    for my $case (
        [direct => {}, $language eq 'DE' ? qr/kein Zwischentitel erforderlich/ : qr/no intermediate is needed/],
        [cautious => { route_no_beneficial_bridge => 1, route_quality_target_met => 1 }, $language eq 'DE' ? qr/Modelle.*widersprachen/s : qr/models disagreed/],
        [no_benefit => { route_no_beneficial_bridge => 1 }, $language eq 'DE' ? qr/65\. Perzentil/ : qr/percentile 65/],
        [best_effort => { route_best_effort => 1, added_track_count => 2 }, $language eq 'DE' ? qr/2 Zwischentiteln/ : qr/2 intermediate tracks/],
        [bridge => { added_track_count => 1 }, $language eq 'DE' ? qr/1 Zwischentitel/ : qr/1 intermediate track/],
        [models => { route_adaptive_model_comparison => 1, route_adaptive_algorithm => 'Adaptive', route_adaptive_direct_percent => 44, route_has_static_model => 1, route_static_direct_percent => 55, route_has_learned_model => 1, route_learned_direct_percent => 66 }, $language eq 'DE' ? qr/44\. Perzentil.*55\. Perzentil.*66\. Perzentil/s : qr/percentile 44.*percentile 55.*percentile 66/s],
    ) {
        my ($name, $extra, $expected) = @$case;
        my $job = { route_to_track => 1, route_direct_percent => 72, trigger_percent => 70, route_achieved_percent => 65, %$extra };
        my $out = '';
        ok($tt->process(\$route_template, { bettercallbliss_job => $job }, \$out), "$language $name renders") or diag($tt->error);
        like($out, $expected, "$language $name displays its route explanation");
    }
}
