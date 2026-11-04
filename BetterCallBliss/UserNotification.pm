package Plugins::BetterCallBliss::UserNotification;

use strict;
use warnings;
use Slim::Control::Request;
use Slim::Utils::Timers;
use Time::HiRes qw(time);

use constant ROUTE_FAILURE_TIMEOUT_SECONDS => 15;

sub scan_blocked {
    my ($player_id, $message) = @_;
    # Show the error after Material's immediate context-menu notification.
    Slim::Utils::Timers::setTimer(undef, time() + 0.5, sub {
        Slim::Control::Request::notifyFromArray(undef, [
            'material-skin', 'notification', 'error', $message,
            undef, $player_id, ROUTE_FAILURE_TIMEOUT_SECONDS,
        ]);
    });
}

sub route_failure {
    my ($job, $message) = @_;
    return 0 unless ref($job) eq 'HASH'
        && $job->{quick_route} && $job->{auto_apply};
    return 0 if $job->{route_failure_notified};
    $job->{route_failure_notified} = 1;

    $message ||= 'Unknown route failure';
    $message =~ s/\s+at\s+\S+\s+line\s+\d+\.?\s*$//;
    $message =~ s/\s+/ /g;
    $message =~ s/^\s+|\s+$//g;
    $message = substr($message, 0, 400);
    my $player_id = $job->{route_player_id} || '';

    Slim::Control::Request::notifyFromArray(
        undef,
        [
            'material-skin', 'notification', 'error',
            'Bliss me there failed: ' . $message,
            undef, $player_id, ROUTE_FAILURE_TIMEOUT_SECONDS,
        ],
    );
    return 1;
}

1;
