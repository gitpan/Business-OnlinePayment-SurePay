package Business::OnlinePayment::SurePay;

use 5.006;
use strict;
use Business::OnlinePayment;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
use warnings;

require Exporter;

our @ISA = qw(Exporter Business::OnlinePayment);

our @EXPORT_OK = qw();
our @EXPORT = qw();
our $VERSION = '0.01';

local($SIG{ALRM}) = sub {die timeout()." sec timeout"};

sub set_defaults {
  my $self = shift;

  $self->build_subs(qw/order_number gateway_type debug_level debug_file timeout/);
  $self->gateway_type('https');
  $self->server('xml.surepay.com');
  $self->port('443');
  $self->path('/');
  $self->debug_level('');
  $self->debug_file('');
  $self->timeout('120');
  
}

sub map_fields {
  my($self) = @_;
  my $i;
  my %content = $self->content();

  for($i=1;$i<4;$i++) {
    $content{"address$i"}='';
    if ((20*($i-1)) < length($content{'address'})) {
      $content{"address$i"} = substr($content{'address'}, 20*($i-1), 20);
    }
  }
  
  $content{'cvv2_status'}=$content{'cvv2'} ? '1':'9';
  
  # Checking test mode
  if($self->test_transaction()) {
    $self->server('xml.test.surepay.com');
  }
  else {
    $self->server('xml.surepay.com');
  }

  # stuff it back into %content
  $self->content(%content);
}

sub remap_fields {
    my($self,%map) = @_;

    my %content = $self->content();
    foreach(keys %map) {
        $content{$map{$_}} = $content{$_};
    }
    $self->content(%content);
}

sub get_fields {
    my($self,@fields) = @_;

    my %content = $self->content();
    my %new = ();
    foreach( grep defined $content{$_}, @fields) { $new{$_} = $content{$_}; }
    return %new;
}

sub submit {
  my($self) = @_;

  $self->map_fields();

  $self->remap_fields(
    first_name   => 'firstname',
    last_name    => 'lastname',
    cvv2_status  => 'cvv2status',
    card_number  => 'number',
    order_number => 'ordernumber',
    tax_amount   => 'taxamount',
    sku_number   => 'sku',
    tax_rate     => 'taxrate',
    amount       => 'unitprice',
    login        => 'merchant'
  );

  $self->required_fields(qw/first_name last_name address1 city state country zip 
                            card_number expiration order_number description quantity sku_number
			    tax_rate amount login password /);

  my $Request_Manager = RequestManager->new(
    'type' => $self->gateway_type(),
    'host' => $self->server(),
    'port' => $self->port(),
    'path' => $self->path(),
    'debuglevel' => $self->debug_level(),
    'debugfile' => $self->debug_file()
  );

  my $Request = Request->new($self->get_fields(qw/csp merchant password/));

  my $BillAddress = Address->new((type => 'billing'),
    $self->get_fields(qw/firstname lastname address1 address2
    address3 city state country zip phone eveningphone fax email/)
  );

  my $ShipAddress = Address->new((type => 'shipping'), 
    $self->get_fields(qw/firstname lastname address1 address2
    address3 city state country zip phone eveningphone fax email/)
  );

  my $Payment_Instrument = CreditCard->new((address => $BillAddress),
    $self->get_fields(qw/number expiration cvv2 cvv2status/)
  );

  my $Auth_Reference = Auth->new((address => $ShipAddress, payInstrument => $Payment_Instrument),
    $self->get_fields(qw/ecommerce eccommercecode ordernumber ponumber
    ipaddress verbalauthcode verbalauthdate shippingcost taxamount trackingnumbers recurring
    referringurl browsertype description/)
  );

  $Auth_Reference->addLineItem(LineItem->new(
    $self->get_fields(qw/sku description quantity taxrate unitprice /)
  ));

  $Request->addAuth($Auth_Reference);

  alarm $self->timeout();
  my $result = $Request_Manager->submit($Request);
  alarm 0;

  if ($result->getFailure eq 'true') {
    $self->is_success(0);
    $self->error_message($result->getFailureMsg);
  }
  else{
    $self->is_success(1);
    $self->authorization($result->getAuthCode);
  }
}

1;

package Address;

use strict;

our (%_Valid_Type,%_Valid_Field);
foreach (qw( billing shipping )) {
  $_Valid_Type{$_}++;
}

foreach (qw( firstname lastname address1 address2 address3 city state zip
  country phone eveningphone fax email type )) {
    $_Valid_Field{$_}++;
}

our %_Max_Length = (
  'firstname'     => 20,
  'lastname'     => 20,
  'address1'     => 20,
  'address2'     => 20,
  'address3'     => 20,
  'city'         => 20,
  'state'        =>  2,
  'zip'          =>  9,
  'country'      =>  2,
  'phone'        => 20,
  'eveningphone' => 20,
  'fax'          => 20,
  'email'        => 40,
);

sub new {
  my ($class,%fields) = @_;
  my $self = bless( {}, $class);
  my ($label,$value);
  while ( ($label,$value) = each %fields ) {
    $self->_Add_Field($label,$value);
  }
  return $self;
}

sub _Add_Field {
  my ($self,$label,$value) = @_;
  $value = Common->clean($value);
  $value =~ s/\D//g  if $label =~ /^(phone|eveningphone|fax|zip)$/;
  $value = uc $value if $label =~ /^(country|state)$/;
  return undef unless $value =~ /\S/;

  if ($label =~ /^type$/) {
    die "Invalid Address Type: ($value)" unless $_Valid_Type{$value};
  }

  $value = substr($value,0,$_Max_Length{$label}) if ($_Max_Length{$label}) && ($_Max_Length{$label} > 0);

  die "Invalid Address Field Name: ($label)" unless $_Valid_Field{$label};
  die "Invalid Email Address: ($value)"    if $label eq 'email'        && $value !~ /\w+\@\w+/;
  die "Invalid Phone Number: ($value)"     if $label eq 'phone'        && length($value) < 10;
  die "Invalid Phone Number: ($value)"     if $label eq 'eveningphone' && length($value) < 10;
  $self->{$label} = $value;
  return undef;
}

sub getType {
  my $self = shift; return $self->{'type'};
}

sub make_XML {
  my $self = shift;
  my $label;
  my $xml = qq(<pp.address );
  foreach $label ( keys %_Valid_Field ) {
    $xml .= qq($label="$self->{$label}" ) if defined $self->{$label};
  }
  $xml .= qq(/>);
  return $xml;
}

1;

package Auth;

use strict;

our %_Valid_Field_Name;
foreach (qw/ ecommerce ecommercecode ordernumber ponumber ipaddress verbalauthcode verbalauthdate
  shippingcost taxamount trackingnumbers recurring referringurl browsertype description /) { 
    $_Valid_Field_Name{$_}++;
}

our %_Max_Length = (
  'ordernumber'     => 10,
  'ponumber'        => 25,
  'ipaddress'       => 15,
  'verbalauthcode'  => 6,
  'verbalauthdate'  => 17,
  'trackingnumbers' => 100,
);

sub new {
  my ($class,%fields) = @_;
  my $self = bless( {}, $class);
  my ($label, $value);
  while ( ($label, $value) = each %fields ) { $self->_Add_Field($label, $value); }
  return $self;
}

sub _Add_Field {
  my ($self,$label,$value) = @_;
  my $backup;

  if ($label =~ /^address$/) {
    my $pref = ref $value;
    die "Invalid Address Reference: ($pref)" unless $pref eq 'Address';
    my $type = $value->getType;
    die "Invalid Address Type: ($type)" unless $type eq 'shipping';
    $self->{$label} = $value;
    return undef;
  }
  if ($label =~ /^payInstrument$/) {
    my $pref = ref $value;
    die "Invalid Payment Instrument: ($pref)" unless $pref eq 'CreditCard' || $pref eq 'TeleCheck';
    $self->{$label} = $value;
    return undef;
  }

  $value = Common->clean($value) if ($label =~ /^(ponumber|verbalauthcode|ipaddress|refurl|browser|verbalauthdate)$/);

  if ($label =~ /^ordernumber$/) {
    $backup = $value;
    die "Invalid order number: ($backup)" unless $value =~ /^\d+$/ && length($value) <= 10;
  }

  if ($label =~ /^verbalauthdate$/) {
    $backup = $value;
    die "Invalid Authorization Date: ($backup)" unless $value =~ /^\d+$/ && length($value) <= 17;
  }

  if ($label =~ /^(shippingcost|taxamount)$/) {
    $value=~ s/[^\d\.]//g;
    $value = sprintf("%.2f",$value);
  }
  
  $value = substr($value,0,$_Max_Length{$label}) if (($_Max_Length{$label}) && ($_Max_Length{$label} > 0));
  
  die "Invalid Auth Field Name ($label)" unless $_Valid_Field_Name{$label};
  return undef unless $value =~ /\S/;
  $self->{$label} = $value;
  return undef;
}

sub addLineItem {
  my ($self,$item) = @_;
  my $pref = ref $item;
  die "invalid line item reference ($pref)" unless $pref eq 'LineItem';
  push(@{$self->{'items'}},$item);
  return undef;
}

sub make_XML {
  my $self = shift;
  my $label;
  die "The ordernumber field is requered" unless $self->{'ordernumber'};
  die "No Line Items in Auth" unless scalar @{$self->{'items'}} > 0;

  $self->{'shippingcost'} = $self->{'shippingcost'}.'USD' if $self->{'shippingcost'};
  $self->{'taxamount'} = $self->{'taxamount'}.'USD' if $self->{'taxamount'};
  $self->{'ecommercecode'} = $self->{'ecommercecode'} ? $self->{'ecommercecode'} : '07';  
  my $xml = qq(<pp.auth );
  foreach $label ( keys %_Valid_Field_Name ) {
    next if $label =~ /^description$/;
    $xml .= qq($label="$self->{$label}" ) if defined $self->{$label};
  };
  $xml .= ">";
  $xml    .= $self->{'payInstrument'}->make_XML;
  $xml    .= $self->{'address'}->make_XML;
  foreach (@{$self->{'items'}}) { $xml .= $_->make_XML; }
  $xml    .= Text->new('description',$self->{'description'})->make_XML if $self->{'description'};
  $xml    .= qq(</pp.auth>);
  return $xml;
}

1;

package AuthResponse;

use strict;

sub new {
  my ($class,$xml)     = @_;
  $xml =~ s/[\n\cM]//g;
  die $xml unless ( $xml =~ m/<pp\.response>.*<\/pp\.response>/);
  my $self = bless ({}, $class);

  ($xml) = $xml =~ m/(<pp\.authresponse.*[<\/pp.authresponse>|\/>])/g;
  $xml =~ s/(authstatus="[^ ]+) /$1" /g;  
  $self->{'authcode'}      = $1 if $xml =~ /authcode="([^\"]*)"/;
  $self->{'authstatus'}    = $1 if $xml =~ /authstatus="([^\"]*)"/;
  $self->{'avs'}           = $1 if $xml =~ /avs="([^\"]*)"/;
  $self->{'cvv2result'}    = $1 if $xml =~ /cvv2result="([^\"]*)"/;
  $self->{'csp'}           = $1 if $xml =~ /csp="([^\"]*)"/;
  $self->{'merchant'}      = $1 if $xml =~ /merchant="([^\"]*)"/;
  $self->{'failure'}       = $1 if $xml =~ /failure="([^\"]*)"/;
  $self->{'ordernumber'}   = $1 if $xml =~ /ordernumber="([^\"]*)"/;
  $self->{'transactionid'} = $1 if $xml =~ /transactionid="([^\"]*)"/;
  $self->{'message'}       = $1 if  $xml =~ />([^<]*)</;
  $self->{'failure'} = 'false'
    unless (defined $self->{'failure'}) && ($self->{'failure'} =~ /^true$/);

  return $self;
}

sub getAuthCode      { my $self = shift; return $self->{'authcode'}; }
sub getAuthStatus    { my $self = shift; return $self->{'authstatus'}; }
sub getAVS           { my $self = shift; return $self->{'avs'}; }
sub getcvv2result    { my $self = shift; return $self->{'cvv2result'}; }
sub getCSP           { my $self = shift; return $self->{'csp'}; }
sub getMerchant      { my $self = shift; return $self->{'merchant'}; }
sub getFailure       { my $self = shift; return $self->{'failure'}; }
sub getOrderNumber   { my $self = shift; return $self->{'ordernumber'}; }
sub getTransactionID { my $self = shift; return $self->{'transactionid'}; }
sub getFailureMsg    { my $self = shift; return $self->{'message'}; }

1;

package CreditCard;

use strict;

our %_Valid_Field_Name;
foreach (qw/ number expiration cvv2 cvv2status address /) { $_Valid_Field_Name{$_}++; }

our %_Max_Length = (
  'cardnumber'   => 19,
  'expiration'   => 5,
  'cvv2'         => 4,
  'cvv2status'   => 1,
);

sub new {
  my ($class,%fields) = @_;
  my $self = bless( {}, $class);
  my ($l,$v);
  while ( ($l,$v) = each %fields ) { $self->addField($l,$v); }
  return $self;
}

sub addField {
  my ($self,$label,$value) = @_;
  my $backup;

  if ($label =~ /^address$/) {
    my $pref = ref $value;
    die "Invalid Address Reference ($pref)" unless $pref eq 'Address';
    my $type = $value->getType;
    die "Invalid Address Type ($type)" unless $type eq 'billing';
    $self->{$label} = $value;
    return undef;
  }

  $value = Common->clean($value);

  if ($label =~ /^number$/) {
    $backup=$value;
    $value = $self->_CreditCardNumberCheck($value);
    die "Invalid Credit Ccard Number: $backup\n" unless $value;
  }

  if ($label =~ /^expiration$/) {
    $backup=$value;
    my ($month,$year) = $value =~ m#^(\d\d)/(\d\d)$#;
    die "Invalid Credit Card Expiration: $backup\n" unless $month =~ /\d\d/ && $year =~ /\d\d/; 
    $value = "$month/$year";
  }

  $value = substr($value,0,$_Max_Length{$label}) if (($_Max_Length{$label}) && ($_Max_Length{$label} > 0));
  
  die "Invalid Credit Card Field Name ($label)" unless $_Valid_Field_Name{$label};
  return undef unless $value =~ /\S/;
  $self->{$label} = $value;
  return undef;
}

sub make_XML {
  my $self = shift;
  my $label;
  my $xml = qq(<pp.creditcard );
  foreach $label ( keys %_Valid_Field_Name ) {
    next if $label =~ /^address$/;
    $xml .= qq($label="$self->{$label}" ) if defined $self->{$label};
  };
  $xml .= ">";
  $xml .= $self->{'address'}->make_XML;
  $xml .= qq(</pp.creditcard>);
  return $xml;
}

sub _CreditCardNumberCheck {
    my ($self,$cardNumber) = @_;
    my ($i, $sum, $weight);
    return undef if ($cardNumber =~ /^\s*$/);  # invalid if empty
    $cardNumber =~ s/\D//g;
    for ($i = 0; $i < length($cardNumber) - 1; $i++) {
	$weight = substr($cardNumber, -1 * ($i + 2), 1) * (2 - ($i % 2));
	$sum += (($weight < 10) ? $weight : ($weight - 9));
    }
    return $cardNumber if substr($cardNumber, -1) == (10 - $sum % 10) % 10;
    return undef;
}

1;

package LineItem;

use strict;

our %_Valid_Field_Name;
foreach (qw/ description quantity sku taxrate unitprice /) { 
  $_Valid_Field_Name{$_}++;
}

our %_Max_Length = (
  'description'     => 200,
);

sub new {
  my ($class,%fields) = @_;
  my $self = bless( {}, $class);
  my ($label, $value);
  while ( ($label, $value) = each %fields ) { $self->_Add_Field($label, $value); }
  return $self;
}

sub _Add_Field {
  my ($self,$label,$value) = @_;
  my $backup;

  $value = Common->clean($value) if ($label =~ /^(sku|description)$/);

  if ($label =~ /^quantity$/) {
    $value =~ s/\D//g;
    $value ||= 0;
  }
  if ($label =~ /^taxrate$/) {
    $value =~ s/[^\d\.]//g;
    $value ||= 0;
  }
  if ($label =~ /^unitprice$/) {
    $value =~ s/[^\d\.\-]//g;
    $value = sprintf("%.2f",$value);
  }

  $value = substr($value,0,$_Max_Length{$label}) if (($_Max_Length{$label}) && ($_Max_Length{$label} > 0));
  
  die "Invalid Line Item Field Name ($label)" unless $_Valid_Field_Name{$label};
  return undef unless $value =~ /\S/;
  $self->{$label} = $value;
  return undef;
}

sub make_XML {
  my $self = shift;
  my $label;
  $self->{'unitprice'} = $self->{'unitprice'}.'USD' if ($self->{'unitprice'});
  my $xml = qq(<pp.lineitem );
  foreach $label ( keys %_Valid_Field_Name ) {
    $xml .= qq($label="$self->{$label}" ) if defined $self->{$label};
  };
  $xml .= qq(></pp.lineitem>);
  return $xml;
}

1;

package Common;

use strict;
use Net::SSLeay;

sub doctype {
  my $self = shift;
  return qq(<!DOCTYPE pp.request PUBLIC "-//IMALL//DTD PUREPAYMENTS 1.0//EN" "http://www.purepayments.com/dtd/purepayments.dtd">);
}

sub clean {
  my ($self,$value) = @_;
  $value =~ s/[^\w !\@#\$\%^&\*\)\)\[\]{}_\-\+=|\\~`:;"'<>,\.\?\/]//g;
  $value =~ s/&/&amp;/g;
  $value =~ s/</&lt;/g;
  $value =~ s/>/&gt;/g;
  $value =~ s/\"/&quot;/g;
  $value =~ s/\n+/\n/g;
  return $value;
}

sub https_post {
  my ($self,$host,$port,$path,$slowly,$type,$request) = @_;
  my ($form,$page);
  $Net::SSLeay::slowly = $slowly if $slowly > 0;
  $request =~ s/([^a-zA-Z0-9_.-])/uc sprintf("%%%02x",ord($1))/eg;
  $request =~ s/ /+/g;
  $form = "$type=$request";
  eval 
  {
    ($page) = Net::SSLeay::post_https($host,$port,$path,'',$form);
  };
  $@ =~ s/ at .*//;
  return $page? ('',$page) : ($@ || 'null response');
}

1;

package Request;

use strict;

our %_Valid_Field_Name;
foreach (qw/ csp merchant password /) { 
    $_Valid_Field_Name{$_}++;
}

sub new {
  my ($class,%fields) = @_;
  my $self = bless( {}, $class);
  my ($label, $value);
  while ( ($label, $value) = each %fields ) { $self->_Add_Field($label, $value); }
  return $self;
}

sub _Add_Field {
  my ($self,$label,$value) = @_;

  $value = Common->clean($value) if ($label =~ /^(merchant|password|csp)$/);

  die "Invalid Auth Field Name ($label)" unless $_Valid_Field_Name{$label};
  return undef unless $value =~ /\S/;
  $self->{$label} = $value;
  return undef;
}

sub addAuth {
  my ($self,$obj) = @_;
  my $pref = ref $obj;
  die "Invalid Auth Reference: ($pref)" unless $pref eq 'Auth';
  $self->{'auths'} = [] unless $self->{'auths'};
  push(@{$self->{'auths'}},$obj);
  return undef;
}

sub make_XML {
  my $self = shift;
  die "No Auth Field In Request" unless ((scalar @{$self->{'auths'}}) > 0);
  my $label;
  my $xml = qq(<pp.request );
  foreach $label ( keys %_Valid_Field_Name ) {
    $xml .= qq($label="$self->{$label}" ) if defined $self->{$label};
  };
  $xml .= qq(>);
  foreach (@{$self->{'auths'}}){ $xml .= $_->make_XML; }
  $xml .= qq(</pp.request>);
  return $xml;
}

1;

package RequestManager;

use strict;

sub new {
  my ($class, %param) = @_;
    die "Host must be defined" unless $param{'host'};
    die "Port must be defined" unless $param{'port'};
    die "Path must be defined" unless $param{'path'};
    $param{'host'} =~ s/^https:\/\///;
  $param{'debuglevel'} ||= 0;
  return bless (\%param, $class);
}

sub submit {
  my ($self,$req) = @_;
  my ($res);
  local (*DBG);
  die "Unrecognized Request Object Reference" unless (ref $req eq 'Request');
  my $smsg = $req->make_XML;
  my $debugfile = $self->{'debugfile'};
  if ($self->{'debuglevel'} > 0) {
    if ($debugfile) {
      open (DBG,">>$debugfile");
      print DBG "smsg: $smsg\n";
      close DBG;
    }
    else {
      print "smsg: $smsg\n";
    }
  }
  my $slowly = 0;
  my $label  = 'xml';
  my ($msg,$output) = Common->https_post(
    $self->{'host'},
    $self->{'port'},
    $self->{'path'},
    $slowly,
    $label,
    $smsg
  );
  if ($msg) {
    die "https error: $msg";
  }
  if ($self->{'debuglevel'} > 0) {
    if ($debugfile) {
      open (DBG,">>$debugfile");
      print DBG "rmsg: $output\n";
      close DBG;
    }
    else {
      print "rmsg: $output\n";
    }
  }
  die "No Response From SurePay Gateway" unless $output;
  return AuthResponse->new($output);
}

1;

package Text;

use strict;

sub new
{
  my ($class,$type,$text) = @_;
  die "Invalid Auth Text Type ($type)" unless $type =~ /^description$/;
  return bless { 'type' => $type, 'text' => $text }, $class;
}

sub make_XML {
  my $self = shift;
  my $type = $self->{'type'};
  my $text = $self->{'text'};
  $text =~ s/[^\w !\@#\$\%^&\*\)\)\[\]{}_\-\+=|\\~`:;"'<>,\.\?\/\n\t]//g;
  $text =~ s/\n+$/\n/;
  $text =~ s/]]>//g;
  $text =~ s/&quot;/\"/g;
  $text =~ s/&amp;/&/g;
  $text = qq(<![CDATA[$text]]>);
  return qq(<pp.ordertext type="$type">$text</pp.ordertext>);
}

1;

__END__

=head1 NAME

Business::OnlinePayment::SurePay - SurePay backend for Business::OnlinePayment

=head1 SYNOPSIS

  use Business::OnlinePayment::SurePay;
  
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
    login          => 'Your merchant login',
    password       => 'Your merchant password'
  );
  $tx->submit();

  if($tx->is_success()) {
      print "Card processed successfully: ".$tx->authorization."\n";
  } else {
      print "Card was rejected: ".$tx->error_message."\n";
  }

=head1 SUPPORTED CREDIT CARDS TYPES

=head2 Visa, MasterCard, American Express, JCB, Discover, and Diners Club

=head1 DESCRIPTION

The following content is required for successeful transaction:
    first_name - The first name of card holder.
    last_name - The last name of card holder.
    address - The street address.
    city - The city of address.
    state - The state of address.
    country - The country of address.
    zip - The zip/postal code of address.
    card_number - The credit card number.
    expiration - The required credit card expiration date. This is a slash with one or two digits on either side.
    order_number - The order number of the authorization request.
    description - The description of the item of the order.
    quantity - The quantity of the item of the order.
    sku_number - The SKU of the item.
    tax_rate - The tax rate of the item.
    amount - The cost of this item. This attribute must be a minus character,for discounts, followed by a string of digits. 
    login - The required ID of the merchant whose request is being submitted.
    password - The required password to access the merchant account.

The following optional content is posible also:
    csp - The name for the commerce service provider through which the merchant's request is being submitted.
    phone - The primary/daytime phone number.
    eveningphone - The evening phone number.
    fax - The fax number. 
    email - The email address. 
    cvv2 - The 3- or 4-digit CVV2 code found on the signature line on the back of the credit card following the account number.
    cvv2status - An optional code indicating whether the CVV2 code isn`t being used, is illegible, or isn`t present on the card.
    ecommerce - The value true or false specifies that the transaction was initiated over the Internet.
    eccommercecode - The code that identifies what level of encryption was used when processing the transaction.
    ponumber - The purchase order number of the authorization request.
    ipaddress - The Internet IP address of the customer being authorized.
    verbalauthcode - The manual authorization code.
    verbalauthdate - The date and time of verbal authorization.
    shippingcost - The shipping costs for the order. 
    taxamount - The tax amount for the order. 
    trackingnumbers - The list of identifiers used to track this order.
    recurring - The value "true" or "false", depending upon whether this payment is recurring, which may affect customer credibility.
    referringurl - The data identifying the URL of the site from which the customer was referred to the merchant's web site.
    browsertype - The data identifying the browser used by the customer when placing the order on the merchant's web site.

For detailed information see L<Business::OnlinePayment>.

=head1 COMPATIBILITY

This module implements Normal Authorization mathod only and compatible
with Software Developer Kit verion 1.4.
See http://www.surepay.com/downloads/SdkIntegrationGuide.pdf for details.

=head1 AUTHOR

Alexey Khobov, E<lt>AKHOBOV@cpan.orgE<gt>

=head1 SEE ALSO

L<perl>. L<Business::OnlinePayment>.

=cut
