
NODES := charm
SUDO := sudo # override this to "" if sudo not desired

REPOSITORY := registry.xenon.ekime.kim

.DELETE_ON_ERROR:
.ONESHELL:
SHELL = /bin/bash
.SHELLFLAGS = -euc

# The all target should generate all files (ie. execute all non-install targets).
# As of writing, the only targets this generates that executing all install targets would not
# is kubeconfigs/admin.kubeconfig and dependencies. That file can't easily be installed automatically.
.PHONY: all
all: keys kubeconfigs secrets manifests static-pods generated-files images

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

# Manifests are handled by manifests/Makefile.
.PHONY: manifests
manifests:
	$(MAKE) -C manifests/

STATIC_POD_JSONNETS := $(wildcard static-pods/*.jsonnet)
STATIC_PODS := $(STATIC_POD_JSONNETS:.jsonnet=.yaml)
.PHONY: static-pods
static-pods: $(STATIC_PODS)

GENERATED_FILE_JSONNETS := $(wildcard generated-files/*.jsonnet)
GENERATED_FILES := $(GENERATED_FILE_JSONNETS:.jsonnet=.yaml)
.PHONY: generated-files
generated-files: $(GENERATED_FILES)

DOCKERFILES := $(wildcard images/*/Dockerfile)
# Strip /Dockerfile from end. Use "images/IMAGE" as the target name to avoid colissions.
IMAGES := $(DOCKERFILES:/Dockerfile=)
.PHONY: images
images: $(IMAGES)

# For now just rebuild images every time and rely on docker's caching. This is unfortunately
# slow but it's difficult to predicate Make on "anything in the folder changed".
.PHONY: $(IMAGES)
$(IMAGES):
	IMAGE=$$(basename "$@")
	TAG="$(REPOSITORY)/$$IMAGE:$$(git rev-parse HEAD)"
	docker build -t "$$TAG" "$@"
	docker push "$$TAG"

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

# static pod manifests
static-pods/%.yaml: static-pods/%.jsonnet
	jsonnet "$<" > "$@"

# generated yaml files
generated-files/%.yaml: generated-files/%.jsonnet $(SECRETS)
	jsonnet "$<" > "$@"

.PHONY: install-kubelet
NODE := $(shell hostname)
install-kubelet: ca/root.pem ca/nodes/$(NODE).pem ca/nodes/$(NODE)-key.pem kubeconfigs/nodes/$(NODE).kubeconfig files/kubelet.conf.yaml files/kubelet.env files/cni.conflist
	$(SUDO) install -m 644 -t /etc/kubernetes/ ca/root.pem files/kubelet.conf.yaml files/kubelet.env
	$(SUDO) install -m 644 ca/nodes/$(NODE).pem /etc/kubernetes/kubelet.pem
	$(SUDO) install -m 600 ca/nodes/$(NODE)-key.pem /etc/kubernetes/kubelet-key.pem
	$(SUDO) install -m 600 kubeconfigs/nodes/$(NODE).kubeconfig /etc/kubernetes/kubelet.kubeconfig
	$(SUDO) install -m 644 -D files/cni.conflist /etc/cni/net.d/10-k8s.conflist

.PHONY: install-scheduler
install-scheduler: install-kubelet kubeconfigs/kube-scheduler.kubeconfig static-pods/scheduler.yaml
	$(SUDO) install -m 600 kubeconfigs/kube-scheduler.kubeconfig /etc/kubernetes/
	$(SUDO) install -m 644 static-pods/scheduler.yaml /etc/kubernetes/manifests

.PHONY: install-controller-manager
install-controller-manager: install-kubelet kubeconfigs/kube-controller-manager.kubeconfig static-pods/controller-manager.yaml ca/service-accounts-key.pem
	$(SUDO) install -m 600 -t /etc/kubernetes/ kubeconfigs/kube-controller-manager.kubeconfig ca/service-accounts-key.pem
	$(SUDO) install -m 644 static-pods/controller-manager.yaml /etc/kubernetes/manifests

.PHONY: install-etcd
install-etcd: install-kubelet files/etcd.conf.yaml static-pods/etcd.yaml
	$(SUDO) install -m 644 files/etcd.conf.yaml /etc/kubernetes
	$(SUDO) install -m 644 static-pods/etcd.yaml /etc/kubernetes/manifests

.PHONY: install-api-server
install-api-server: install-kubelet ca/api-server.pem ca/api-server-key.pem ca/service-accounts.pem ca/service-accounts-key.pem files/audit-policy.yaml generated-files/encryption-config.yaml static-pods/api-server.yaml
	$(SUDO) install -m 644 -t /etc/kubernetes ca/api-server.pem ca/service-accounts.pem files/audit-policy.yaml
	$(SUDO) install -m 600 -t /etc/kubernetes ca/api-server-key.pem ca/service-accounts-key.pem generated-files/encryption-config.yaml
	$(SUDO) install -m 644 -t /etc/kubernetes/manifests static-pods/api-server.yaml

.PHONY: install-master
install-master: install-etcd install-api-server install-scheduler install-controller-manager

.PHONY: apply-manifests
apply-manifests: manifests
	kubectl --context=xenon apply -f manifests/manifests.yaml --prune -l managed-by=homekube
