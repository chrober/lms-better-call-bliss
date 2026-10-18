use strict;
use warnings;
use FindBin;
use Test::More;
use lib "$FindBin::Bin/..";

BEGIN {
    package Slim::Control::Request;
    our @notifications;
    sub notifyFromArray { push @notifications, $_[1] }
    $INC{'Slim/Control/Request.pm'} = __FILE__;
}

require "$FindBin::Bin/../BetterCallBliss/UserNotification.pm";

my $quick_route = {
    quick_route => 1,
    auto_apply => 1,
    route_player_id => 'aa:bb:cc:dd:ee:ff',
};

ok(
    Plugins::BetterCallBliss::UserNotification::route_failure(
        $quick_route,
        "no valid route was found\n",
    ),
    'an automatic Bliss me there failure emits a notification',
);
is_deeply(
    $Slim::Control::Request::notifications[-1],
    [
        'material-skin', 'notification', 'error',
        'Bliss me there failed: no valid route was found',
        undef, 'aa:bb:cc:dd:ee:ff', 15,
    ],
    'the error snackbar is targeted to the route player and remains visible',
);

my $count = scalar @Slim::Control::Request::notifications;
ok(
    !Plugins::BetterCallBliss::UserNotification::route_failure(
        {quick_route => 0, auto_apply => 0},
        'ordinary preview failed',
    ),
    'an Extras preview does not emit a route snackbar',
);
is(scalar @Slim::Control::Request::notifications, $count,
    'ordinary preview failure did not publish a notification');

ok(
    !Plugins::BetterCallBliss::UserNotification::route_failure(
        $quick_route,
        'another failure',
    ),
    'the same quick route failure is notified only once',
);
is(scalar @Slim::Control::Request::notifications, $count,
    'duplicate terminal handling did not publish twice');

done_testing();
