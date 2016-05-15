#!/usr/bin/perl
use strict;
use warnings;
use WWW::Curl::Easy;
use XML::Simple;
use POSIX 'strftime';
use URI::Escape;
use MIME::Base64;

if ( @ARGV != 1 ) {
	print "Usage: $0 <fqdn>\n";
	exit 1;
}

my $hostname = $ARGV[0];
my $xml = XMLin('config.xml');

if ( !-d "certificates" ) {
	mkdir "certificates";
}

## Generate the CSR...
my $date = strftime '%Y-%m-%d', localtime;

## Check if CSR already exists.
if ( -f "certificates/$hostname.csr" ) {
	## Prompt to use existing CSR if it exists. Some hardware devices generate their own CSRs.
	print "A CSR for $hostname already exists in ./certificates/.\n\nDo you want to use this CSR? (Y/N): ";
	chomp(my $answer = <STDIN>);
	if ( lc($answer) eq "n" ) {
		## Remove the old CSR so we create a new one in the next step.
		unlink "certificates/$hostname.csr";
	}
}

if ( !-f "certificates/$hostname.csr" ) {
	`openssl req -new -newkey rsa:4096 -sha512 -nodes -out certificates/$hostname.csr -keyout certificates/$hostname.key -subj "/CN=$hostname"`;
}

open my $csr_file, "<", "certificates/$hostname.csr";
my $csr = do { local $/; <$csr_file>; };
chomp($csr);
close $csr_file;

my $json = 'RequestData={
	"tokenID": "' . $xml->{config}->{Token} . '",
	"actionType": "ApplyCertificate",
	"certType": "DVSSL",
	"domains": "' . $hostname . '",
	"CSR": "'. uri_escape($csr) . '"
}';

print "Submitting CSR...\n";
my $body = "";
my $headers = "";
my @bad_headers = ('Expect:');
my $curl = WWW::Curl::Easy->new;
if ( $xml->{config}->{Verbose} ) {
        $curl->setopt(CURLOPT_VERBOSE, 1);
}
$curl->setopt(CURLOPT_SSLCERT, "./" . $xml->{config}->{SSLCert});
$curl->setopt(CURLOPT_SSLKEY, "./" . $xml->{config}->{SSLKey});
$curl->setopt(CURLOPT_URL, $xml->{config}->{URI});
$curl->setopt(CURLOPT_POST, 1);
$curl->setopt(CURLOPT_POSTFIELDS, $json);
$curl->setopt(CURLOPT_WRITEHEADER, \$headers );
$curl->setopt(CURLOPT_FILE, \$body);
$curl->setopt(CURLOPT_HTTPHEADER, \@bad_headers );
$curl->perform();

$body =~ /"errorCode": (.+),/;
my $errorcode = $1;
if ( $errorcode != 0 ) {
	$body =~ /"shortMsg": "(.+)"/;
	print "Received Error Code: $errorcode - $1\n\n";
	exit 1;
}

$body =~ /"orderStatus": (.+),/;
my $orderStatus = $1;

$body =~ /"orderID": "(.+)",/;
my $orderID = $1;

$body =~ /"orderNo": "(.+)",/;
my $orderNo = $1;

open my $LOG, ">>", "certificates/$hostname.log" or die "Unable to open log file: $!\n";
print $LOG <<EOF;
====== StartSSL Certificate Log ======
Date:			$date
Order ID:		$orderID
Order Number:		$orderNo
Order Status:		$orderStatus
Obtained from:		$xml->{config}->{URI}
EOF

print "\nSaved order details to: certificates/$hostname.log\n\n";

if ( $orderStatus eq "3" ) {
	print "Order Status:			Rejected.\n";
}
elsif ( $orderStatus eq "1" ) {
	print "Order Status:			Pending. Retrieve certificate later...\n";
}
elsif ( $orderStatus eq "2" ) {
	print "Order Status:			Issued.\n\n";
	if ( $body =~ /"certificateFieldMD5": "(.+)",/ ) {
		print $LOG "Certificate MD5:	$1\n";
	}
	if ( $body =~ /"intermediateCertificateFieldMD5": "(.+)"/ ) {
		print $LOG "Intermediate MD5:	$1\n";
	}

	## Print the certificate to file.
	$body =~ /"certificate": "(.+)",/;
	my $certificate = $1;
	$body =~ /"intermediateCertificate": "(.+)",/;
	my $intermediatecertificate = $1;

	open my $CERT, ">", "certificates/$hostname.crt" or die "Unable to write certificate: $!\n";
	print $CERT decode_base64($certificate);
	close $CERT;

	## Print the intermediate to file,
	open $CERT, ">", "certificates/$hostname-intermediate.crt" or die "Unable to write certificate: $!\n";
	print $CERT decode_base64($intermediatecertificate);
	close $CERT;

	## Write out the combined PEM.
	open $CERT, ">", "certificates/$hostname.pem" or die "Unable to write certificate: $!\n";
	print $CERT decode_base64($certificate);
	print $CERT decode_base64($intermediatecertificate);
	close $CERT;
	
	print "Wrote Certificate to:		certificates/$hostname.crt\n";
	print "Wrote Intermediate Cert to:	certificates/$hostname-intermediate.crt\n";
	print "Wrote combined PEM Cert to:	certificates/$hostname.pem\n";
	unlink "certificates/$hostname.csr";
}

print $LOG "====== StartSSL End of Log ======\n\n";
close $LOG;
