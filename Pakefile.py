
import json
from socket import gethostname

NODES = ["charm"]
REPOSITORY = "registry.xenon.ekime.kim"
INSTALL_WITH_SUDO = True
CONTEXT = "xenon"

git = cmd("git")
jsonnet = cmd("jsonnet")
docker = cmd("docker")

# The default target should generate all files (ie. execute all non-install targets).
# As of writing, the only targets this generates that executing all install targets would not
# is kubeconfigs/admin.kubeconfig and dependencies. That file can't easily be installed automatically.
group("default", [
	"keys",
	"kubeconfigs",
	"secrets",
	"manifests",
	"static_pods",
	"generated_files",
	"images",
])

@always()
def clean(deps):
	git("clean", "-fX").run()

keys = [path.replace("-csr.json", ".pem") for path in glob("ca/*-csr.json")]
keys += [f"ca/nodes/{node}.pem" for node in NODES]
group("keys", keys)

kubeconfigs = [path.replace(".jsonnet", ".kubeconfig") for path in glob("kubeconfigs/*.jsonnet")]
kubeconfigs += [f"kubeconfigs/nodes/{node}.kubeconfig" for node in NODES]
group("kubeconfigs", kubeconfigs)

secrets = [path.replace(".sh", ".secret") for path in glob("secrets/*.sh")]
group("secrets", secrets)

# Manifests are handled by manifests/Makefile for now, which writes manifests/manifests.yaml.
# This is a rare instance of a non-virtual always rule.
@target("manifests/manifests.yaml", ["always"])
def manifests(target, deps):
	cmd("make").workdir("manifests/").run()

static_pods = [path.replace(".jsonnet", ".yaml") for path in glob("static-pods/*.jsonnet")]
group("static_pods", static_pods)

generated_files = [path.replace(".jsonnet", ".yaml") for path in glob("generated-files/*.jsonnet")]
group("generated_files", generated_files)

# Use "images/IMAGE" as the target name (instead of just IMAGE) to avoid colissions.
images = glob("images/*")
group("images", images)

# For now just rebuild images every time and rely on docker's caching.
# TODO fix this now that we aren't limited to Make's issues
for image in images:
	@always(name=image)
	def build_image(deps):
		name = os.path.basename(image)
		commit = git("rev-parse", "HEAD").get_output()
		tag = f"{REPOSITORY}/{name}:{commit}"
		docker("build", "-t", tag, image)
		docker("push", tag)

# Keys are made as a side effect of certs, so depend on certs with a do-nothing recipe.
# This could cause failures if the key is changed/deleted on disk but not the pem, but
# that seems unlikely to happen.
@pattern(r"(.*)-key\.pem", [r"\1.pem"])
def cert_key(target, deps, match):
	pass

gencert = cmd("cfssl", "gencert")

def write_cert(name, data):
	"""Takes output from cfssl gencert and writes to NAME.pem and NAME-key.pem"""
	data = {k: v for k, v in data.items() if k in ["key", "cert"]}
	cmd("cfssljson", "-bare", name).stdin_json(data).run()

# special-case root cert
@target("ca/root.pem", ["ca/config.json", "ca/root-csr.json"])
def root_cert(target, deps):
	data = gencert("-initca", "-config=ca/config.json", "ca/root-csr.json").json()
	write_cert("ca/root", data)

# other certs
@pattern(r"(.*)\.pem", [r"\1-csr.json", "ca/root.pem"])
def cert(target, deps, match):
	data = gencert(
		"-ca=ca/root.pem",
		"-ca-key=ca/root-key.pem",
		"-config=ca/config.json",
		"-profile=kubernetes",
		f"{match.group(1)}-csr.json",
	).json()
	write_cert(match.group(1), data)

# generate node CSRs
@pattern(r"ca/nodes/(.*)-csr\.json", ["ca/nodes/generate-csr"])
def node_csr(target, deps, match):
	cmd("ca/nodes/generate-csr", match.group(1)).stdout(target).run()

# generate node kubeconfigs. must be before general kubeconfigs to avoid the wrong one matching.
@pattern(r"kubeconfigs/nodes/(.*)\.kubeconfig", [
	"kubeconfigs/kubeconfig.libsonnet",
	r"ca/nodes/\1.pem",
	r"ca/nodes/\1-key.pem",
])
def node_kubeconfig(target, deps, match):
	node = match.groups(1)
	input, cert, key = deps
	jsonnet(input,
		"--tla-str", f"user=system:node:{node}",
		"--tla-code", f"clientCertificate=importstr {json.dumps(cert)}",
		"--tla-code", f"clientKey=importstr {json.dumps(key)}",
	).stdout(target).run()

# generate kubeconfigs
@pattern(r"kubeconfigs/(.*)\.kubeconfig", [
	r"kubeconfigs/\1.jsonnet",
	"kubeconfigs/kubeconfig.libsonnet",
	r"ca/\1.pem",
	r"ca/\1-key.pem",
])
def kubeconfig(target, deps, match):
	input, *_ = deps
	jsonnet(input).stdout(target).run()

# generate secrets from scripts
@pattern(r"secrets/(.*)\.secret", [r"secrets/\1.sh"])
def secret(target, deps, match):
	input, = deps
	cmd("bash", input).stdout(target).run()

# static pod manifests
@pattern(r"static-pods/(.*)\.yaml", [r"static-pods/\1.jsonnet"])
def static_pod(target, deps, match):
	input, = deps
	jsonnet(input).stdout(target).run()

# generated yaml files
@pattern(r"generated-files/(.*)\.yaml", [r"generated-files/\1.jsonnet"] + secrets)
def generated_file(target, deps, match):
	input, *_ = deps
	jsonnet(input).stdout(target).run()

def install(mode, *args):
	install = (sudo if INSTALL_WITH_SUDO else cmd)("install", "--mode", f"{mode:03o}", *args).run()

node = gethostname()
@virtual([
	"ca/root.pem",
	f"ca/nodes/{node}.pem",
	f"ca/nodes/{node}-key.pem",
	f"kubeconfigs/nodes/{node}.kubeconfig",
	"files/kubelet.conf.yaml",
	"files/kubelet.env",
	"files/cni.conflist",
])
def install_kubelet(deps):
	install(0o644, "ca/root.pem", "files/kubelet.conf.yaml", "files/kubelet.env", "/etc/kubernetes/")
	install(0o644, f"ca/nodes/{node}.pem", "/etc/kubernetes/kubelet.pem")
	install(0o644, f"ca/nodes/{node}.pem", "/etc/kubernetes/kubelet.pem")
	install(0o600, f"ca/nodes/{node}-key.pem", "/etc/kubernetes/kubelet-key.pem")
	install(0o600, f"kubeconfigs/nodes/{node}.kubeconfig", "/etc/kubernetes/kubelet.kubeconfig")
	install(0o644, "-D", "files/cni.conflist", "/etc/cni/net.d/10-k8s.conflist")

@virtual([
	"install_kubelet",
	"kubeconfigs/kube-scheduler.kubeconfig",
	"static-pods/scheduler.yaml",
])
def install_scheduler(deps):
	install(0o600, "kubeconfigs/kube-scheduler.kubeconfig", "/etc/kubernetes/")
	install(0o644, "static-pods/scheduler.yaml", "/etc/kubernetes/manifests/")

@virtual([
	"install_kubelet",
	"kubeconfigs/kube-controller-manager.kubeconfig",
	"static-pods/controller-manager.yaml",
	"ca/service-accounts-key.pem",
])
def install_controller_manager(deps):
	install(0o600, "kubeconfigs/kube-controller-manager.kubeconfig", "ca/service-accounts-key.pem", "/etc/kubernetes/")
	install(0o644, "static-pods/controller-manager.yaml", "/etc/kubernetes/manifests/")

@virtual([
	"install_kubelet",
	"files/etcd.conf.yaml",
	"static-pods/etcd.yaml",
])
def install_etcd(deps):
	install(0o644, "files/etcd.conf.yaml", "/etc/kubernetes/")
	install(0o644, "static-pods/etcd.yaml", "/etc/kubernetes/manifests/")

@virtual([
	"install_kubelet",
	"ca/api-server.pem",
	"ca/api-server-key.pem",
	"ca/service-accounts.pem",
	"ca/service-accounts-key.pem",
	"files/audit-policy.yaml",
	"generated-files/encryption-config.yaml",
	"static-pods/api-server.yaml",
])
def install_api_server(deps):
	install(0o644, "ca/api-server.pem", "ca/service-accounts.pem", "files/audit-policy.yaml", "/etc/kubernetes/")
	install(0o600, "ca/api-server-key.pem", "ca/service-accounts-key.pem", "generated-files/encryption-config.yaml", "/etc/kubernetes/")
	install(0o644, "static-pods/api-server.yaml", "/etc/kubernetes/manifests/")

group("install_master", ["install_etcd", "install_api_server", "install_scheduler", "install_controller_manager"])

@virtual(["manifests/manifests.yaml"])
def apply_manifests(deps):
	cmd("kubectl", f"--context={CONTEXT}", "apply", "-f", "manifests/manifests.yaml", "--prune", "-l", "managed-by=homekube").run()
