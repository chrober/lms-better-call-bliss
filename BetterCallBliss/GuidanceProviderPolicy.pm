package Plugins::BetterCallBliss::GuidanceProviderPolicy;

use strict;
use warnings;
use Plugins::BlissGuidance::Policy ();

# Keep the existing Better Call Bliss entry points while using the shared
# provider-neutral resolver and validation rules as the single authority.
sub resolve { return Plugins::BlissGuidance::Policy::resolve(@_); }
sub host_state { return Plugins::BlissGuidance::Policy::host_state(@_); }
sub replace_host_state { return Plugins::BlissGuidance::Policy::replace_host_state(@_); }
sub _validate_value { return Plugins::BlissGuidance::Policy::_validate_value(@_); }

1;
