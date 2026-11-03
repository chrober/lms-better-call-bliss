use strict;
use warnings;
use Test::More;
my $available = system('node', '--version') == 0;
plan skip_all => 'Node.js is required for pagination behavior tests' unless $available;
plan tests => 1;
is(system('node', 'tests/recent_pagination.js'), 0, 'recent preview pagination preserves navigation across updates');
