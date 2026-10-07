# Vendored dependencies

These ordinary source files were copied from the provided local vendor mirrors.
No installation, package manager, submodule, or network access is needed to build.

- OpenZeppelin Contracts: mirror package version **5.7.0**. Only ERC20.sol and
  its four transitive imports are included, unchanged, along with the MIT license.
  ERC20.sol's upstream header identifies its last update as v5.5.0.
- forge-std: mirror package version **1.16.2**. The complete `src/` directory is
  included unchanged, with its MIT and Apache-2.0 licenses. Used by tests and the
  local deployment script only.

The source files in this directory, rather than an external branch or tag, define
the dependency versions used by this project.
