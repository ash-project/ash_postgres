alias AshPostgres.Test.{Api, Post}

ten_rows =
  1..10
  |> Enum.map(fn i ->
    %{
      title: "Title: #{i}"
    }
  end)

thousand_rows =
  1..1000
  |> Enum.map(fn i ->
    %{
      title: "Title: #{i}"
    }
  end)

hundred_thousand_rows =
  1..1000
  |> Enum.map(fn i ->
    %{
      title: "Title: #{i}"
    }
  end)

Api.bulk_create(ten_rows, Post, :create,
  batch_size: 10,
  max_concurrency: 0
)

AshPostgres.TestRepo.insert_all(Post, ten_rows)

Benchee.run(
  %{
    "ash sync": fn input ->
      %{error_count: 0} = Api.bulk_create(input, Post, :create,
        batch_size: 200,
        transaction: false
      )
    end,
    "ecto sync": fn input ->
      input
      |> Stream.chunk_every(200)
      |> Enum.each(fn batch ->
        AshPostgres.TestRepo.insert_all(Post, batch)
      end)
    end,
    "ash async": fn input ->
      %{error_count: 0} = Api.bulk_create(input, Post, :create,
        batch_size: 200,
        max_concurrency: 8,
        transaction: false
      )
    end,
    "ecto async": fn input ->
      input
      |> Stream.chunk_every(200)
      |> Task.async_stream(fn batch ->
        AshPostgres.TestRepo.insert_all(Post, batch)
      end, max_concurrency: 8, timeout: :infinity)
      |> Stream.run()
    end
  },
  inputs: %{
    "10 rows" => ten_rows,
    "1000 rows" => thousand_rows,
    "100000 rows" => hundred_thousand_rows
  }
)
