alias AshPostgres.Test.{Domain, Post}

AshPostgres.TestRepo.start_link()

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

# do them both once to warm things up
Ash.bulk_create(ten_rows, Post, :create,
  batch_size: 10,
  max_concurrency: 2
)

# do them both once to warm things up
AshPostgres.TestRepo.insert_all(Post, ten_rows)

max_concurrency = 16
batch_size = 200

Benchee.run(
  %{
    "ash sync": fn input ->
      %{error_count: 0} = Ash.bulk_create(input, Post, :create,
        batch_size: batch_size,
        transaction: false
      )
    end,
    "ash sync assuming casted": fn input ->
      %{error_count: 0} = Ash.bulk_create(input, Post, :create,
        batch_size: batch_size,
        transaction: false,
        assume_casted?: true
      )
    end,
    "ecto sync": fn input ->
      input
      |> Stream.chunk_every(batch_size)
      |> Enum.each(fn batch ->
        AshPostgres.TestRepo.insert_all(Post, batch)
      end)
    end,
    "ash async stream": fn input ->
      input
      |> Stream.chunk_every(batch_size)
      |> Task.async_stream(fn batch ->
        %{error_count: 0} =  Ash.bulk_create(batch, Post, :create,
          transaction: false
        )
      end, max_concurrency: max_concurrency, timeout: :infinity)
      |> Stream.run()
    end,
    "ash async stream assuming casted": fn input ->
      input
      |> Stream.chunk_every(batch_size)
      |> Task.async_stream(fn batch ->
        %{error_count: 0} =  Ash.bulk_create(batch, Post, :create,
          transaction: false,
          assume_casted?: true
        )
      end, max_concurrency: max_concurrency, timeout: :infinity)
      |> Stream.run()
    end,
    "ash using own async option": fn input ->
      %{error_count: 0} = Ash.bulk_create(input, Post, :create,
        transaction: false,
        max_concurrency: max_concurrency,
        batch_size: batch_size
      )
    end,
    "ash using own async option assuming casted": fn input ->
      %{error_count: 0} = Ash.bulk_create(input, Post, :create,
        transaction: false,
        assume_casted?: true,
        max_concurrency: max_concurrency,
        batch_size: batch_size
      )
    end,
    "ecto async stream": fn input ->
      input
      |> Stream.chunk_every(batch_size)
      |> Task.async_stream(fn batch ->
        AshPostgres.TestRepo.insert_all(Post, batch)
      end, max_concurrency: max_concurrency, timeout: :infinity)
      |> Stream.run()
    end
  },
  after_scenario: fn _ ->
    AshPostgres.TestRepo.query!("TRUNCATE posts CASCADE")
  end,
  inputs: %{
    "10 rows" => ten_rows,
    "1000 rows" => thousand_rows
  }
)
