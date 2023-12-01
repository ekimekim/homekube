
NODES := charm

.DELETE_ON_ERROR:
.ONESHELL:
SHELL = /bin/bash
.SHELLFLAGS = -euc

.PHONY: all
all: keys kubeconfigs secrets manifests static-pods generated-files

.PHONY: clean
clean:
	git clean -fX

CSRS := $(wildcard ca/*-csr.json)
NODEKEYS := $(addsuffix .pem,$(NODES))
KEYS := $(CSRS:-csr.json=.pem) $(addprefix ca/nodes/,$(NODEKEYS))
.PHONY: keys
keys: $(KEYS)

CONFIGSPECS := $(wildcard kubeconfigs/*.jsonnet)
NODECONFIGS := $(addsuffix .kubeconfig,$(NODES))
KUBECONFIGS := $(CONFIGSPECS:.jsonnet=.kubeconfig) $(addprefix kubeconfigs/nodes/,$(NODECONFIGS))
.PHONY: kubeconfigs
kubeconfigs: $(KUBECONFIGS)

SECRET_GENERATORS := $(wildcard secrets/*.sh)
SECRETS := $(SECRET_GENERATORS:.sh=.secret)
.PHONY: secrets
secrets: $(SECRETS)

MANIFEST_JSONNETS := $(wildcard manifests/*.jsonnet)
MANIFESTS := $(MANIFEST_JSONNETS:.jsonnet=.yaml)
.PHONY: manifests
manifests: $(MANIFESTS)

STATIC_POD_JSONNETS := $(wildcard static-pods/*.jsonnet)
STATIC_PODS := $(STATIC_POD_JSONNETS:.jsonnet=.yaml)
.PHONY: static-pods
static-pods: $(STATIC_PODS)

GENERATED_FILE_JSONNETS := $(wildcard generated-files/*.jsonnet)
GENERATED_FILES := $(GENERATED_FILE_JSONNETS:.jsonnet=.yaml)
.PHONY: generated-files
generated-files: $(GENERATED_FILES)

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
kubeconfigs/%.kubeconfig: kubeconfigs/%.jsonnet kubeconfigs/kubeconfig.libsonnet ca/%.pem ca/%-key.pem
	jsonnet "$<" > "$@"

# this folder has no non-generated files so it needs to be created on fresh checkout
kubeconfigs/nodes:
	mkdir "$@"

# generate node kubeconfigs
kubeconfigs/nodes/%.kubeconfig: kubeconfigs/kubeconfig.libsonnet ca/nodes/%.pem ca/nodes/%-key.pem kubeconfigs/nodes
	jsonnet "$<" \
		--tla-str user="system:node:$*" \
		--tla-code 'clientCertificate=importstr "ca/nodes/$*.pem"' \
		--tla-code 'clientKey=importstr "ca/nodes/$*-key.pem"' \
		>"$@"

# generate secrets from scripts
secrets/%.secret: secrets/%.sh
	bash "$<" > "$@"

# generate manifest yamls from jsonnets
# each generated yaml may be a list of manifests or an object where manifests are values
MANIFEST_LIBSONNETS = $(wildcard manifests/*.libsonnet)
manifests/%.yaml: manifests/%.jsonnet $(MANIFEST_LIBSONNETS) $(SECRETS)
	jsonnet --yaml-stream -e '
		function(x)
			if std.type(x) == "array" then x
			else if std.type(x) == "object" then std.objectValues(x)
			else error "Expected array or object"
	' --tla-code 'x=import "$<"' > "$@"

# static pod manifests
static-pods/%.yaml: static-pods/%.jsonnet
	jsonnet "$<" > "$@"

# generated yaml files
generated-files/%.yaml: generated-files/%.jsonnet $(SECRETS)
	jsonnet "$<" > "$@"

.PHONY: install-kubelet
NODE := $(shell hostname)
install-kubelet: ca/root.pem ca/nodes/$(NODE).pem ca/nodes/$(NODE)-key.pem kubeconfigs/nodes/$(NODE).kubeconfig files/kubelet.conf.yaml files/kubelet.env
	install -m 644 -t /etc/kubernetes/ ca/root.pem files/kubelet.conf.yaml files/kubelet.env
	install -m 644 ca/nodes/$(NODE).pem /etc/kubernetes/kubelet.pem
	install -m 600 ca/nodes/$(NODE)-key.pem /etc/kubernetes/kubelet-key.pem
	install -m 600 kubeconfigs/nodes/$(NODE).kubeconfig /etc/kubernetes/kubelet.kubeconfig

.PHONY: install-scheduler
install-scheduler: install-kubelet kubeconfigs/kube-scheduler.kubeconfig static-pods/scheduler.yaml
	install -m 600 kubeconfigs/kube-scheduler.kubeconfig /etc/kubernetes/
	install -m 644 static-pods/scheduler.yaml /etc/kubernetes/manifests

.PHONY: install-controller-manager
install-controller-manager: install-kubelet kubeconfigs/kube-controller-manager.kubeconfig static-pods/controller-manager.yaml ca/service-accounts-key.pem
	install -m 600 -t /etc/kubernetes/ kubeconfigs/kube-controller-manager.kubeconfig ca/service-accounts-key.pem
	install -m 644 static-pods/controller-manager.yaml /etc/kubernetes/manifests

.PHONY: install-etcd
install-etcd: install-kubelet files/etcd.yaml.conf static-pods/etcd.yaml
	install -m 644 files/etcd.yaml.conf /etc/kubernetes
	install -m 644 static-pods/etcd.yaml /etc/kubernetes/manifests

.PHONY: install-api-server
install-api-server: install-kubelet ca/api-server.pem ca/api-server-key.pem ca/service-account.pem ca/service-accounts-key.pem manifests/encryption-config.yaml static-pods/api-server.yaml
	install -m 644 -t /etc/kubernetes ca/api-server.pem ca/service-account.pem
	install -m 600 -t /etc/kubernetes ca/api-server-key.pem ca/service-accounts-key.pem manifests/encryption-config.yaml
	install -m 644 -t /etc/kubernetes/manifests static-pods/api-server.yaml

.PHONY: install-master
install-master: install-etcd install-api-server install-scheduler install-controller-manager

.PHONY: apply-manifests
apply-manifests: manifests
	kubectl --context=xenon apply -f manifests/
