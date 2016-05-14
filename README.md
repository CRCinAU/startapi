# startapi

A perl implementation of [StartAPI](https://www.startssl.com/StartAPI) certificate interface of [StartSSL](https://www.startssl.com).

### Preparations

1) Log into StartSSL and create a new "Email Validation" for use with the API.

2) Select the certificate in the [Start API Settings](https://startssl.com/StartAPI/ApplyPart).

3) Generate a API Token for use in config.xml

### Configuration

1) Copy config.xml.sample to config.xml and fill out the paths to your API user certificate and add your Token.

2) Add your domains for validation to config.xml

The <name> element should contain the root domain name to be validated.

<validatehost> should be the server that hosts a web site at http://yourdomain.com. The scripts will connect to this via SSH to copy the validation information to a file at http://yourdomain.com/yourdomain.com.html. You should set up this host in *~/.ssh/config* to allow automated connections to it.

<validatepath> should point to the document root of http://yourdomain.com

You can add multiple domains to this file with multiple <domain> elements.

### Usage

To validate a domain, run *./validate_domain.pl yourdomain.com*.

To create a certificate after validation, run *./create_certificate.pl www.yourdomain.com*.

To retrieve a certificate previously issued or in a Pending status, use *./retrieve_certificate.pl orderID*.
