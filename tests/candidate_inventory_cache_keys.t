use strict;
use warnings;
use FindBin;
use File::Temp qw(tempdir);
use Test::More;

BEGIN {
    package main; sub ISWINDOWS () { 0 }
    package DBI; $INC{'DBI.pm'} = __FILE__;
    package File::Slurp;
    sub import { no strict 'refs'; *{caller() . '::read_file'} = sub { open my $fh, '<:raw', $_[0] or die $!; local $/; return <$fh> }; *{caller() . '::write_file'} = sub { open my $fh, '>:raw', $_[0] or die $!; print {$fh} $_[-1]; close $fh } }
    $INC{'File/Slurp.pm'} = __FILE__;
    package JSON::XS; use JSON::PP (); sub new { JSON::PP->new } sub true () { 1 } sub false () { 0 } $INC{'JSON/XS.pm'} = __FILE__;
    package Slim::Music::Import; sub lastScanTime { 123 } $INC{'Slim/Music/Import.pm'} = __FILE__;
    package Slim::Schema; $INC{'Slim/Schema.pm'} = __FILE__;
    package TestLog; sub info { } sub warn { }
    package Slim::Utils::Log; sub logger { bless {}, 'TestLog' } $INC{'Slim/Utils/Log.pm'} = __FILE__;
    package Slim::Utils::Misc; $INC{'Slim/Utils/Misc.pm'} = __FILE__;
    package Slim::Utils::Timers; $INC{'Slim/Utils/Timers.pm'} = __FILE__;
    package Slim::Utils::Unicode; $INC{'Slim/Utils/Unicode.pm'} = __FILE__;
    package URI::Escape; sub import { no strict 'refs'; *{caller() . '::uri_unescape'} = sub { $_[0] } } $INC{'URI/Escape.pm'} = __FILE__;
}

use lib "$FindBin::Bin/..";
require Plugins::BetterCallBliss::CandidateInventory;
my $root = tempdir(CLEANUP => 1);
Plugins::BetterCallBliss::CandidateInventory::init($root);
my $all = Plugins::BetterCallBliss::CandidateInventory::_manifest_path_for_key('database|scan|roots||all');
my $virtual = Plugins::BetterCallBliss::CandidateInventory::_manifest_path_for_key('database|scan|roots|virtual|2');
isnt($all, $virtual, 'different candidate libraries have distinct manifests');
is($all, Plugins::BetterCallBliss::CandidateInventory::_manifest_path_for_key('database|scan|roots||all'),
    'the same complete cache identity resolves to the same manifest after restart');
like($virtual, qr{/candidate-inventory/state-[0-9a-f]{64}\.json$}, 'manifest filename is a safe digest');

my $dir = "$root/candidate-inventory";
my $json = JSON::PP->new->canonical->utf8;
my $identity_sha = 'a' x 64;
my $track_sha = 'b' x 64;
my $identity_path = "$dir/identities-$identity_sha.json";
my $lookup_path = "$dir/identities-$identity_sha.sqlite";
my $track_path = "$dir/track-identities-$track_sha.sqlite";
for my $path ($identity_path, $lookup_path, $track_path) { open my $fh, '>:raw', $path or die $!; close $fh }
for my $case (
    {key => 'database|scan|roots||all', library => '', count => 0, rows => [1, 2]},
    {key => 'database|scan|roots|virtual|2', library => 'virtual', count => 2, rows => [2]},
) {
    my $payload = $json->encode({schema_identity => 'lms-local-candidate-inventory-v1',
        database_cache_identity => 'database', lms_scan_time => 123,
        allowed_row_ids => $case->{rows}});
    my $sha = Digest::SHA::sha256_hex($payload);
    my $inventory_path = "$dir/inventory-$sha.json";
    open my $inventory, '>:raw', $inventory_path or die $!; print {$inventory} $payload; close $inventory;
    my $manifest = {builder_revision => Plugins::BetterCallBliss::CandidateInventory::BUILDER_REVISION(),
        cache_key => $case->{key}, candidate_library_id => $case->{library},
        candidate_library_track_count => $case->{count}, inventory_path => $inventory_path,
        inventory_sha256 => $sha, identity_path => $identity_path, identity_sha256 => $identity_sha,
        identity_lookup_path => $lookup_path, track_identity_path => $track_path, track_identity_sha256 => $track_sha};
    my $path = Plugins::BetterCallBliss::CandidateInventory::_manifest_path_for_key($case->{key});
    open my $fh, '>:raw', $path or die $!; print {$fh} $json->encode($manifest); close $fh;
}
for my $case (
    {key => 'database|scan|roots||all', library => '', rows => [1, 2]},
    {key => 'database|scan|roots|virtual|2', library => 'virtual', count => 2, rows => [2]},
    {key => 'database|scan|roots||all', library => '', rows => [1, 2]},
) {
    my $loaded = Plugins::BetterCallBliss::CandidateInventory::_load_cached_inventory(
        $case->{key}, 'database', 123, {id => $case->{library}}, undef, $case->{count});
    my $rows;
    if ($loaded && $loaded->{artifact}) {
        open my $fh, '<:raw', $loaded->{artifact}->{path} or die $!;
        local $/;
        $rows = $json->decode(<$fh>)->{allowed_row_ids};
        close $fh;
    }
    is_deeply($rows, $case->{rows}, 'the correct per-library manifest is reused across A/B/A switches');
}
{
    no warnings 'redefine';
    my @seen;
    local *Plugins::BetterCallBliss::CandidateInventory::_lyrion_database_identity = sub { 'lyrion-identity' };
    local *Plugins::BetterCallBliss::CandidateInventory::_candidate_library_membership = sub { return ({2 => 1, 3 => 1}, 'membership-b', 2) };
    local *Plugins::BetterCallBliss::CandidateInventory::_load_cached_inventory = sub {
        push @seen, $_[4];
        return {status => {ready => 1, allowed_row_count => 1, unmatched_row_count => 0}};
    };
    Plugins::BetterCallBliss::CandidateInventory::init($root);
    Plugins::BetterCallBliss::CandidateInventory::prepare(
        {music_roots => ['/music']}, 'database', {id => 'virtual'});
    is($seen[0], 'membership-b', 'cache validation checks membership identity, not only its count');
}
done_testing();
