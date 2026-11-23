#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use JSON::XS ();

require "$FindBin::Bin/ScanDatabaseSnapshot.pm";
die "Expected Lyrion database, Bliss database and job directory\n" unless @ARGV == 3;
eval { setpriority(0, 0, 10) } if $^O ne 'MSWin32';
my $snapshots = Plugins::BetterCallBliss::ScanDatabaseSnapshot::capture_pair(@ARGV);
binmode STDOUT, ':raw';
print JSON::XS->new->utf8->canonical->encode($snapshots)
    or die "Cannot write snapshot descriptor: $!";
