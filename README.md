# AshPostgres

[![Elixir CI](https://github.com/ash-project/ash_postgres/workflows/Elixir%20CI/badge.svg)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Coverage Status](https://coveralls.io/repos/github/ash-project/ash_postgres/badge.svg?branch=master)](https://coveralls.io/github/ash-project/ash_postgres?branch=master)
[![Hex version badge](https://img.shields.io/hexpm/v/ash.svg)](https://hex.pm/packages/ash_postgres)

# TODO

## Configuration

- Need to figure out how to only fetch config one time in the configuration of the repo.
  Right now, we are calling the `installed_extensions()` function in both `supervisor` and
  `runtime` but that could mean checking the system environment variables every time (is that bad?)
