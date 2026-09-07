package Plugins::BetterCallBliss::AlbumDestination;

use strict;
use Scalar::Util qw(blessed);
use Slim::Schema;

sub label {
    my $album = shift;
    return 'Unknown album' unless $album;
    my $artist = eval { $album->contributor->name } || 'Various Artists';
    my $title = eval { $album->title } || eval { $album->name } || 'Unknown Album';
    return "$artist - $title";
}

sub ordered_local_tracks {
    my $album_id = shift;
    die "Choose a destination album"
        unless defined $album_id && "$album_id" =~ /^\d+$/;
    my $album = Slim::Schema->find('Album', int($album_id));
    die "Destination album was not found in the LMS library"
        unless blessed($album) && $album->can('tracks');
    my @tracks = $album->tracks;
    my @unsupported = grep {
        !$_ || !$_->can('id') || $_->remote || !eval { $_->audio }
    } @tracks;
    die "Destination album cannot be routed in full because it contains "
        . scalar(@unsupported) . " non-local or non-audio track(s)"
        if @unsupported;
    @tracks = sort {
        (0 + (eval { $a->disc } || 0)) <=> (0 + (eval { $b->disc } || 0))
            || (0 + (eval { $a->tracknum } || 0))
                <=> (0 + (eval { $b->tracknum } || 0))
            || lc(eval { $a->title } || '') cmp lc(eval { $b->title } || '')
            || $a->id <=> $b->id
    } @tracks;
    die "Destination album has no local playable tracks" unless @tracks;
    return ($album, @tracks);
}

1;
