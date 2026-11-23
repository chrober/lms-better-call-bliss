package Plugins::BetterCallBliss::ScanOutputValidation;
use strict;
use warnings;
use Slim::Schema;
use Slim::Music::VirtualLibraries;

sub validate {
    my ($job, $tracks) = @_;
    my $bridges = $job->{bridge_track_ids} || [];
    return 1 unless @$bridges;
    my $inventory = $job->{candidate_inventory};
    return 1 if !$job->{live_database_path} && ref($inventory) ne 'HASH';
    die "CANDIDATE_LIBRARY_CHANGED: The captured candidate library is unavailable; run the preview again.\n"
        unless ref($inventory) eq 'HASH' && defined($inventory->{candidate_library_id})
            && !ref($inventory->{candidate_library_id});
    my $library = $inventory->{candidate_library_id};
    return 1 unless length $library;
    my $real = eval { Slim::Music::VirtualLibraries->getRealId($library) };
    die "CANDIDATE_LIBRARY_CHANGED: The selected virtual library is no longer available; run the preview again.\n"
        unless defined($real) && $real eq $library;
    my $ids = $job->{final_track_ids} || [];
    die "CANDIDATE_LIBRARY_CHANGED: The selected tracks cannot be verified; run the preview again.\n"
        unless ref($tracks) eq 'ARRAY' && ref($ids) eq 'ARRAY' && @$tracks == @$ids;
    my %bridge = map { $_ => 1 } @$bridges;
    my %seen;
    my $ok = eval {
        my $sth = Slim::Schema->dbh->prepare('SELECT 1 FROM library_track WHERE library = ? AND track = ? LIMIT 1');
        for my $index (0 .. $#$ids) {
            next unless $bridge{$ids->[$index]};
            my $id = $tracks->[$index]->id;
            die 'Invalid track identity' unless defined($id) && "$id" =~ /\A\d+\z/;
            $sth->execute($library, $id);
            die 'Track is outside the selected library' unless $sth->fetchrow_array;
            $seen{$ids->[$index]} = 1;
        }
        $sth->finish;
        die 'Missing selected bridge' if grep { !$seen{$_} } @$bridges;
        1;
    };
    die "CANDIDATE_LIBRARY_CHANGED: Added tracks cannot be verified in the selected virtual library; run the preview again.\n"
        unless $ok;
    return 1;
}

1;
