use strict;
use warnings;
use utf8;
use FindBin;
use Test::More;

my $path = "$FindBin::Bin/../BetterCallBliss/strings.txt";
open my $file, '<:encoding(UTF-8)', $path or die "Cannot read $path: $!";
my $contents = do { local $/; <$file> };
for my $kind (qw(ONE MANY)) {
    my ($en, $de) = $contents =~ /^PLUGIN_BETTERCALLBLISS_GUIDANCE_SUMMARY_\Q$kind\E\n\tEN\t([^\n]+)\n\tDE\t([^\n]+)/m;
    ok(defined($en) && defined($de), "$kind summary has English and German translations");
    for my $entry ([EN => $en], [DE => $de]) {
        my ($language, $format) = @$entry;
        my $rendered = sprintf($format, 1, 35, 2, 3, 4, 5, 6, 7);
        my @numbers = $rendered =~ /\b(\d+)\b/g;
        is_deeply(\@numbers, [1, 35, 2, 3, 4, 5, 6, 7],
            "$language $kind summary keeps all guidance counts in order");
    }
}
done_testing;
