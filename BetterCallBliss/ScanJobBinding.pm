package Plugins::BetterCallBliss::ScanJobBinding;
use strict;
use warnings;
use File::Spec;

sub bind {
    my ($built, $snapshot) = @_;
    die 'Invalid built request' unless ref($built) eq 'HASH'
        && ref($built->{capability}) eq 'HASH' && ref($built->{request}) eq 'HASH'
        && ref($built->{request}->{artifacts}) eq 'HASH'
        && ref($built->{request}->{artifacts}->{database}) eq 'HASH';
    my $live = $built->{capability}->{database};
    die 'Original database paths disagree' unless defined($live) && !ref($live) && length($live)
        && ($built->{request}->{artifacts}->{database}->{path} || '') eq $live;
    die 'Invalid snapshot context' unless ref($snapshot) eq 'HASH'
        && defined($snapshot->{directory}) && -d $snapshot->{directory} && !-l $snapshot->{directory}
        && ref($snapshot->{snapshots}) eq 'HASH';
    my $path = $snapshot->{snapshots}->{bliss};
    my $expected = File::Spec->catfile($snapshot->{directory}, 'bliss-snapshot.db');
    die 'Invalid Bliss database snapshot' unless defined($path) && !ref($path)
        && File::Spec->rel2abs($path) eq File::Spec->rel2abs($expected) && -f $path && !-l $path;
    return {
        %$built,
        live_database_path => $live,
        capability => {%{$built->{capability}}, database => $path},
        request => {%{$built->{request}}, artifacts => {%{$built->{request}->{artifacts}},
            database => {%{$built->{request}->{artifacts}->{database}}, path => $path}}},
    };
}

sub validate_scan_state {
    my ($job, $scanning, $scan_generation) = @_;
    return 1 if $job->{live_database_path};
    die "LIBRARY_SCAN_STARTED: The library changed while this preview was running; run it again.\n"
        if $scanning || (defined($job->{scan_generation}) && defined($scan_generation)
            && "$job->{scan_generation}" ne "$scan_generation");
    return 1;
}

1;
