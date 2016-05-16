#!/usr/bin/perl
use strict;
use warnings;
use lib ".";
use functions;
use POSIX 'strftime';
use URI::Escape;
use MIME::Base64;

if ( @ARGV != 1 ) {
	print "Usage: $0 <fqdn>\n";
	exit 1;
}

my $hostname = $ARGV[0];

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
my %results = functions::libcurl_post($json);

$results{body} =~ /"errorCode": (.+),/;
my $errorcode = $1;
if ( $errorcode != 0 ) {
	$results{body} =~ /"shortMsg": "(.+)"/;
	print "Received Error Code: $errorcode - $1\n\n";
	exit 1;
}

$results{body} =~ /"orderStatus": (.+),/;
my $orderStatus = $1;

$results{body} =~ /"orderID": "(.+)",/;
my $orderID = $1;

$results{body} =~ /"orderNo": "(.+)",/;
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

	## Print the certificate to file.
	$results{body} =~ /"certificate": "(.+)",/;
	my $certificate = decode_base64($1);
	$results{body} =~ /"intermediateCertificate": "(.+)",/;
	my $intermediatecertificate = decode_base64($1);

	## Get the cert info...
	my %cert_info = functions::get_cert_info($certificate);
	print $LOG "Cert Begins:            $cert_info{begins}\n";
	print $LOG "Cert Expires:           $cert_info{expires}\n";

	if ( $results{body} =~ /"certificateFieldMD5": "(.+)",/ ) {
		print $LOG "Certificate MD5:	$1\n";
	}
	if ( $results{body} =~ /"intermediateCertificateFieldMD5": "(.+)"/ ) {
		print $LOG "Intermediate MD5:	$1\n";
	}

	## Write the certificate to disk.
	open my $CERT, ">", "certificates/$hostname.crt" or die "Unable to write certificate: $!\n";
	print $CERT $certificate;
	close $CERT;

	## Print the intermediate to file,
	open $CERT, ">", "certificates/$hostname-intermediate.crt" or die "Unable to write certificate: $!\n";
	print $CERT $intermediatecertificate;
	close $CERT;

	## Write out the combined PEM.
	open $CERT, ">", "certificates/$hostname.pem" or die "Unable to write certificate: $!\n";
	print $CERT $certificate;
	print $CERT $intermediatecertificate;
	close $CERT;

	## Get the expiry date of the certificate.
	
	print "Wrote Certificate to:		certificates/$hostname.crt\n";
	print "Wrote Intermediate Cert to:	certificates/$hostname-intermediate.crt\n";
	print "Wrote combined PEM Cert to:	certificates/$hostname.pem\n";
	unlink "certificates/$hostname.csr";
}

print $LOG "====== StartSSL End of Log ======\n\n";
close $LOG;
