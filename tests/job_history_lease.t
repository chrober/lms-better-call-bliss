use strict;
use warnings;
use FindBin;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use Fcntl qw(:flock);
use Test::More;

plan skip_all => 'process lock inheritance is tested on Unix' if $^O eq 'MSWin32';
require "$FindBin::Bin/../BetterCallBliss/JobHistory.pm";
my $root = tempdir(CLEANUP => 1);
my $id = 'preview-1000-lease';
make_path("$root/$id");
my $history = Plugins::BetterCallBliss::JobHistory->new($root);
ok(!$history->result_in_use($id), 'a missing optimizer result has no running writer');
open my $result, '>', "$root/$id/result.json" or die $!;
flock($result, LOCK_EX | LOCK_NB) or die $!;
pipe(my $read, my $write) or die $!;
my $pid = fork();
die $! unless defined $pid;
if (!$pid) {
    close $write;
    open STDIN, '<&', $read or die $!;
    open STDOUT, '>&', $result or die $!;
    exec $^X, '-e', 'scalar <STDIN>;';
    die "exec failed: $!";
}
close $read;
close $result;
select undef, undef, undef, 0.2;
ok($history->result_in_use($id), 'a child inheriting the result lock protects its job');
print {$write} "done\n";
close $write;
waitpid($pid, 0);
ok(!$history->result_in_use($id), 'result is available for cleanup after the child exits');
done_testing();
