use strict;
use warnings;
use Test::More;

my $available = system('node', '--version') == 0;
plan skip_all => 'Node.js is required for the browser recovery behavior test' unless $available;
plan tests => 1;
is(system('node', 'tests/preview_start_recovery.js'), 0, 'preview startup recovery handles uncertain network failures');
