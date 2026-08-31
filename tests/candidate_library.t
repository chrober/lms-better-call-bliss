use strict;
use warnings;
use FindBin;
use Test::More;

BEGIN {
    package Slim::Music::VirtualLibraries;
    our %libraries = (
        '4d2ba37f' => {id => 'noAudioBooks', name => 'All Music without Audiobooks'},
        'abcd1234' => {id => 'christmas', name => 'Christmas'},
    );
    sub getRealId {
        my ($class, $id) = @_;
        return $id if exists $libraries{$id};
        for my $real (keys %libraries) {
            return $real if $libraries{$real}->{id} eq $id;
        }
        return;
    }
    sub getLibraryIdForClient { return '4d2ba37f' }
    sub getNameForId { return $libraries{$_[1]}->{name} || '' }
    sub getLibraries { return \%libraries }
    sub getTrackCount { return $_[1] eq '4d2ba37f' ? 66676 : 420 }
    $INC{'Slim/Music/VirtualLibraries.pm'} = __FILE__;
}

use lib "$FindBin::Bin/..";
require Plugins::BetterCallBliss::CandidateLibrary;

is(Plugins::BetterCallBliss::CandidateLibrary::active_id(undef), '4d2ba37f',
    'the player/global active virtual library is detected');
is(Plugins::BetterCallBliss::CandidateLibrary::normalize_id('noAudioBooks'),
    '4d2ba37f', 'stable virtual-library names resolve to LMS internal ids');
is_deeply(
    Plugins::BetterCallBliss::CandidateLibrary::describe('4d2ba37f'),
    {
        id => '4d2ba37f',
        name => 'All Music without Audiobooks',
        virtual => 1,
    },
    'a selected virtual library becomes a frozen job descriptor',
);
is_deeply(
    Plugins::BetterCallBliss::CandidateLibrary::describe(''),
    {id => '', name => 'All tracks', virtual => 0},
    'an empty selection explicitly means all local tracks',
);
my $choices = Plugins::BetterCallBliss::CandidateLibrary::choices(undef);
is($choices->[0]->{id}, '', 'All tracks is the first dropdown choice');
is($choices->[1]->{id}, '4d2ba37f',
    'virtual-library dropdown choices are sorted by display name');
is($choices->[1]->{count}, 66676,
    'dropdown choice reports Lyrion virtual-library membership count');

eval { Plugins::BetterCallBliss::CandidateLibrary::normalize_id('missing') };
like($@, qr/no longer available/,
    'a stale or forged virtual-library id is rejected before job start');

done_testing();
