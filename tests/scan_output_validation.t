use strict;
use warnings;
use FindBin;
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;
use DBI;
BEGIN {
    package Slim::Schema;
    our $dbh;
    sub dbh { $dbh }
    sub objectForUrl { my ($class, $url) = @_; $url =~ /([0-9]+)$/ ? TestTrack->new($1) : undef }
    $INC{'Slim/Schema.pm'} = __FILE__;
    package Slim::Music::VirtualLibraries;
    our $available = 1;
    sub getRealId { $available && $_[1] eq 'scope' ? 'scope' : undef }
    $INC{'Slim/Music/VirtualLibraries.pm'} = __FILE__;
    package TestTrack;
    sub new { bless {id => $_[1]}, $_[0] }
    sub id { $_[0]->{id} }
    sub url { 'file://' . $_[0]->{id} }
    sub remote { 0 }
    package Slim::Utils::Prefs;
    sub preferences { bless {}, 'TestPrefs' }
    sub import { no strict 'refs'; *{caller() . '::preferences'} = \&preferences }
    for my $module (qw(Slim/Formats/Playlists.pm Slim/Formats/Playlists/M3U.pm
        Slim/Utils/Misc.pm Slim/Utils/Prefs.pm Slim/Utils/Text.pm Slim/Utils/Unicode.pm)) {
        $INC{$module} = __FILE__;
    }
}
use lib "$FindBin::Bin/..";
use Plugins::BetterCallBliss::ScanOutputValidation;
use Plugins::BetterCallBliss::PlaylistWriter;
my $root = tempdir(CLEANUP => 1);
$Slim::Schema::dbh = DBI->connect('dbi:SQLite:dbname=' . File::Spec->catfile($root, 'library.db'), '', '', {RaiseError => 1});
$Slim::Schema::dbh->do('CREATE TABLE library_track (library TEXT, track INTEGER)');
$Slim::Schema::dbh->do(q{INSERT INTO library_track VALUES ('scope', 2)});
my $job = {live_database_path => '/live/bliss.db',
    candidate_inventory => {candidate_library_id => 'scope'},
    final_track_ids => ['source', 'bridge'], bridge_track_ids => ['bridge']};
my $tracks = [TestTrack->new(1), TestTrack->new(2)];
ok(Plugins::BetterCallBliss::ScanOutputValidation::validate($job, $tracks),
    'only additions are checked against the selected candidate library');
$Slim::Schema::dbh->do(q{DELETE FROM library_track WHERE library='scope' AND track=2});
my $ok = eval { Plugins::BetterCallBliss::ScanOutputValidation::validate($job, $tracks); 1 };
ok(!$ok && $@ =~ /CANDIDATE_LIBRARY_CHANGED/, 'removed membership fails closed before output');
my $started_before_scan = {%$job, live_database_path => undef};
$ok = eval { Plugins::BetterCallBliss::ScanOutputValidation::validate($started_before_scan, $tracks); 1 };
ok(!$ok && $@ =~ /CANDIDATE_LIBRARY_CHANGED/,
    'a normal job also rejects stale library membership if a scan starts later');
my $output_job = {%$job, state => 'completed', artifact => {}, track_count => 1,
    final_track_count => 2, source_track_ids => ['source'],
    track_urls => {source => 'file://1', bridge => 'file://2'}};
$ok = eval { Plugins::BetterCallBliss::PlaylistWriter::resolved_tracks_for_job($output_job); 1 };
ok(!$ok && $@ =~ /CANDIDATE_LIBRARY_CHANGED/, 'playlist and queue output reject an addition removed from its virtual library');
my $normal_output_job = {%$output_job, live_database_path => undef};
$ok = eval { Plugins::BetterCallBliss::PlaylistWriter::resolved_tracks_for_job($normal_output_job); 1 };
ok(!$ok && $@ =~ /CANDIDATE_LIBRARY_CHANGED/,
    'output also rejects stale additions for a preview started before the scan');
$Slim::Music::VirtualLibraries::available = 0;
$ok = eval { Plugins::BetterCallBliss::ScanOutputValidation::validate($job, $tracks); 1 };
ok(!$ok && $@ =~ /CANDIDATE_LIBRARY_CHANGED/, 'a removed virtual library fails closed');
$Slim::Music::VirtualLibraries::available = 1;
my $all = {%$job, candidate_inventory => {candidate_library_id => ''}};
ok(Plugins::BetterCallBliss::ScanOutputValidation::validate($all, $tracks),
    'the all-tracks scope does not require a virtual-library membership row');
my $unknown = {%$job, candidate_inventory => undef};
$ok = eval { Plugins::BetterCallBliss::ScanOutputValidation::validate($unknown, $tracks); 1 };
ok(!$ok && $@ =~ /CANDIDATE_LIBRARY_CHANGED/, 'missing captured candidate scope fails closed');
$Slim::Schema::dbh->disconnect;
done_testing;
