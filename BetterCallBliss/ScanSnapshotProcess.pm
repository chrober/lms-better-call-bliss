package Plugins::BetterCallBliss::ScanSnapshotProcess;
use strict;
use warnings;
use File::Basename qw(dirname);
use File::Spec;
use File::Temp qw(tempdir);
use Errno qw(ENOTEMPTY EEXIST);
use Config ();
use JSON::XS ();
use Time::HiRes qw(time);
use Plugins::BetterCallBliss::ScanDatabaseSnapshot;
use Plugins::BlissLibrary::Worker;

sub start {
    my ($class, %args) = @_;
    for my $key (qw(parent_dir lyrion_path bliss_path)) {
        die "Missing $key" unless defined($args{$key}) && !ref($args{$key}) && length($args{$key});
    }
    my $timeout = $args{timeout_seconds} // 120;
    die 'Invalid snapshot timeout' unless $timeout =~ /\A\d+\z/ && $timeout > 0;
    my $dir = tempdir('scan-snapshot-XXXXXXXX', DIR => $args{parent_dir}, CLEANUP => 0);
    my $stdout = File::Spec->catfile($dir, 'worker.out');
    my $stderr = File::Spec->catfile($dir, 'worker.err');
    my $script = File::Spec->catfile(dirname(__FILE__), 'scan-snapshot-worker.pl');
    my $separator = $Config::Config{path_sep};
    my @existing = split /\Q$separator\E/, ($ENV{PERL5LIB} || '');
    local $ENV{PERL5LIB} = join($separator, grep { defined($_) && !ref($_) && -d $_ } (@existing, @INC));
    my $worker = eval { Plugins::BlissLibrary::Worker->start(
        command => [$^X, $script, $args{lyrion_path}, $args{bliss_path}, $dir],
        stdout_path => $stdout, stderr_path => $stderr,
    ) };
    unless ($worker) {
        my $error = $@ || 'Could not start snapshot worker';
        unlink $stdout, $stderr;
        rmdir $dir;
        die $error;
    }
    return bless {worker => $worker, dir => $dir, stdout => $stdout, stderr => $stderr,
        deadline => time + $timeout}, $class;
}

sub cancel {
    my ($self) = @_;
    return if $self->{terminal};
    $self->{cancel_reason} ||= 'cancelled';
    $self->{worker}->cancel;
    return 1;
}

sub pid {
    my ($self) = @_;
    my $process = $self->{worker}->{proc};
    return $process && $process->can('pid') ? $process->pid : undef;
}

sub poll {
    my ($self) = @_;
    return $self->{terminal} if $self->{terminal};
    my $status = $self->{worker}->poll;
    if ($status->{state} eq 'running' && time >= $self->{deadline}) {
        $self->{cancel_reason} = 'timeout';
        $self->{worker}->cancel;
        return {state => 'running'};
    }
    return {state => 'running'} if $status->{state} eq 'running' || $status->{state} eq 'cancelling';
    if ($self->{cancel_reason}) {
        return $self->{terminal} = {state => $self->{cancel_reason} eq 'cancelled' ? 'cancelled' : 'failed',
            error => $self->{cancel_reason} eq 'timeout' ? 'Snapshot worker timed out' : 'Snapshot worker cancelled'};
    }
    if ($status->{state} ne 'completed' && !$status->{exit_status_unknown}) {
        my $error = '';
        if (open my $fh, '<:raw', $self->{stderr}) { read($fh, $error, 1024); close $fh }
        $error =~ s/\s+/ /g;
        return $self->{terminal} = {state => 'failed', error => $error || $status->{error} || 'Snapshot worker failed'};
    }
    my $bytes = '';
    if (open my $fh, '<:raw', $self->{stdout}) { read($fh, $bytes, 8192); close $fh }
    my $snapshots = eval { JSON::XS->new->utf8->decode($bytes) };
    for my $role (qw(lyrion bliss)) {
        my $expected = File::Spec->catfile($self->{dir}, "$role-snapshot.db");
        return $self->{terminal} = {state => 'failed', error => 'Invalid snapshot worker result'}
            unless ref($snapshots) eq 'HASH' && defined($snapshots->{$role}) && !ref($snapshots->{$role})
                && $snapshots->{$role} eq $expected && -f $expected && !-l $expected;
    }
    return $self->{terminal} = {state => 'completed', directory => $self->{dir}, snapshots => $snapshots};
}

sub cleanup {
    my ($self, %options) = @_;
    die 'Cannot clean up a running snapshot worker' unless $self->{terminal};
    Plugins::BetterCallBliss::ScanDatabaseSnapshot::cleanup_pair($self->{dir});
    if ($options{discard_inventory}) {
        my $inventory = File::Spec->catdir($self->{dir}, 'candidate-inventory');
        if (-d $inventory && !-l $inventory) {
            opendir my $dh, $inventory or die "Cannot inspect job inventory: $!";
            my @names = grep {
                /\A(?:current\.json|(?:state|inventory|identities|track-identities)-[0-9a-f]{64}\.(?:json|sqlite)|track-identities\.tmp-\d+\.sqlite)(?:\.tmp-\d+)?(?:-journal|-wal|-shm)?\z/
            } readdir $dh;
            closedir $dh;
            for my $name (@names) {
                my $path = File::Spec->catfile($inventory, $name);
                die "Cannot remove job inventory artifact: $!" unless unlink $path;
            }
            unless (rmdir $inventory) {
                die "Cannot remove job inventory directory: $!" unless $! == ENOTEMPTY || $! == EEXIST;
            }
        }
    }
    for my $path ($self->{stdout}, $self->{stderr}) {
        unlink($path) or die "Cannot remove snapshot worker output: $!" if -e $path || -l $path;
    }
    unless (rmdir($self->{dir})) {
        die "Cannot remove snapshot worker directory: $!" unless $! == ENOTEMPTY || $! == EEXIST;
    }
    return 1;
}

1;
