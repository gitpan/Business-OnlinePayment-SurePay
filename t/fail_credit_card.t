BEGIN { $| = 1; print "1..1\n"; }

#testing/testing is valid and seems to work...
#print "ok 1 # Skipped: need a valid Authorize.Net login/password to test\n"; exit;

use Business::OnlinePayment;

my $tx = new Business::OnlinePayment("SurePay");
$tx->content(
    first_name     => 'Jason',
    last_name      => 'Kohles',
    address        => '123 Anystreet',
    city           => 'Anywhere',
    state          => 'UT',
    country        => 'USA',
    zip            => '99999',
    card_number    => '4111111111111111',
    expiration     => '12/00',
    order_number   => '100100',
    description    => 'test',
    quantity       => '1',
    sku_number     => '12345',
    tax_rate       => '0',
    amount         => '50.00',
    login          => '1001',
    password       => 'password'
);

$tx->test_transaction(1); # test, dont really charge
$tx->submit();

if($tx->is_success()) {
    print "not ok 1\n";
} else {
    print "ok 1\n";
}
