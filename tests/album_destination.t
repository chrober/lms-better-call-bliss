use strict;
use warnings;
use FindBin;
use Test::More;

BEGIN {
    package Slim::Schema;
    our $album;
    sub find { return $album }
    $INC{'Slim/Schema.pm'} = __FILE__;
}

{
    package TestContributor;
    sub new { bless {name => $_[1]}, $_[0] }
    sub name { $_[0]->{name} }

    package TestAlbum;
    sub new { bless {tracks => $_[1]}, $_[0] }
    sub id { 77 }
    sub title { 'The Album' }
    sub contributor { TestContributor->new('The Artist') }
    sub tracks { @{$_[0]->{tracks}} }

    package TestTrack;
    sub new {
        my ($class, $id, $disc, $tracknum, $title, $remote, $audio) = @_;
        bless {
            id => $id, disc => $disc, tracknum => $tracknum, title => $title,
            remote => $remote, audio => $audio,
        }, $class;
    }
    sub id { $_[0]->{id} }
    sub disc { $_[0]->{disc} }
    sub tracknum { $_[0]->{tracknum} }
    sub title { $_[0]->{title} }
    sub remote { $_[0]->{remote} }
    sub audio { $_[0]->{audio} }
}

use lib "$FindBin::Bin/..";
require Plugins::BetterCallBliss::AlbumDestination;

$Slim::Schema::album = TestAlbum->new([
    TestTrack->new(5, 2, 1, 'Disc two', 0, 1),
    TestTrack->new(3, 1, 2, 'Second', 0, 1),
    TestTrack->new(2, 1, 1, 'First', 0, 1),
    TestTrack->new(4, 1, 2, 'Second alternate', 0, 1),
]);

my ($album, @tracks) =
    Plugins::BetterCallBliss::AlbumDestination::ordered_local_tracks(77);
is($album, $Slim::Schema::album, 'album object is returned with its tracks');
is_deeply([map { $_->id } @tracks], [2, 3, 4, 5],
    'a local audio album is returned in canonical disc, track, title, and id order');
is(Plugins::BetterCallBliss::AlbumDestination::label($album),
    'The Artist - The Album', 'album label includes album artist and title');

$Slim::Schema::album = TestAlbum->new([
    TestTrack->new(2, 1, 1, 'First', 0, 1),
    TestTrack->new(6, 1, 2, 'Remote', 1, 1),
]);
eval { Plugins::BetterCallBliss::AlbumDestination::ordered_local_tracks(77) };
like($@, qr/cannot be routed in full.*1 non-local or non-audio track/s,
    'an album with an unsupported member is rejected rather than truncated');

eval { Plugins::BetterCallBliss::AlbumDestination::ordered_local_tracks('oops') };
like($@, qr/Choose a destination album/, 'non-numeric album IDs are rejected');

$Slim::Schema::album = undef;
eval { Plugins::BetterCallBliss::AlbumDestination::ordered_local_tracks(999) };
like($@, qr/not found/, 'missing albums are rejected clearly');

done_testing();
