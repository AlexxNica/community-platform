use strict;
use warnings;

BEGIN {
    $ENV{DDGC_DB_DSN} = 'dbi:SQLite:dbname=ddgc_test.db';
    $ENV{DDGC_MAIL_TEST} = 1;
    $ENV{DDGC_BASIC_AUTH_USER} = 'mailuser';
    $ENV{DDGC_BASIC_AUTH_PASS} = 'cE8cgcEoyscVr7YnwHrfjxa1RRyLVHMns';
}


use Plack::Test;
use Plack::Builder;
use HTTP::Request::Common;
use Test::More;
use Test::MockTime qw/:all/;
use t::lib::DDGC::TestUtils;
use DDGC::Web::App::Subscriber;
use DDGC::Base::Web::Light;
use DDGC::Util::Script::SubscriberMailer;
use URI;
use MIME::Base64 'encode_base64url';

t::lib::DDGC::TestUtils::deploy( { drop => 1 }, schema );
my $m = DDGC::Util::Script::SubscriberMailer->new;

my $app = builder {
    mount '/s' => DDGC::Web::App::Subscriber->to_app;
};

test_psgi $app => sub {
    my ( $cb ) = @_;

    set_absolute_time('2016-10-18T12:00:00Z');

    for my $email (qw/
        test1@duckduckgo.com
        test2@duckduckgo.com
        test3@duckduckgo.com
        test4@duckduckgo.com
        test5@duckduckgo.com
        test6duckduckgo.com
        lateverify@duckduckgo.com
        notanemailaddress
    / ) {
        ok( $cb->(
            POST '/s/a',
            [ email => $email, campaign => 'a', flow => 'flow1' ]
        ), "Adding subscriber : $email" );
    }

    my $invalid = rset('Subscriber')->find( {
        email_address => 'notanemailaddress',
        campaign => 'a'
    } );
    is( $invalid, undef, 'Invalid address not inserted via POST' );

    my $transport = DDGC::Util::Script::SubscriberMailer->new->verify;
    is( $transport->delivery_count, 6, 'Correct number of verification emails sent' );

    $transport = DDGC::Util::Script::SubscriberMailer->new->verify;
    is( $transport->delivery_count, 0, 'No verification emails re-sent' );

    my $unsubscribe = sub {
        my ( $email ) = @_;
        my $subscriber = rset('Subscriber')->find( {
            email_address => $email,
            campaign => 'a',
        } );
        my $url = URI->new( $subscriber->unsubscribe_url );
        ok(
            $cb->( GET $url->path ),
            "Verifying " . $subscriber->email_address
        );
    };

    my $verify = sub {
        my ( $email ) = @_;
        my $subscriber = rset('Subscriber')->find( {
            email_address => $email,
            campaign => 'a',
        } );
        my $url = URI->new( $subscriber->verify_url );
        ok(
            $cb->( GET $url->path ),
            "Verifying " . $subscriber->email_address
        );
    };

    set_absolute_time('2016-10-20T12:00:00Z');
    $transport = DDGC::Util::Script::SubscriberMailer->new->execute;
    is( $transport->delivery_count, 6, '6 received emails' );

    $transport = DDGC::Util::Script::SubscriberMailer->new->execute;
    is( $transport->delivery_count, 0, 'Emails not re-sent' );

    set_absolute_time('2016-10-21T12:00:00Z');
    $transport = DDGC::Util::Script::SubscriberMailer->new->execute;
    is( $transport->delivery_count, 0, '0 received emails - non scheduled' );

    $unsubscribe->('test2@duckduckgo.com');

    set_absolute_time('2016-10-22T12:00:00Z');
    $transport = DDGC::Util::Script::SubscriberMailer->new->execute;
    is( $transport->delivery_count, 5, '5 received emails - one unsubscribed' );

    $transport = DDGC::Util::Script::SubscriberMailer->new->execute;
    is( $transport->delivery_count, 0, 'Emails not re-sent' );
};

test_psgi $app => sub {
    my ( $cb ) = @_;

    my $creds = encode_base64url("$ENV{DDGC_BASIC_AUTH_USER}:$ENV{DDGC_BASIC_AUTH_PASS}");
    my $badcreds = encode_base64url('baduser:baspassword');

    is( $cb->( GET '/s/testrun/a' )->code, 401,
        'Cannot get testrun form without credentials' );
    is( $cb->( GET '/s/testrun/a', Authorization => "Basic $badcreds" )->code, 401,
        'Cannot get testrun form with incorrect credentials' );
    is( $cb->( GET '/s/testrun/a', Authorization => "Basic $creds" )->code, 200,
        'Can get testrun form with correct credentials' );

    is( $cb->( POST '/s/testrun/a' )->code, 401,
        'Cannot POST to testrun without credentials' );
    is( $cb->( POST '/s/testrun/a', Authorization => "Basic $badcreds" )->code, 401,
        'Cannot POST to testrun with incorrect credentials' );

    my $req = POST '/s/testrun/a';
    $req->authorization_basic( $ENV{DDGC_BASIC_AUTH_USER}, $ENV{DDGC_BASIC_AUTH_PASS} );
    $req->content('email=emailaddress%40duckduckgo.com');
    is( $cb->( $req )->content, 'OK', 'testrun accepts a DDG address' );

};

done_testing;

