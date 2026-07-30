defmodule Faviconic do
  @moduledoc "./README.md" |> File.stream!() |> Enum.drop(1) |> Enum.join()
  import Untangle
  @user_agent "Mozilla/5.0 (Windows NT 6.1; Win64; x64; rv:47.0) Gecko/20100101 Firefox/47.0"
  @timeout_ms 3_000


  @doc """
  Fetch the binary contents of a favicon file for a domain 
  """
  def fetch(url) do
    get(url, true)
  end

  @doc """
  Get the URL of a favicon file for a domain (or fetch its binary contents by setting the `fetch_image?` param to true)

  Tries to obtain a favicon for the site.
  It first tries the url/favicon.ico (for speed).
  Then it uses the some third-party favicon services to try retrieving a favicon.
  Lastly it tries to find a path to an icon URL in the HTML page.

  If you do not pass `http://` or `https://`, `http://` is assumed.
  """
  def get(url, fetch_image? \\ false)

  def get(url, fetch_image?) when is_binary(url) do
    {absolute_url, host} = process_uri(url)

    with {:ok, image} <-
           fetch_default(absolute_url, fetch_image?) ||
             fetch_from_third_parties(host, fetch_image?) ||
             fetch_from_html(absolute_url, fetch_image?) do
      {:ok, image}
    else
      e ->
        error(e, "failed to find favicon for #{url}")
    end
  end

  def get(url, _), do: error(url, "Tried to fetch an invalid URL")

  @doc """
  Find a favicon URL (or fetch its binary contents by setting the `fetch_image?` param to true) given HTML page contents. *Use this if you already fetched the HTML page to avoid doing it twice.*

  Parses the HTML and tries to find a favicon in it (if provided), and otherwise tries other techniques.
  """
  def find(url, html_body, fetch_image? \\ false) do
    with {:ok, image_or_url} <- parse(url, html_body, fetch_image?) || get(url, fetch_image?) do
      {:ok, image_or_url}
    else
      _ ->
        {:error, "failed to find favicon"}
    end
  end

  @doc """
  Parses an HTML page and tries to find a favicon URL in it
  """
  def parse(url, html_body, fetch_image? \\ false) do
    with icon_path when is_binary(icon_path) <- get_icon_path_html(html_body) do
      get_absolute_image_path(url, icon_path)
      |> check_url(fetch_image?)
    else
      _ -> nil
    end
  end

  defp fetch_default(url, fetch_image? \\ true) do
    URI.parse(url)
    |> URI.merge("/favicon.ico")
    |> to_string()
    |> check_url(fetch_image?)
  end

  defp fetch_from_html(url, fetch_image? \\ true) do
    with {:ok, body} <- get_html_from_url(url) do
      parse(url, body, fetch_image?)
    else
      e ->
        debug(e)
        nil
    end
  end

  defp fetch_from_third_parties(url, fetch_image? \\ true) do
    fetch_from_duck_duck_go(url, fetch_image?) ||
      fetch_from_google(url, fetch_image?)
  end

  defp fetch_from_duck_duck_go(domain, fetch_image? \\ true) do
    check_url("https://icons.duckduckgo.com/ip3/#{domain}.ico", fetch_image?)
  end

  defp fetch_from_google(domain, fetch_image? \\ true) do
    check_url("https://www.google.com/s2/favicons?domain=#{domain}", fetch_image?)
  end

  defp get_icon_path_html(body) do
    case Floki.find(body, "link[rel=icon]") do
      [] ->
        case Floki.find(body, "link[rel*=icon]") do
          [] ->
            nil

          links ->
            first_icon_from_links(links)
        end

      links ->
        first_icon_from_links(links)
    end
  end

  defp first_icon_from_links(links) do
    Floki.attribute(links, "href")
    |> List.first()

    # |> IO.inspect(label: "first_icon_from_links")
  end

  defp check_url(url, _fetch_image? = true), do: get_image_from_url(url)
  defp check_url(url, _), do: get_valid_image_url(url)

  defp get_image_from_url(url) do
    case fetch_url(url) do
      {:ok, %{body: ""}} ->
        debug("body was empty")
        nil

      {:ok, %{body: body, headers: headers_list}} ->
        case Enum.into(headers_list, %{}) do
          %{"content-encoding" => _encoding} ->
            debug(headers_list, "found unexpected header (content-encoding)")
            nil

          %{"content-type" => ["image" <> _]} ->
            {:ok, body}

          %{"content-type" => "image" <> _} ->
            {:ok, body}

          _ ->
            debug(headers_list, "did not find expected header (content-type: image)")
            nil
        end

      nil ->
        nil
      
      other ->
        debug(other, url)
        nil
    end
  end

  defp get_valid_image_url(url) do
    case get_headers(url) do
      {:ok, %{headers: headers_list}} ->
        # IO.inspect(headers_list)
        case Enum.into(headers_list, %{}) do
          %{"content-type" => ["image" <> _]} ->
            {:ok, url}

          %{"content-type" => "image" <> _} ->
            {:ok, url}

          _ ->
            debug(headers_list, "did not find expected header (content-type: image)")
            nil
        end

      # |> IO.inspect(label: "get_valid_image_url")

      other ->
        debug(other, url)
        nil
    end
  end

  defp get_html_from_url(url) do
    case fetch_url(url) do
      {:ok, %{body: body, headers: headers_list}} ->
        case Enum.into(headers_list, %{}) do
          %{"content-type" => "text/html" <> _} -> {:ok, body}
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp fetch_url(url) do
    if full_uri?(url) do
      case {_code, response} =
             Req.get(
               url,
               user_agent: @user_agent,
               receive_timeout: @timeout_ms,
               max_redirects: 3,
               retry: false,
               # for mocks during testing
               adapter: ProcessTree.get(:req_adapter) || (&Req.Steps.run_finch/1)
             ) do
        {:ok, %{status: 200}} -> {:ok, response}
        other -> 
          debug(other, url)
          nil
      end
    end
  rescue
    e in RuntimeError ->
      error(e)
      nil
  end

  defp get_headers(url) do
    if full_uri?(url) do
      case {_code, response} =
             Req.head(
               url,
               user_agent: @user_agent,
               receive_timeout: @timeout_ms,
               max_redirects: 3,
               raw: true
             ) do
        {:ok, %{status: 200}} -> {:ok, response}
        _ -> nil
      end
    end
  end

  # with no base url to resolve against, the icon path is all we have (`URI.parse/1` raises a FunctionClauseError on a non-binary, and callers do pass nil — eg. Unfurl for a hostless url)
  defp get_absolute_image_path(url, icon_path) when not is_binary(url), do: icon_path

  defp get_absolute_image_path(url, icon_path) do
    case URI.parse(url) do
      %{scheme: nil} ->
        icon_path

      %{host: nil} ->
        icon_path

      _ ->
        case URI.parse(icon_path) do
          %{scheme: nil} -> URI.merge(url, icon_path) |> to_string()
          %{host: nil} -> URI.merge(url, icon_path) |> to_string()
          _ -> icon_path
        end
    end
  end

  defp process_uri(url) when is_binary(url) do
    case URI.parse(url) do
      %{scheme: nil, host: nil, path: path_as_host} when is_binary(path_as_host) -> {"http://#{path_as_host}", path_as_host}
      %{host: host} -> {url, host}
    end
  end

  defp full_uri?(url) do
    case URI.parse(url) do
      %{scheme: nil} -> false
      %{host: nil} -> false
      _ -> true
    end
  end
end
