#!/usr/bin/perl
use strict;
use warnings;
use lib ".";
use functions;
use Net::OpenSSH;
use Data::Dumper;

if ( @ARGV != 1 ) {
	print "Usage: $0 <fqdn>\n";
	exit 1;
}

my $domain = $ARGV[0];
my $validatehost = "";
my $validatepath = "";

## Find the host to validate....
foreach my $node ( keys $xml->{domains}{domain} ) {
	if ( $node eq $ARGV[0] ) {
		$validatehost = $xml->{domains}{domain}{$node}{validatehost};
		$validatepath = $xml->{domains}{domain}{$node}{validatepath};
		last;
	}
}

my $json = 'RequestData={
	"tokenID": "' . $xml->{config}->{Token} . '",
	"actionType": "ApplyWebControl",
	"hostname": "' . $domain . '"
}';

print "Getting validation string...\n";
my %results = functions::libcurl_post($json);

$results{body} =~ /"errorCode": (.+),/;
my $errorcode = $1;
if ( $errorcode != 0 ) {
	$results{body} =~ /"shortMsg": "(.+)"/;
	print "Received Error Code: $errorcode - $1\n\n";
	exit 1;
}

$results{body} =~ /"data": "(.+)"/;
my $data = $1;

if ( $validatehost eq "" ) {
	print "No validatehost specified. Reverting to manual validation.\n\n";
	print "To continue, log into the host serving your web site for $domain and create a file $domain.html\n\n";
	print "This file should be available at http://$domain/$domain.html\n\n";
	print "The file should contain the string: $data\n\n";
	print "When done, press Enter to continue (or Ctrl+C to abort):\n";
	local( $| ) = ( 1 );
	my $waitforuseraction = <STDIN>;
} else {
	## Create the validation file on the server.
	print "Sending validation string to server: $validatehost...\n";
	my $ssh = Net::OpenSSH->new($validatehost) or die "ERROR: Unable to connect " . $!;
	$ssh->system("echo \"$data\" > $validatepath$domain.html");
}

print "Validating with StartSSL...\n";
$json = 'RequestData={
	"tokenID": "' . $xml->{config}->{Token} . '",
        "actionType" : "WebControlValidation",
	"hostname": "' . $domain . '"
}';

%results = functions::libcurl_post($json);

print "Status:\n$results{body}\n";
