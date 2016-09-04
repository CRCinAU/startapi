#!/usr/bin/perl
use strict;
use warnings;
use Net::OpenSSH;
use Data::Dumper;
use XML::Simple;

if ( @ARGV != 1 ) {
	print "Usage: $0 <fqdn>\n";
	exit 1;
}


my $xml = XMLin("deployment.xml", SuppressEmpty => '', KeyAttr => {} );

my $domain = $ARGV[0];
my ($name, $host, $pem, $cert, $key, $intermediate, $execute);

## Find the host to validate....
foreach my $node ( @{ $xml->{domains}->{domain} } ) {
	if ( $node->{name} eq $domain ) {
		$name		= $node->{name};
		$host		= $node->{host};
		$pem		= $node->{pem};
		$cert		= $node->{cert};
		$key		= $node->{key};
		$intermediate	= $node->{intermediate};
		$execute	= $node->{execute};
		last;
	}
}
if ( !$host ) {
	print "No host found for $domain\n";
	exit 1;
}

print "Domain Name: $name\nHost: $host\nPEM File: $pem\nCert File: $cert\nKey File: $key\nIntermediate: $intermediate\n\n";
open my $LOG, ">>", "certificates/$domain.log" or die "Unable to open log file: $!\n";
my $date = localtime();
print $LOG <<EOF;
====== Deployment - Start of Log ======
Date:			$date
EOF

## Load the certificates.
print "Loading certificates...\n";
my %certificates;
my $errors = 0;
foreach my $file ( "$name.key", "$name.pem", "$name.crt", "$name-intermediate.crt" ) {
	if ( -f "certificates/$file" ) {
		open ( my $fh, "<", "certificates/$file" ) or die "Unable to open $file: $!\n";
		$certificates{$file} = do { local $/; <$fh>; };
	} else {
		print "File certificates/$file does not exist!\n";
		$errors++;
	}
}

if ( $errors ) {
	print "\nToo many errors. Aborting...\n";
	exit 1;
}

print "Connecting to $host...";
my $ssh = Net::OpenSSH->new($host) or die " Unable to connect " . $! . "\n";
print " Connected!\n";
print $LOG "Deployment host:\t$host\n";

if ( $key ) {
	print "Installing Private Key...";
	$ssh->scp_put("certificates/$name.key", $key);
	print $LOG "Private key:\t\t$key\n";
	print "Done.\n";
}

if ( $cert ) {
	print "Installing Certificate...";
	$ssh->scp_put("certificates/$name.crt", $cert);
	print $LOG "Certificate:\t\t$cert\n";
	print "Done.\n";
}

if ( $pem ) {
	print "Installing PEM Certificate...";
	$ssh->scp_put("certificates/$name.pem", $pem);
	print $LOG "PEM file:\t$pem\n";
	print "Done.\n";
}

if ( $intermediate ) {
	print "Installing intermediate cert...";
	$ssh->scp_put("certificates/$name-intermediate.crt", $intermediate);
	print $LOG "Intermediate cert:\t$intermediate\n";
	print "Done.\n";
}

if ( $execute ) {
	print "Running post-installation command...";
	print $LOG "\nRunning post-install command:\n\t\t$execute\n";
	my $result = $ssh->capture($execute);
	print $LOG "Post-install results:\n\t\t$result\n";
	print "Done.\n";
}

print "Certificates installed!\n";
print $LOG "====== Deployment - End of Log ======\n\n";
close $LOG;
