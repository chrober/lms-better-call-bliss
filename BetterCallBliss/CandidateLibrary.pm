package Plugins::BetterCallBliss::CandidateLibrary;

use strict;
use Slim::Music::VirtualLibraries;

sub normalize_id {
    my $value = shift;
    $value = '' unless defined $value;
    $value =~ s/^\s+|\s+$//g;
    return '' if !length($value) || $value eq '0' || $value eq '-1';

    my $id = Slim::Music::VirtualLibraries->getRealId($value);
    die "Candidate library is no longer available" unless defined $id && length $id;
    return $id;
}

sub active_id {
    my $client = shift;
    my $id = Slim::Music::VirtualLibraries->getLibraryIdForClient($client) || '';
    return normalize_id($id);
}

sub describe {
    my ($value, $client) = @_;
    my $id = normalize_id($value);
    return {
        id => '',
        name => 'All tracks',
        virtual => 0,
    } unless length $id;

    my $name = Slim::Music::VirtualLibraries->getNameForId($id, $client);
    die "Candidate library is no longer available" unless defined $name && length $name;
    return {
        id => $id,
        name => $name,
        virtual => 1,
    };
}

sub choices {
    my $client = shift;
    my @choices = ({
        id => '',
        name => 'All tracks',
        count => undef,
    });
    my $libraries = Slim::Music::VirtualLibraries->getLibraries() || {};
    for my $id (keys %$libraries) {
        my $name = Slim::Music::VirtualLibraries->getNameForId($id, $client);
        next unless defined $name && length $name;
        push @choices, {
            id => $id,
            name => $name,
            count => 0 + Slim::Music::VirtualLibraries->getTrackCount($id),
        };
    }
    my $all = shift @choices;
    @choices = sort {
        lc($a->{name} || '') cmp lc($b->{name} || '')
            || ($a->{id} || '') cmp ($b->{id} || '')
    } @choices;
    return [$all, @choices];
}

1;
