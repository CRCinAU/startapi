package functions;
use strict;
use warnings;
use parent 'Exporter';
use WWW::Curl::Easy;
use XML::Simple;
use IPC::Open3;
use Data::Dumper;

our $xml = XMLin('config.xml');
our @EXPORT = qw($xml);

sub libcurl_post($) {
	my $post_content = shift;

	my @bad_headers = ('Expect:');
	my $body = "";
	my $headers = "";

	my $curl = WWW::Curl::Easy->new;
	if ( $xml->{config}->{Verbose} ) {
		$curl->setopt(CURLOPT_VERBOSE, 1);
	}
	$curl->setopt(CURLOPT_SSLCERT, "./" . $xml->{config}->{SSLCert});
	$curl->setopt(CURLOPT_SSLKEY, "./" . $xml->{config}->{SSLKey});
	$curl->setopt(CURLOPT_URL, $xml->{config}->{URI});
	$curl->setopt(CURLOPT_POST, 1);
	$curl->setopt(CURLOPT_POSTFIELDS, $post_content);
	$curl->setopt(CURLOPT_WRITEHEADER, \$headers );
	$curl->setopt(CURLOPT_FILE, \$body);
	$curl->setopt(CURLOPT_HTTPHEADER, \@bad_headers );
	$curl->perform();

	my %return;
	$return{body} = $body;
	$return{headers} = $headers;

	return %return;
}

sub get_cert_info($) {
	my $cert = shift;
	my %cert_info;

        my $cmd = "/usr/bin/openssl";
        my @args = qw(x509 -noout -text);
        my $pid =  open3(\*WRITER, \*READER, 0, $cmd, @args);
        print WRITER $cert;
        close WRITER;

        my $openssl = do { local $/; <READER>; };

        $openssl =~ /Not After : (.*)/;
	$cert_info{expires} = $1;

	$openssl =~ /Not Before: (.*)/;
	$cert_info{begins} = $1;

	$openssl =~ /DNS:(.*)/;
	$cert_info{hostname} = $1;

        return %cert_info;
}
