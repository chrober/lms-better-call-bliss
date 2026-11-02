package Plugins::BetterCallBliss::JobHistory;

use strict;
use warnings;
use File::Path qw(remove_tree);
use File::Spec;
use Fcntl qw(O_RDONLY O_WRONLY O_CREAT O_EXCL :flock);
use Errno qw(ENOENT);
use JSON::XS;
use Scalar::Util qw(blessed);

my $json = JSON::XS->new->utf8->canonical;
my $temp_serial = 0;

sub new {
    my ($class, $root) = @_;
    return bless { root => $root }, $class;
}

sub _id_ok { defined $_[0] && $_[0] =~ /\Apreview-\d+-[A-Za-z0-9_-]+\z/ }

sub _copy {
    my ($value) = @_;
    return $value unless ref $value;
    return $value if JSON::XS::is_bool($value);
    return undef if blessed($value);
    return [map { _copy($_) } @$value] if ref($value) eq 'ARRAY';
    if (ref($value) eq 'HASH') {
        return { map { $_ => _copy($value->{$_}) }
            grep { !/(?:api.?key|secret|password|credential|access.?token)/i } keys %$value };
    }
    return undef;
}

sub save {
    my ($self, $job) = @_;
    die 'Invalid history job' unless ref($job) eq 'HASH' && _id_ok($job->{id})
        && ($job->{state} || '') =~ /\A(?:running|completed|failed|cancelled)\z/;
    my $dir = File::Spec->catdir($self->{root}, $job->{id});
    die 'Invalid history directory' unless -d $dir && !-l $dir;
    my %snapshot = %$job;
    delete @snapshot{qw(process request_path result_path progress_path stderr_path semantic_path _history_busy)};
    my $capability = $job->{capability} || {};
    $snapshot{capability} = { map { $_ => $capability->{$_} }
        grep { exists $capability->{$_} } qw(algorithm matrix_available matrix_provider static_weight_sliders) };
    my $path = File::Spec->catfile($dir, 'history.json');
    my $tmp = File::Spec->catfile($dir, 'history.' . $$ . '.' . ++$temp_serial . '.tmp');
    sysopen my $fh, $tmp, O_WRONLY | O_CREAT | O_EXCL, 0600
        or die "Cannot write history: $!";
    binmode $fh, ':raw';
    print {$fh} $json->encode({ version => 1, job => _copy(\%snapshot) }) or die "Cannot write history: $!";
    close $fh or die "Cannot close history: $!";
    rename $tmp, $path or die "Cannot replace history: $!";
    return 1;
}

sub load {
    my ($self) = @_;
    opendir my $dh, $self->{root} or return ();
    my @ids = grep { _id_ok($_) } readdir $dh;
    closedir $dh;
    my @jobs;
    for my $id (@ids) {
        my $dir = File::Spec->catdir($self->{root}, $id);
        next if -l $dir || !-d $dir;
        my $path = File::Spec->catfile($dir, 'history.json');
        next if -l $path || !-f $path;
        open my $fh, '<:raw', $path or next;
        local $/; my $bytes = <$fh>; close $fh;
        my $entry = eval { $json->decode($bytes) };
        next unless ref($entry) eq 'HASH' && ($entry->{version} || 0) == 1
            && ref($entry->{job}) eq 'HASH' && ($entry->{job}->{id} || '') eq $id
            && ($entry->{job}->{state} || '') =~ /\A(?:running|completed|failed|cancelled)\z/
            && ($entry->{job}->{started_at} || 0) =~ /\A\d+(?:\.\d+)?\z/
            && ref($entry->{job}->{options}) eq 'HASH'
            && ref($entry->{job}->{capability}) eq 'HASH'
            && (($entry->{job}->{state} || '') ne 'completed'
                || ref($entry->{job}->{artifact}) eq 'HASH');
        push @jobs, $entry->{job};
    }
    return sort { $b->{started_at} <=> $a->{started_at} || $b->{id} cmp $a->{id} } @jobs;
}

sub result_in_use {
    my ($self, $id) = @_;
    return 1 unless _id_ok($id);
    my $dir = File::Spec->catdir($self->{root}, $id);
    return 1 if -l $dir || !-d $dir;
    my $path = File::Spec->catfile($dir, 'result.json');
    return 1 if -l $path;
    unless (sysopen my $fh, $path, O_RDONLY) {
        return $! == ENOENT ? 0 : 1;
    } else {
        my $locked = flock($fh, LOCK_EX | LOCK_NB);
        close $fh;
        return $locked ? 0 : 1;
    }
}

sub prune {
    my ($self, $protected) = @_;
    $protected ||= {};
    my @jobs = $self->load;
    return () if @jobs <= 8;
    splice(@jobs, 0, 8);
    my @removed;
    for my $job (@jobs) {
        next if ($job->{state} || '') eq 'running' || $protected->{$job->{id}};
        my $dir = File::Spec->catdir($self->{root}, $job->{id});
        next if -l $dir || !-d $dir;
        remove_tree($dir, { safe => 1 });
        push @removed, $job->{id} unless -e $dir || -l $dir;
    }
    return @removed;
}

1;
