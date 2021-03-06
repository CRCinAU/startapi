#!/usr/bin/perl
use strict;
use warnings;
use lib ".";
use functions;
use POSIX 'strftime';
use URI::Escape;
use MIME::Base64;
use IPC::Open3;

if ( @ARGV != 1 ) {
	print "Usage: $0 <Order ID>\n";
	exit 1;
}

if ( !-d "certificates" ) {
	mkdir "certificates";
}

## Generate the CSR...
my $date = strftime '%Y-%m-%d', localtime;

my $json = 'RequestData={
	"tokenID": "' . $xml->{config}->{Token} . '",
	"actionType": "RetrieveCertificate",
	"orderID": "' . $ARGV[0] . '"
}';

print "Requesting Order ID: $ARGV[0]...\n\n";
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

if ( $orderStatus eq "3" ) {
	print "Order Status:			Rejected.\n";
}
elsif ( $orderStatus eq "1" ) {
	print "Order Status:			Pending. Retrieve certificate later...\n";
}
elsif ( $orderStatus eq "2" ) {
	print "Order Status:			Issued.\n\n";

	## Parse out the certificate data.
	$results{body} =~ /"certificate": "(.+)",/;
	my $certificate = decode_base64($1);
	$results{body} =~ /"intermediateCertificate": "(.+)",/;
	my $intermediatecertificate = decode_base64($1);

	## Get the hostname for the certificate.
	my %cert_info = functions::get_cert_info($certificate);

	open my $LOG, ">>", "certificates/$cert_info{hostname}.log" or die "Unable to open log file: $!\n";
	print $LOG <<EOF;
====== StartSSL Certificate Log ======
Retrieve Certificate Results:
Date:			$date
Order ID:		$orderID
Order Number:		$orderNo
Order Status:		$orderStatus
Obtained from:          $xml->{config}->{URI}
Cert Begins:		$cert_info{begins}
Cert Expires:		$cert_info{expires}
EOF

	if ( $results{body} =~ /"certificateFieldMD5": "(.+)",/ ) {
		print $LOG "Certificate MD5:	$1\n";
	}
	if ( $results{body} =~ /"intermediateCertificateFieldMD5": "(.+)"/ ) {
		print $LOG "Intermediate MD5:	$1\n";
	}
	print $LOG "====== StartSSL End of Log ======\n\n";
	close $LOG;

	## Print the certificate to file.
	open my $CERT, ">", "certificates/$cert_info{hostname}.crt" or die "Unable to write certificate: $!\n";
	print $CERT $certificate;
	close $CERT;

	## Print the intermediate to file.
	open $CERT, ">", "certificates/$cert_info{hostname}-intermediate.crt" or die "Unable to write certificate: $!\n";
	print $CERT $intermediatecertificate;
	close $CERT;

	## Print the combined PEM.
	open $CERT, ">", "certificates/$cert_info{hostname}.pem" or die "Unable to write certificate: $!\n";
	print $CERT $certificate;
	print $CERT $intermediatecertificate;
	close $CERT;
	
	print "Saved order details to:		certificates/$cert_info{hostname}.log\n";
	print "Wrote Certificate to:		certificates/$cert_info{hostname}.crt\n";
	print "Wrote Intermediate Cert to:	certificates/$cert_info{hostname}-intermediate.crt\n";
	print "Wrote combined PEM Cert to:	certificates/$cert_info{hostname}.pem\n";
	
}

