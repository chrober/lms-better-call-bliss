package Plugins::BlissEmAll::PlaylistWriter;

use strict;
use Errno qw(EEXIST);
use Fcntl qw(O_CREAT O_EXCL O_WRONLY);
use File::Copy qw(copy);
use File::Spec::Functions qw(catfile);
use Scalar::Util qw(blessed);
use Slim::Formats::Playlists::M3U;
use Slim::Schema;
use Slim::Utils::Misc;
use Slim::Utils::Text;
use Slim::Utils::Unicode;

sub _fail {
    my ($code, $message) = @_;
    die "$code: $message\n";
}

sub _same_urls {
    my ($expected, $actual) = @_;
    return 0 unless @$expected == @$actual;
    for my $index (0 .. $#$expected) {
        return 0 unless defined $actual->[$index]
            && $expected->[$index] eq $actual->[$index];
    }
    return 1;
}

sub _normalized_name {
    my $requested_name = shift;
    my $name = Slim::Utils::Misc::cleanupFilename($requested_name || '');
    $name =~ s/^\s+|\s+$//g;
    _fail('INVALID_OUTPUT_NAME', 'Enter a name for the optimized copy')
        unless length $name;
    _fail('INVALID_OUTPUT_NAME', 'The optimized copy name is too long')
        if length($name) > 255;
    return $name;
}

sub _target_for_name {
    my ($playlist_dir, $name) = @_;
    my $encoded_name = Slim::Utils::Unicode::encode_locale($name);
    my $path = catfile($playlist_dir, $encoded_name . '.m3u');
    my $url = Slim::Utils::Misc::fileURLFromPath($path);
    my $existing = Slim::Schema->objectForUrl({
        url => $url,
        playlist => 1,
    });
    return ($path, $url, blessed($existing) ? $existing : undef);
}

sub _name_exists {
    my ($playlist_dir, $name) = @_;
    my ($path, undef, $existing) = _target_for_name($playlist_dir, $name);
    return -e $path || blessed($existing);
}

sub available_copy_name {
    my $requested_name = shift;
    my $playlist_dir = Slim::Utils::Misc::getPlaylistDir();
    _fail('PLAYLIST_DIR_MISSING', 'The LMS playlist folder is not configured')
        unless $playlist_dir && -d $playlist_dir;
    my $base = _normalized_name($requested_name);
    return $base unless _name_exists($playlist_dir, $base);
    for my $number (2 .. 9999) {
        my $suffix = ' (' . $number . ')';
        my $stem = substr($base, 0, 255 - length($suffix));
        $stem =~ s/\s+$//;
        my $candidate = $stem . $suffix;
        return $candidate unless _name_exists($playlist_dir, $candidate);
    }
    _fail('OUTPUT_NAME_EXHAUSTED', 'Could not find a free optimized copy name');
}

sub _resolved_tracks {
    my $job = shift;
    my @selected = @{$job->{final_track_ids} || []};
    my $urls_by_id = $job->{track_urls} || {};
    my %source = map { $_ => 1 } @{$job->{source_track_ids} || []};
    my %bridge = map { $_ => 1 } @{$job->{bridge_track_ids} || []};
    _fail('INVALID_PREVIEW', 'The preview returned an unexpected track count')
        unless @selected == ($job->{final_track_count} || 0)
            && @selected == $job->{track_count}
                + scalar(@{$job->{bridge_track_ids} || []});

    my (%seen, %seen_url, @tracks, @urls);
    for my $id (@selected) {
        _fail('INVALID_PREVIEW', "Unknown selected track '$id'")
            unless exists $urls_by_id->{$id} && ($source{$id} || $bridge{$id});
        _fail('INVALID_PREVIEW', "Selected track '$id' occurs more than once")
            if $seen{$id}++;
        _fail('INVALID_PREVIEW', "Selected track '$id' duplicates another URL")
            if $seen_url{$urls_by_id->{$id}}++;
        my $track = Slim::Schema->objectForUrl($urls_by_id->{$id});
        _fail('TRACK_NOT_FOUND', "Selected track '$id' is no longer in LMS")
            unless blessed($track) && $track->can('url') && !$track->remote;
        push @tracks, $track;
        push @urls, $track->url;
    }
    _fail('INVALID_PREVIEW', 'The preview does not contain every source track')
        if scalar(grep { !$seen{$_} } keys %source);
    _fail('INVALID_PREVIEW', 'The preview does not contain every resolved bridge')
        if scalar(grep { !$seen{$_} } keys %bridge);
    return (\@tracks, \@urls);
}

sub create_copy {
    my ($job, $requested_name, $automatic_name) = @_;
    _fail('INVALID_JOB', 'A completed preview is required')
        unless $job && $job->{state} eq 'completed' && $job->{artifact};

    my $playlist_dir = Slim::Utils::Misc::getPlaylistDir();
    _fail('PLAYLIST_DIR_MISSING', 'The LMS playlist folder is not configured')
        unless $playlist_dir && -d $playlist_dir && -w $playlist_dir;

    my $name = _normalized_name($requested_name);
    $name = available_copy_name($name) if $automatic_name;
    my ($final_path, $final_url, $existing) =
        _target_for_name($playlist_dir, $name);
    _fail('OUTPUT_EXISTS', "A playlist named '$name' already exists")
        if -e $final_path || blessed($existing);

    my ($tracks, $urls) = _resolved_tracks($job);
    my $temp_path = catfile(
        $playlist_dir, '.blissemall-' . $job->{id} . '-' . $$ . '.tmp',
    );
    _fail('TEMP_COLLISION', 'The private output temporary file already exists')
        if -e $temp_path;

    my ($playlist, $published);
    my $ok = eval {
        my $written = Slim::Formats::Playlists::M3U->write(
            $urls, undef, $temp_path, 1,
        );
        _fail('WRITE_FAILED', 'The LMS M3U writer could not create the copy')
            unless defined $written && -f $temp_path && -s $temp_path;

        my @serialized = Slim::Formats::Playlists::M3U->read(
            $temp_path, undef,
            Slim::Utils::Misc::fileURLFromPath($temp_path),
        );
        my @serialized_urls = map {
            blessed($_) && $_->can('url') ? $_->url : ''
        } @serialized;
        _fail('SERIALIZATION_MISMATCH', 'Temporary M3U order did not verify')
            unless _same_urls($urls, \@serialized_urls);

        my $output;
        unless (sysopen($output, $final_path, O_WRONLY | O_CREAT | O_EXCL)) {
            _fail('OUTPUT_EXISTS', "A playlist named '$name' already exists")
                if $! == EEXIST;
            _fail('PUBLISH_FAILED', "Could not publish optimized copy: $!");
        }
        $published = 1;
        binmode($output, ':raw');
        my $copied = copy($temp_path, $output);
        my $closed = close($output);
        _fail('PUBLISH_FAILED', "Could not publish optimized copy: $!")
            unless $copied && $closed;
        unlink($temp_path)
            or _fail('TEMP_CLEANUP_FAILED', "Could not remove temporary copy: $!");

        $playlist = Slim::Schema->updateOrCreate({
            url => $final_url,
            playlist => 1,
            attributes => {
                TITLE => $name,
                CT => 'ssp',
            },
        });
        _fail('CATALOG_CREATE_FAILED', 'LMS did not create the playlist object')
            unless blessed($playlist) && $playlist->can('setTracks');

        my $titlesort = Slim::Utils::Text::ignoreCaseArticles($name);
        $playlist->set_column('titlesort', $titlesort);
        $playlist->set_column('titlesearch', $titlesort);
        $playlist->setTracks($tracks);
        $playlist->update;
        Slim::Schema->forceCommit;

        my @catalog_urls = map { $_->url } $playlist->tracks;
        _fail('CATALOG_VERIFY_FAILED', 'LMS catalog order did not verify')
            unless _same_urls($urls, \@catalog_urls);

        my @final_tracks = Slim::Formats::Playlists::M3U->read(
            $final_path, undef, $final_url,
        );
        my @final_urls = map {
            blessed($_) && $_->can('url') ? $_->url : ''
        } @final_tracks;
        _fail('FILE_VERIFY_FAILED', 'Published M3U order did not verify')
            unless _same_urls($urls, \@final_urls);
        1;
    };
    my $error = $@;

    unless ($ok) {
        unlink $temp_path if -e $temp_path;
        if ($playlist && blessed($playlist)) {
            eval {
                $playlist->setTracks([]);
                $playlist->delete;
                Slim::Schema->forceCommit;
            };
        }
        unlink $final_path if $published && -e $final_path;
        die $error || "CREATE_FAILED: Unknown playlist creation failure\n";
    }

    return {
        playlist_id => 0 + $playlist->id,
        title => $name,
        url => $final_url,
        path => $final_path,
        track_count => scalar @$urls,
    };
}

1;
