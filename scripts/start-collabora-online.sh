#!/bin/sh

# Fix domain name resolution from jails
cp /etc/resolv.conf /etc/hosts /opt/lool/systemplate/etc/

# Set language
echo "LANG=de_DE.utf8" > /etc/default/locale 

# Turn off SSL & turn on TLS
loolconfig set ssl.enable false
loolconfig set ssl.termination true

if test "${DONT_GEN_SSL_CERT-set}" == set; then
	# Generate new SSL certificate instead of using the default
	mkdir -p /opt/ssl/
	cd /opt/ssl/
	mkdir -p certs/ca
	openssl rand -writerand /opt/lool/.rnd
	openssl genrsa -out certs/ca/root.key.pem 2048
	openssl req -x509 -new -nodes -key certs/ca/root.key.pem -days 9131 -out certs/ca/root.crt.pem -subj "/C=DE/ST=RP/L=Mainz/O=Dummy Authority/CN=Dummy Authority"
	mkdir -p certs/{servers,tmp}
	mkdir -p certs/servers/localhost
	openssl genrsa -out certs/servers/localhost/privkey.pem 2048
	if test "${cert_domain-set}" == set; then
		openssl req -key certs/servers/localhost/privkey.pem -new -sha256 -out certs/tmp/localhost.csr.pem -subj "/C=DE/ST=RP/L=Mainz/O=Dummy Authority/CN=localhost"
	else
		openssl req -key certs/servers/localhost/privkey.pem -new -sha256 -out certs/tmp/localhost.csr.pem -subj "/C=DE/ST=RP/L=Mainz/O=Dummy Authority/CN=${cert_domain}"
	fi
	openssl x509 -req -in certs/tmp/localhost.csr.pem -CA certs/ca/root.crt.pem -CAkey certs/ca/root.key.pem -CAcreateserial -out certs/servers/localhost/cert.pem -days 9131
	mv certs/servers/localhost/privkey.pem /etc/loolwsd/key.pem
	mv certs/servers/localhost/cert.pem /etc/loolwsd/cert.pem
	mv certs/ca/root.crt.pem /etc/loolwsd/ca-chain.cert.pem
fi

# Disable warning/info messages of LOKit by default
if test "${SAL_LOG-set}" == set; then
	SAL_LOG="-INFO-WARN"
fi

# Replace trusted host and set admin username and password
loolconfig set storage.wopi.host "${domain}"
printf "${username}\n${password}\n${password}" | loolconfig set-admin-password
if [ -z "${dictionaries}" ]; then
	loolconfig set allowed_languages "de_DE en_GB en_US es_ES fr_FR it nl pt_BR pt_PT ru"
else
	loolconfig set allowed_languages "${dictionaries}"
fi

# Turn off welcome dialog
loolconfig set welcome.enable "false"

# Restart when /etc/loolwsd/loolwsd.xml changes
[ -x /usr/bin/inotifywait -a /usr/bin/killall ] && (
	/usr/bin/inotifywait -e modify /etc/loolwsd/loolwsd.xml
	echo "$(ls -l /etc/loolwsd/loolwsd.xml) modified --> restarting"
	/usr/bin/killall -1 loolwsd
) &

# Generate WOPI proof key
loolwsd-generate-proof-key

# Start loolwsd
exec /usr/bin/loolwsd --version --o:sys_template_path=/opt/lool/systemplate --o:child_root_path=/opt/lool/child-roots --o:file_server_root_path=/usr/share/loolwsd --o:user_interface.mode=notebookbar ${extra_params}
