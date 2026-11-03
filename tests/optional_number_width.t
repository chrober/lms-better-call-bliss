use strict;
use warnings;
use Test::More;
plan skip_all => 'Node.js is required for optional number width tests'
    unless system('node', '--version') == 0;
plan tests => 1;
is(system('node', 'tests/optional_number_width.js'), 0, 'optional number fields adapt to localized placeholders');
