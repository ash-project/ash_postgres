# AshPostgres

![Elixir CI](https://github.com/ash-project/ash_postgres/workflows/Elixir%20CI/badge.svg)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Coverage Status](https://coveralls.io/repos/github/ash-project/ash_postgres/badge.svg?branch=master)](https://coveralls.io/github/ash-project/ash_postgres?branch=master)
[![Hex version badge](https://img.shields.io/hexpm/v/ash.svg)](https://hex.pm/packages/ash_postgres)

# TODO

## Configuration

- Need to figure out how to only fetch config one time in the configuration of the repo.
  Right now, we are calling the `installed_extensions()` function in both `supervisor` and
  `runtime` but that could mean checking the system environment variables every time (is that bad?)
- Figure out heuristics for when to left join/right join (alternatively, make it configurable via the query language)
  For instance, if a relationship has a non-nil predicate applied to it in all `ors` or a single `and` then we should
  be able to inner join.
  I have learned from experience that no single approach here
  will be a one-size-fits-all. We need to either use complexity metrics,
  hints from the interface, or some other heuristic to do our best to
  make queries perform well. For now, I'm just choosing the most naive approach
  possible: left join to relationships that appear in `or` conditions, inner
  join to conditions that are constant the query (dont do this yet, but it will be a good optimization)
  Realistically, in my experience, joins don't actually scale very well, especially
  when calculated attributes are added.
