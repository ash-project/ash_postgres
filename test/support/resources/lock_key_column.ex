# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.LockKeyColumn do
  @moduledoc false
  # A column for each way an index can make it a key, or not, for the row lock an update
  # takes through a subquery. See `test/update_lock_key_columns_test.exs`.
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "lock_key_columns"
    repo AshPostgres.TestRepo

    identity_wheres_to_sql(unique_nickname: "(nickname IS NOT NULL)")

    custom_indexes do
      index [{:asc, :shop_id}, {:desc, :sku}], unique: true
      index ["barcode"], unique: true
      index [{:desc, "serial"}], unique: true
      index [:tag], unique: true
      index ["lower(label)"], unique: true, name: "lock_key_columns_lower_label_index"
      index [:alias_name], unique: true, where: "alias_name IS NOT NULL"
      index [{:desc, :rank}], unique: false
    end
  end

  multitenancy do
    strategy(:attribute)
    attribute(:org_id)
    global?(true)
  end

  identities do
    identity(:unique_handle, [:handle])
    identity(:unique_nickname, [:nickname], where: expr(not is_nil(nickname)))
  end

  attributes do
    uuid_primary_key(:id, writable?: true)
    attribute(:org_id, :uuid, public?: true)
    attribute(:stock, :integer, public?: true)
    attribute(:rank, :integer, public?: true)
    attribute(:shop_id, :uuid, public?: true)
    attribute(:code, :string, public?: true, source: :sku)
    attribute(:barcode, :string, public?: true)
    attribute(:serial, :string, public?: true)
    # `tag` is stored in `tag_text`, and the unique index on the `tag` column is `tag_code`'s.
    attribute(:tag, :string, public?: true, source: :tag_text)
    attribute(:tag_code, :string, public?: true, source: :tag)
    attribute(:label, :string, public?: true)
    attribute(:alias_name, :string, public?: true)
    attribute(:handle, :string, public?: true)
    attribute(:nickname, :string, public?: true)
  end

  actions do
    default_accept(:*)
    defaults([:create, :read, :update, :destroy])
  end
end
