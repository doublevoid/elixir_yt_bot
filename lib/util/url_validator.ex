defmodule UrlValidator do
  @url_regex ~r/^https?:\/\/([a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,5}|(2(5[0-5]|[0-4][0-9])|[0-1]?[0-9]{1,2})(\.(2(5[0-5]|[0-4][0-9])|[0-1]?[0-9]{1,2})){3})(:[0-9]{1,5})?(\/.*)?$/ix

  def valid?(url) when is_binary(url) do
    url =~ @url_regex
  end
end
