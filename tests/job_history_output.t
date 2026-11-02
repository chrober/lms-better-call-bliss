use strict;
use warnings;
use FindBin;
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test::More;

BEGIN {
    package HistoryOutputPrefs;
    sub get { undef }
    package Slim::Utils::Prefs;
    sub preferences { bless {}, 'HistoryOutputPrefs' }
    sub import { no strict 'refs'; *{caller() . '::preferences'} = \&preferences }
    package HistoryOutputTrack;
    sub url { $_[0]->{url} }
    sub remote { 0 }
    package Slim::Schema;
    our %tracks;
    sub objectForUrl { $tracks{$_[1]} }
    package Slim::Formats::Playlists::M3U;
    our @tracks;
    sub read { @tracks }
    package Slim::Formats::Playlists;
    sub parseList { @Slim::Formats::Playlists::M3U::tracks }
    for my $module (qw(
        Slim/Formats/Playlists.pm Slim/Formats/Playlists/M3U.pm Slim/Schema.pm Slim/Utils/Misc.pm
        Slim/Utils/Prefs.pm Slim/Utils/Text.pm Slim/Utils/Unicode.pm
    )) { $INC{$module} = __FILE__ }
}

require "$FindBin::Bin/../BetterCallBliss/JobHistory.pm";
require "$FindBin::Bin/../BetterCallBliss/PlaylistWriter.pm";

my $root = tempdir(CLEANUP => 1);
my $id = 'preview-4000-output';
make_path("$root/$id");
my $history = Plugins::BetterCallBliss::JobHistory->new($root);
my @urls = ('file:///source.flac', 'file:///bridge.flac');
for my $url (@urls) {
    $Slim::Schema::tracks{$url} = bless { url => $url }, 'HistoryOutputTrack';
}
$history->save({
    id => $id, state => 'completed', started_at => 4000,
    options => {}, capability => {}, artifact => {}, track_count => 1,
    source_track_ids => ['source'], bridge_track_ids => ['bridge'], final_track_count => 2,
    final_track_ids => ['source', 'bridge'],
    track_urls => { source => $urls[0], bridge => $urls[1] },
});
my ($restored) = $history->load;
my (undef, $resolved) = Plugins::BetterCallBliss::PlaylistWriter::resolved_tracks_for_job($restored);
is_deeply($resolved, \@urls, 'restored preview still resolves the exact tracks in their original result order');
delete $Slim::Schema::tracks{$urls[1]};
my $ok = eval { Plugins::BetterCallBliss::PlaylistWriter::resolved_tracks_for_job($restored); 1 };
ok(!$ok && $@ =~ /TRACK_NOT_FOUND/, 'restored output rejects tracks removed from the library');

@Slim::Formats::Playlists::M3U::tracks = ($Slim::Schema::tracks{$urls[0]});
my $same_source = eval {
    Plugins::BetterCallBliss::PlaylistWriter::_verify_source_snapshot($restored, '/tmp/source.m3u', 'file:///source.m3u');
    1;
};
ok($same_source, 'restored preview can still overwrite an unchanged source playlist');
{
    no warnings 'redefine';
    local *Slim::Formats::Playlists::M3U::read = sub { die 'M3U parser cannot read PLS' };
    my $other_format = eval {
        Plugins::BetterCallBliss::PlaylistWriter::_verify_source_snapshot($restored, '/tmp/source.pls', 'file:///source.pls');
        1;
    };
    ok($other_format, 'source verification uses Lyrion playlist format dispatch for PLS files');
}
@Slim::Formats::Playlists::M3U::tracks = (bless { url => 'file:///changed.flac' }, 'HistoryOutputTrack');
my $changed_source = eval {
    Plugins::BetterCallBliss::PlaylistWriter::_verify_source_snapshot($restored, '/tmp/source.m3u', 'file:///source.m3u');
    1;
};
ok(!$changed_source && $@ =~ /SOURCE_PLAYLIST_CHANGED/, 'overwrite rejects a source changed after the preview');

done_testing();
