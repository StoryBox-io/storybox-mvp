defmodule Storybox.Storage do
  @bucket Application.compile_env(:storybox, :minio_bucket, "storybox-pieces")

  def uri_for_sequence(story_id, piece_id, version_number) do
    "storybox://stories/#{story_id}/sequences/#{piece_id}/v#{version_number}.fountain"
  end

  def uri_for_scene(story_id, piece_id, version_number) do
    "storybox://stories/#{story_id}/scenes/#{piece_id}/v#{version_number}.fountain"
  end

  def uri_for_synopsis(story_id, version_number) do
    "storybox://stories/#{story_id}/synopsis/v#{version_number}.fountain"
  end

  def uri_to_path("storybox://" <> path), do: path

  def put_content(uri, content) do
    path = uri_to_path(uri)

    case ExAws.S3.put_object(@bucket, path, content) |> ExAws.request() do
      {:ok, _} -> {:ok, uri}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_content(uri) do
    path = uri_to_path(uri)

    case ExAws.S3.get_object(@bucket, path) |> ExAws.request() do
      {:ok, %{body: body}} -> {:ok, body}
      {:error, reason} -> {:error, reason}
    end
  end
end
