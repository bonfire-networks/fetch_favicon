defmodule FaviconicTest do
  use ExUnit.Case

  import Mock

  test "accepts an HTML favicon that rejects HEAD but allows GET" do
    test_pid = self()
    favicon_url = "https://example.com/signed-icon.svg"
    html = "<html><head><link rel=\"icon\" href=\"#{favicon_url}\"></head></html>"
    {:ok, document} = Floki.parse_document(html)

    with_mock Req,
      head: fn ^favicon_url, _opts ->
        send(test_pid, :head_requested)
        {:ok, %{status: 403, headers: []}}
      end,
      get: fn ^favicon_url, opts ->
        send(test_pid, {:get_requested, opts})
        {:ok, %{status: 200, headers: [{"content-type", "image/svg+xml"}], body: ""}}
      end do
      result = Faviconic.parse("https://example.com", document)

      assert_received :head_requested
      assert_received {:get_requested, opts}
      assert is_function(opts[:into], 2)
      assert {:ok, ^favicon_url} = result
    end
  end

  test "invalid html returned" do
    with_mock Req, get: fn url, _ -> {:ok, ""} end do
      assert {:error, _} = Faviconic.fetch("reddit.com")
    end
  end

  test "error returned" do
    with_mock Req, get: fn url, _ -> {:error, "error message"} end do
      assert {:error, _} = Faviconic.fetch("reddit.com")
    end
  end

  @tag :skip
  test "first call fails" do
    base_site_response = %{
      body: "<html><link href=\"/custom/reddit/ico/path/icon.ico\" rel=\"shortcut icon\"></html>",
      headers: [
        {"content-type", "text/html; charset=UTF-8"},
        {"content-length", "non zero"}
      ],
      # request_url: "",
      status: 200
    }

    image_response = %{
      body: "some valid image",
      headers: [
        {"content-type", "image/x-icon"},
        {"content-length", "non zero"}
      ],
      # request_url: "",
      status: 200
    }

    with_mock Req,
      get: fn url, _ ->
        case url do
          "http://reddit.com/favicon.ico" ->
            {:error, "404"}

          "http://reddit.com" ->
            {:ok, base_site_response}

          "http://reddit.com/custom/reddit/ico/path/icon.ico" ->
            {:ok, image_response}

          other ->
            # IO.inspect(other)
            {:error, "404"}
        end
      end do
      # FIXME
      assert {:ok, _} = Faviconic.fetch("reddit.com")
    end
  end

  test "trailing slash" do
    response = %{
      body: "<html></html>",
      headers: [
        {"content-type", "image/x-icon"},
        {"content-length", "non zero"}
      ],
      # request_url: "",
      status: 200
    }

    with_mock Req,
      get: fn url, _ ->
        case url do
          "http://reddit.com/favicon.ico" ->
            {:ok, response}

          _ ->
            nil
        end
      end do
      assert {:ok, _} = Faviconic.fetch("reddit.com/")
    end
  end

  test "not image" do
    response = %{
      body: "<html></html>",
      headers: [
        {"content-type", "text/html; charset=utf-8"},
        {"content-length", "non zero"}
      ],
      # request_url: "",
      status: 200
    }

    with_mock Req,
      get: fn url, _ ->
        case url do
          "http://reddit.com/favicon.ico" ->
            {:ok, response}

          _ ->
            {:error, "error message"}
        end
      end do
      assert {:error, _} = Faviconic.fetch("reddit.com/")
    end
  end

  test "has encoding" do
    response = %{
      body: "<html></html>",
      headers: [
        {"content-type", "text/html; charset=utf-8"},
        {"content-length", "non zero"},
        {"content-encoding", "gzip"}
      ],
      # request_url: "",
      status: 200
    }

    with_mock Req,
      get: fn url, _ ->
        case url do
          "http://reddit.com/favicon.ico" ->
            {:ok, response}

          _ ->
            {:error, "error message"}
        end
      end do
      assert {:error, _} = Faviconic.fetch("reddit.com/")
    end
  end

  test "content length 0" do
    response = %{
      body: "",
      headers: [
        {"content-type", "image/png"},
        {"content-length", "0"}
      ],
      # request_url: "",
      status: 200
    }

    with_mock Req,
      get: fn url, _ ->
        case url do
          "http://reddit.com/favicon.ico" ->
            {:ok, response}

          _ ->
            {:error, "error message"}
        end
      end do
      assert {:error, _} = Faviconic.fetch("reddit.com/")
    end
  end

  test "invalid image" do
    response = %{
      body: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAAGXR
      FWHRTb2Z0d2FyZQBBZG9iZSBJbWFnZVJlYWR5ccllPAAAA99JREFUeNrsG4t1ozDMzQSM4A2ODUo9nKB
      ucN2hugtIJ6E1AboLcBiQTkJsANiAb9OCd/OpzMWBJBl5TvaeXPiiyJetry0J8wW3wefawefN4II=\n",
      headers: [
        {"content-type", "image/png"}
      ],
      # request_url: "",
      status: 200
    }

    with_mock Req,
      get: fn url, _ ->
        case url do
          "http://reddit.com/favicon.ico" ->
            {:error, "error message"}

          "http://reddit.com/" ->
            {:ok, response}

          _ ->
            {:error, "error message"}
        end
      end do
      assert {:error, _} = Faviconic.fetch("reddit.com/")
    end
  end

  test "www" do
    response = %{
      body: "<html></html>",
      headers: [{"content-type", "image/png"}, {"content-length", "non zero"}],
      # request_url: "",
      status: 200
    }

    with_mock Req,
      get: fn url, _ ->
        case url do
          "http://www.reddit.com/favicon.ico" ->
            {:ok, response}

          _ ->
            nil
        end
      end do
      assert {:ok, _} = Faviconic.fetch("www.reddit.com/")
    end
  end

  test "first and second calls fail" do
    response = %{
      body: "image",
      headers: [
        {"content-type", "image/x-icon"},
        {"content-length", "non zero"}
      ],
      # request_url: "",
      status: 200
    }

    with_mock Req,
      get: fn url, _ ->
        case url do
          "http://reddit.com/favicon.ico" ->
            {:error, "error messsage"}

          "http://reddit.com" ->
            {:error, "error messsage"}

          "https://www.google.com/s2/favicons?domain=reddit.com" ->
            {:ok, response}

          _ ->
            {:error, "error messsage"}
        end
      end do
      assert {:ok, _} = Faviconic.fetch("reddit.com")
    end
  end
end
