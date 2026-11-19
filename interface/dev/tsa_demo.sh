#!/bin/sh
# Autorite d'horodatage FICTIVE (OpenSSL) pour la demonstration et les tests : ses jetons n'ont AUCUNE valeur juridique.
# Usage : sh tsa_demo.sh <dossier>
set -e
D="${1:-demo/tsa}"; mkdir -p "$D"; cd "$D"
[ -f tsa.crt ] && exit 0
openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.crt -days 3650 -subj "/C=FR/O=DigSpill DEMO/CN=DigSpill DEMO Racine (fictive)" 2>/dev/null
openssl req -newkey rsa:2048 -nodes -keyout tsa.key -out tsa.csr -subj "/C=FR/O=DigSpill DEMO/CN=DigSpill DEMO Horodatage (fictif, non qualifie)" 2>/dev/null
printf "basicConstraints=CA:FALSE\nkeyUsage=critical,digitalSignature,nonRepudiation\nextendedKeyUsage=critical,timeStamping\n" > ext.cnf
openssl x509 -req -in tsa.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out tsa.crt -days 3650 -extfile ext.cnf 2>/dev/null
cat > tsa.cnf <<CNF
[ tsa ]
default_tsa = tsa_demo
[ tsa_demo ]
dir = .
serial = ./serial
signer_cert = ./tsa.crt
certs = ./ca.crt
signer_key = ./tsa.key
signer_digest = sha256
default_policy = 1.2.3.4.1
digests = sha256
accuracy = secs:1
ordering = no
tsa_name = yes
ess_cert_id_chain = no
ess_cert_id_alg = sha256
CNF
echo 01 > serial
