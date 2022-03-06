

ca/ca-key.pem: ca/ca.pem

ca/ca.pem: ca/ca-config.json ca/ca-csr.json
	cfssl gencert -initca -config=ca/ca-config.json ca/ca-csr.json | cfssljson -bare ca/ca
