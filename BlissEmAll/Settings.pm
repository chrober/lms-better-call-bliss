package Plugins::BlissEmAll::Settings;

use strict;
use base qw(Slim::Web::Settings);
use Slim::Utils::Prefs;

my $prefs = preferences('plugin.blissemall');

sub name {
    return Slim::Web::HTTP::CSRF->protectName('PLUGIN_BLISSEMALL_SETTINGS');
}

sub page {
    return Slim::Web::HTTP::CSRF->protectURI(
        'plugins/BlissEmAll/settings/blissemall.html'
    );
}

sub prefs { return ($prefs, qw(output_suffix restart_count)); }

sub handler {
    my ($class, $client, $params) = @_;
    if (defined $params->{pref_restart_count}) {
        my $value = int($params->{pref_restart_count});
        $params->{pref_restart_count} = 10 if $value < 10;
        $params->{pref_restart_count} = 500 if $value > 500;
    }
    return $class->SUPER::handler($client, $params);
}

1;
