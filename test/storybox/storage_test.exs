defmodule Storybox.StorageTest do
  use ExUnit.Case, async: true

  alias Storybox.Storage

  @story_id "11111111-1111-1111-1111-111111111111"
  @piece_id "22222222-2222-2222-2222-222222222222"

  describe "uri_for_sequence/3" do
    test "builds correct URI" do
      assert Storage.uri_for_sequence(@story_id, @piece_id, 1) ==
               "storybox://stories/#{@story_id}/sequences/#{@piece_id}/v1.fountain"
    end
  end

  describe "uri_for_scene/3" do
    test "builds correct URI" do
      assert Storage.uri_for_scene(@story_id, @piece_id, 2) ==
               "storybox://stories/#{@story_id}/scenes/#{@piece_id}/v2.fountain"
    end
  end

  describe "uri_for_synopsis/2" do
    test "builds correct URI" do
      assert Storage.uri_for_synopsis(@story_id, 3) ==
               "storybox://stories/#{@story_id}/synopsis/v3.fountain"
    end
  end

  describe "uri_to_path/1" do
    test "strips storybox:// scheme" do
      uri = "storybox://stories/#{@story_id}/sequences/#{@piece_id}/v1.fountain"
      assert Storage.uri_to_path(uri) == "stories/#{@story_id}/sequences/#{@piece_id}/v1.fountain"
    end
  end

  describe "put_content/2 and get_content/1" do
    test "round-trips content through MinIO" do
      uri = Storage.uri_for_sequence(@story_id, @piece_id, 99)
      content = "INT. COFFEE SHOP - DAY\n\nA detective stares at a blank page."

      assert {:ok, ^uri} = Storage.put_content(uri, content)
      assert {:ok, ^content} = Storage.get_content(uri)
    end
  end
end
