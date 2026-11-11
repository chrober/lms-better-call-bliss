use strict;
use warnings;
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

my $root = tempdir(CLEANUP => 1);
my $plugin = File::Spec->catdir($root, 'Plugins', 'BetterCallBliss');
my $guidance = File::Spec->catdir($plugin, 'Plugins', 'BlissGuidance');
make_path($guidance);
copy("$FindBin::Bin/../BetterCallBliss/GuidanceProviderPolicy.pm", $plugin) or die $!;
copy("$FindBin::Bin/../BetterCallBliss/Plugins/BlissGuidance/Policy.pm", $guidance) or die $!;
local $ENV{PERL5LIB} = '';
my $result = system($^X, "-I$root", '-MPlugins::BetterCallBliss::GuidanceProviderPolicy', '-e', 'exit 0');
is($result, 0, 'policy wrapper loads its bundled shared module from the installed plugin layout');
done_testing();
