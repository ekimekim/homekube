

ca/ca-key.pem: ca/ca.pem

ca/ca.pem: ca/config.json ca/root-csr.json
	cfssl gencert -initca -config=ca/config.json ca/root-csr.json | cfssljson -bare ca/root
