use strict;
use warnings;
use Test::More;
use FindBin;

eval { require Template::Parser; 1 }
    or plan skip_all => 'Template Toolkit is required to validate the Extras template';
plan tests => 1;
my $path = "$FindBin::Bin/../BetterCallBliss/HTML/EN/plugins/BetterCallBliss/index.html";
open my $file, '<:raw', $path or die "Cannot read $path: $!";
my $source = do { local $/; <$file> };
my $parser = Template::Parser->new;
my $parsed = $parser->parse($source);
ok($parsed, 'Extras template parses with Template Toolkit') or diag($parser->error);
