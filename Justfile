root := justfile_directory()

export TYPST_ROOT := root

[private]
default:
  @just --list --unsorted

# generate manual
doc:
  typst compile docs/manual.typ docs/manual.pdf
  typst compile docs/thumbnail.typ thumbnail-light.svg
  typst compile --input theme=dark docs/thumbnail.typ thumbnail-dark.svg

# run test suite
test *args:
  tt run --no-fail-fast {{ args }}

# run only the assertion tests (the ones with nothing to eyeball)
check:
  tt run --no-fail-fast -e 'regex:"-ops$" | exact:core-ops | exact:api-conformance'

# update test cases
update *args:
  tt update {{ args }}

# print the package name and version packaging will use
version:
  @grep -E '^(name|version) *=' typst.toml

# package the library into the specified destination folder
# (name and version are read from typst.toml by scripts/setup)
package target:
  ./scripts/package "{{target}}"

# install the library with the "@local" prefix (as @local/starling/<version>)
install: (package "@local")

# install the library with the "@preview" prefix (for pre-release testing)
install-preview: (package "@preview")

[private]
remove target:
  ./scripts/uninstall "{{target}}"

# uninstalls the library from the "@local" prefix
uninstall: (remove "@local")

# uninstalls the library from the "@preview" prefix (for pre-release testing)
uninstall-preview: (remove "@preview")

# run ci suite
ci: test doc
