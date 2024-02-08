
.DELETE_ON_ERROR:
.ONESHELL:
SHELL = /bin/bash
.SHELLFLAGS = -euc

JSONNETS := $(shell find -type f -name '*.jsonnet' -not -name manifests.jsonnet)
YAMLS := $(JSONNETS:.jsonnet=.yaml)
DEPS := $(JSONNETS:.jsonnet=.d)

# Full yaml file, which is simply all the yamls concatenated.
# This is a relatively trivial transform, but is useful to exist as a file
# for diff purposes.
manifests.yaml: $(YAMLS)
	cat $^ > "$@"

# Produce a makefile that lists dependencies of each jsonnet file, and include them.
# Notably, the generated dependencies may also include further dependencies on particular .d files,
# so that eg. they are regenerated if a libsonnet referenced by them changes.
# This follows the recommendations in https://www.gnu.org/software/make/manual/html_node/Automatic-Variables.html
%.d: %.jsonnet
	# The initial output is of form %.jsonnet: DEP DEP ...
	# We want %.yaml %.d: DEP DEP ...
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
