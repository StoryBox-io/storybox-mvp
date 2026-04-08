bucket = System.get_env("MINIO_BUCKET", "storybox-pieces")

case ExAws.S3.head_bucket(bucket) |> ExAws.request() do
  {:ok, _} ->
    IO.puts("MinIO bucket '#{bucket}' already exists.")

  {:error, {:http_error, 404, _}} ->
    IO.puts("Creating MinIO bucket '#{bucket}'...")

    ExAws.S3.put_bucket(bucket, "us-east-1")
    |> ExAws.request!()

    IO.puts("MinIO bucket '#{bucket}' created.")

  {:error, reason} ->
    IO.warn("MinIO bucket check failed: #{inspect(reason)} — skipping.")
end
