use strict;
use warnings;
use Test::More;
my $available = system('node', '--version') == 0;
plan skip_all => 'Node.js is required for Extras localization tests' unless $available;
plan tests => 1;
is(system('node', 'tests/extras_i18n.js'), 0, 'dynamic Extras descriptions follow the selected language');
