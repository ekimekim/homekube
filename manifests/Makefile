
# Standard "sane make" options
MAKEFLAGS += --no-builtin-rules
.SUFFIXES:
.DELETE_ON_ERROR:
.ONESHELL:
SHELL = /bin/bash
.SHELLFLAGS = -euc

# *.jsonnet and */*.jsonnet, except manifests.jsonnet
JSONNETS := $(wildcard *.jsonnet) $(wildcard */*.jsonnet)
JSONNETS := $(filter-out manifests.jsonnet, $(JSONNETS))
YAMLS := $(JSONNETS:.jsonnet=.yaml)
DEPS := $(JSONNETS:.jsonnet=.d)

# Directories which will have all .jsonnet files within them imported into a generated libsonnet
# of the same name.
GENERATE_DIRS := monitoring/dashboards
GENERATE_LIBSONNETS := $(addsuffix .libsonnet, $(GENERATE_DIRS))

# Full yaml file, which is simply all the yamls concatenated.
# This is a relatively trivial transform, but is useful to exist as a file
# for diff purposes.
manifests.yaml: $(YAMLS)
	cat $^ > "$@"

# Generate a libsonnet file for each generate directory.
# Make will consider the directory as having been changed if its file listing changes.
$(GENERATE_LIBSONNETS): %.libsonnet: %
	shopt -s nullglob
	jq -nr '
		[
			"{",
			(
				$$ARGS.positional[]
				| split("/") # split into path components
				| .[-1][:-8] as $$name # take basename, strip ".jsonnet"
				| (.[-2:] | join("/")) as $$path # take last two parts only
				| "  \($$name|tojson): import \($$path|tojson),"
			),
			"}"
		] | join("\n")
	' --args $</*.jsonnet > $@

# Produce a makefile that lists dependencies of each jsonnet file, and include them.
# Notably, the generated dependencies may also include further dependencies on particular .d files,
# so that eg. they are regenerated if a libsonnet referenced by them changes.
# This follows the recommendations in https://www.gnu.org/software/make/manual/html_node/Automatic-Variables.html
# Because the dep graph may need to read the generated libsonnets, we need to do those first.
# Rebuilding all the dependencies if any of the generated libsonnet change isn't ideal,
# but should be fine.
%.d: %.jsonnet $(GENERATE_LIBSONNETS)
	# The initial output is of form %.jsonnet: DEP DEP ...
	# We want %.yaml %.d: DEP DEP ...
	set -o pipefail
	jsonnet_dep_graph --jpath . "$<" |
		awk -F ': ' '{
			base = substr($$1, 0, length($$1) - 8); # strip .jsonnet
			printf "%s.yaml %s.d: %s\n", base, base, $$2
		}' > $@
include $(DEPS)

$(YAMLS): %.yaml: %.jsonnet manifests.jsonnet
	jsonnet --jpath . --yaml-stream manifests.jsonnet --tla-str 'path=$<' --tla-code 'value=import "$<"' > "$@"

.PHONY: clean
clean:
	rm -f manifests.yaml $(YAMLS) $(DEPS)
