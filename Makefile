
NODES := example

.PHONY: all
all: keys

.DELETE_ON_ERROR:

CSRS := $(wildcard ca/*-csr.json)
NODEKEYS := $(addsuffix .pem,$(NODES))
KEYS := $(CSRS:-csr.json=.pem) $(addprefix ca/nodes/,$(NODEKEYS))
.PHONY: keys
keys: $(KEYS)

# keys are made alongside certs
%-key.pem: %.pem

# special-case root cert
ca/root.pem: ca/config.json ca/root-csr.json
	cfssl gencert -initca -config=ca/config.json ca/root-csr.json | jq '{key, cert}' | cfssljson -bare ca/root

# other certs
%.pem: %-csr.json ca/root.pem
	cfssl gencert -ca=ca/root.pem -ca-key=ca/root-key.pem -config=ca/config.json -profile=kubernetes $*-csr.json | jq '{key, cert}' | cfssljson -bare $*

# generate node CSRs
.PRECIOUS: ca/nodes/%-csr.json
ca/nodes/%-csr.json: ca/nodes/generate-csr
	ca/nodes/generate-csr "$*" > "$@"

# generate kubeconfigs
configs/%.kubeconfig: configs/%.jsonnet configs/kubeconfig.libsonnet ca/%.pem ca/%-key.pem
	jsonnet "$<" > "$@"

configs/nodes:
	mkdir "$@"

# generate node kubeconfigs
configs/nodes/%.kubeconfig: configs/kubeconfig.libsonnet ca/nodes/%.pem ca/nodes/%-key.pem configs/nodes
	jsonnet "$<" \
		--tla-str user="system:node:$*" \
		--tla-code 'clientCertificate=importstr "ca/nodes/$*.pem"' \
		--tla-code 'clientKey=importstr "ca/nodes/$*-key.pem"' \
		>"$@"
