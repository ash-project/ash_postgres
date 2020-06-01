# AshPostgres
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

# TODO

## Configuration

- Need to figure out how to only fetch config one time in the configuration of the repo.
  Right now, we are calling the `installed_extensions()` function in both `supervisor` and
  `runtime` but that could mean checking the system environment variables every time (is that bad?)
