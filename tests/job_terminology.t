use strict;
use warnings;
use Test::More;
plan skip_all => 'Node.js is required for terminology checks' unless system('node', '--version') == 0;
plan tests => 1;
is(system('node', 'tests/job_terminology.js'), 0, 'job terminology is consistent in English and German');
