# AshPostgres

**TODO: Add description**


## TODO LIST (in no order)
* Determine if we want to own the dependency of ecto. If not, somehow have a compatibility determination step at compile time
* Add the ability for a data_layer to express what it can/can't do, so the engine can adjust accordingly. I don't want runtime failures as a result of this, I want Ash/frontends to say what they need from the data layer at compile time, so DSL elements that would result in failure behavior are detected at compile time.
* support `through` relationships, here and in ash