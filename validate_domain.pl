#!/usr/bin/perl
use strict;
use warnings;
use WWW::Curl::Easy;
use XML::Simple;
use Net::OpenSSH;
use Data::Dumper;

my $xml = XMLin('config.xml');

if ( @ARGV != 1 ) {
	print "Usage: $0 <fqdn>\n";
	exit 1;
}

our ( $domain, $validatepath, $validatehost );

## Find the host to validate....
foreach my $node ( keys $xml->{domains}{domain} ) {
	if ( $node eq $ARGV[0] ) {
		$domain = $node;
		$validatehost = $xml->{domains}{domain}{$node}{validatehost};
		$validatepath = $xml->{domains}{domain}{$node}{validatepath};
		last;
	}
}

if ( !$domain ) {
	print "No domain match found. Add to config.xml\n";
	exit 1;
}

my $json = 'RequestData={
	"tokenID": "' . $xml->{config}->{Token} . '",
	"actionType": "ApplyWebControl",
	"hostname": "' . $domain . '"
}';

print "Getting validation string...\n";
my $body = "";
my $headers = "";
my $curl = WWW::Curl::Easy->new;
#$curl->setopt(CURLOPT_VERBOSE, 1);
$curl->setopt(CURLOPT_SSLCERT, "./" . $xml->{config}->{SSLCert});
$curl->setopt(CURLOPT_SSLKEY, "./" . $xml->{config}->{SSLKey});
$curl->setopt(CURLOPT_URL, $xml->{config}->{URI});
$curl->setopt(CURLOPT_POST, 1);
$curl->setopt(CURLOPT_POSTFIELDS, $json);
$curl->setopt(CURLOPT_WRITEHEADER, \$headers );
$curl->setopt(CURLOPT_FILE, \$body);
$curl->perform();

$body =~ /"errorCode": (.+),/;
my $errorcode = $1;
if ( $errorcode != 0 ) {
	$body =~ /"shortMsg": "(.+)"/;
	print "Received Error Code: $errorcode - $1\n\n";
	exit 1;
}

$body =~ /"data": "(.+)"/;
my $data = $1;

print "Data: $data\n";

## Create the validation file on the server.
print "Sending validation string to server: $validatehost...\n";
my $ssh = Net::OpenSSH->new($validatehost) or die "ERROR: Unable to connect " . $!;
$ssh->system("echo \"$data\" > $validatepath$domain.html");

print "Validating with StartSSL...\n";
$body = "";
$headers = "";
$json = 'RequestData={
	"tokenID": "' . $xml->{config}->{Token} . '",
        "actionType" : "WebControlValidation",
	"hostname": "' . $domain . '"
}';

$curl->setopt(CURLOPT_POSTFIELDS, $json);
$curl->perform();

print "Status:\n$body\n";

$ssh->system("echo > $validatepath$domain.html");
