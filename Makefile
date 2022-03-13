
NODES := example

.DELETE_ON_ERROR:

.PHONY: all
all: keys configs manifests

.PHONY: clean
clean:
	git clean -fX

CSRS := $(wildcard ca/*-csr.json)
NODEKEYS := $(addsuffix .pem,$(NODES))
KEYS := $(CSRS:-csr.json=.pem) $(addprefix ca/nodes/,$(NODEKEYS))
.PHONY: keys
keys: $(KEYS)

CONFIGSPECS := $(wildcard config/*.jsonnet)
NODECONFIGS := $(addsuffix .kubeconfig,$(NODES))
CONFIGS := $(CONFIGSPECS:.jsonnet=.kubeconfig) $(addprefix configs/nodes/,$(NODECONFIGS))
.PHONY: configs
configs: $(CONFIGS)

SECRET_GENERATORS := $(wildcard secrets/*.sh)
SECRETS := $(SECRET_GENERATORS:.sh=.secret)
secrets: $(SECRETS)

MANIFEST_JSONNETS := $(wildcard manifests/*.jsonnet)
MANIFESTS := $(MANIFEST_JSONNETS:.jsonnet=.yaml)
manifests: $(MANIFESTS)

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

# this folder has no non-generated files so it needs to be created on fresh checkout
configs/nodes:
	mkdir "$@"

# generate node kubeconfigs
configs/nodes/%.kubeconfig: configs/kubeconfig.libsonnet ca/nodes/%.pem ca/nodes/%-key.pem configs/nodes
	jsonnet "$<" \
		--tla-str user="system:node:$*" \
		--tla-code 'clientCertificate=importstr "ca/nodes/$*.pem"' \
		--tla-code 'clientKey=importstr "ca/nodes/$*-key.pem"' \
		>"$@"

# generate secrets from scripts
secrets/%.secret: secrets/%.sh
	bash "$<" > "$@"

# generate manifest yamls from jsonnets
# each generated yaml may be a single manifest or a list
LIBSONNETS = $(wildcard manifests/*.libsonnet)
manifests/%.yaml: manifests/%.jsonnet $(LIBSONNETS) $(SECRETS)
	jsonnet --yaml-stream -e 'function(x) if std.type(x) == "array" then x else [x]' --tla-code 'x=import "$<"' > "$@"
