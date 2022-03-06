

# keys are made alongside certs
ca/%-key.pem: ca/%.pem

# special-case root cert
ca/root.pem: ca/config.json ca/root-csr.json
	cfssl gencert -initca -config=ca/config.json ca/root-csr.json | cfssljson -bare ca/root

# other certs
ca/%.pem: ca/%-csr.json ca/root.pem
	cfssl gencert -ca=ca/root.pem -ca-key=ca/root-key.pem -config=ca/config.json -profile=kubernetes ca/$*-csr.json | cfssljson -bare ca/$*
