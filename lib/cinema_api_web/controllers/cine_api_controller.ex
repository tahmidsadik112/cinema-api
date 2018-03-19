defmodule CinemaApiWeb.CineApiController do
  use CinemaApiWeb, :controller

  def parse_month_string_to_int(month) do
    case month do
      "January" -> 1
      "February" -> 2
      "March" -> 3
      "April" -> 4
      "May" -> 5
      "June" -> 6
      "July" -> 7
      "August" -> 8
      "September" -> 9
      "October" -> 10
      "November" -> 11
      "December" -> 12
    end
  end

  def normalize_date_format(date) do
    d =
      date
      |> String.split(",")
      |> Enum.slice(1..-1)
      |> Enum.map(fn n -> String.trim(n) end)

    day = Enum.at(d, 0) |> String.split() |> Enum.at(1) |> String.to_integer()
    month = Enum.at(d, 0) |> String.split() |> Enum.at(0) |> parse_month_string_to_int
    year = Enum.at(d, 1) |> String.to_integer()

    %{
      :day => day,
      :month => month,
      :year => year
    }
  end

  def normalize_time_format(time) do
    t =
      time
      |> String.replace(~r/AM|PM/, "")
      |> String.trim()
      |> String.split(":")

    time_period =
      time
      |> String.split(~r/\d{2}:\d{2}/)
      |> Enum.at(1)

    hour =
      case time_period do
        "AM" -> Enum.at(t, 0) |> String.to_integer()
        "PM" -> Enum.at(t, 0) |> String.to_integer() |> Kernel.+(12)
      end

    minute = Enum.at(t, 1) |> String.to_integer()
    second = 0

    %{
      :hour => hour,
      :minute => minute,
      :second => second
    }
  end

  def normalize_movie_dates(movie_dates) do
    movie_dates
    |> Enum.map(fn date -> normalize_date_format(date) end)
  end

  def get_movie_times(parsed_html_body) do
    parsed_html_body
    |> Floki.find(".col-lg-8 .col-xs-12")
    |> Enum.map(fn n -> Floki.find(n, ".items-wrap") end)
    |> Enum.map(fn n ->
      Enum.map(n, fn x ->
        x
        |> Floki.find("li")
        |> Floki.text()
        |> String.trim()
        |> String.replace(" ", "")
        |> String.replace("\n", " ")
      end)
    end)
  end

  def get_movie_dates(parsed_html_body) do
    parsed_html_body
    |> Floki.find(".date-tx")
    |> Enum.map(fn n -> n |> Floki.find("strong") |> Floki.text() end)
  end

  def get_movie_names(parsed_html_body) do
    parsed_html_body
    |> Floki.find(".col-lg-8 .col-xs-12")
    |> Enum.map(fn block -> Floki.find(block, ".text-info") end)
    |> Enum.map(fn n -> Enum.map(n, fn x -> Floki.text(x) end) end)
    |> Enum.map(fn n ->
      Enum.map(n, fn x ->
        x |> String.trim()
        |> String.replace("\n", "")
      end)
    end)
  end

  def get_unique_movies(movie_list) do
    movie_list
    |> List.flatten()
    |> Enum.uniq()
  end

  def merge_movie_date_time(movie_dates, movie_times) do
    Enum.zip(normalize_movie_dates(movie_dates), movie_times)
    |> Enum.map(fn date_time_pair ->
      date = elem(date_time_pair, 0)

      Enum.map(elem(date_time_pair, 1), fn times ->
        String.split(times)
        |> Enum.map(fn time ->
          t = normalize_time_format(time)

          {:ok, show_time} =
            NaiveDateTime.new(date.year, date.month, date.day, t.hour, t.minute, t.second)

          show_time
        end)
      end)
    end)
  end

  def merge_movie_with_showtime(movie_names, showtimes) do
    for i <- 0..(Enum.count(movie_names) - 1),
        do:
          Enum.zip(Enum.at(movie_names, i), Enum.at(showtimes, i))
          |> Enum.into(%{})
  end

  def get_cineplex_movie_list() do
    url = "http://www.cineplexbd.com/cineplexbd/showtime"
    # url = "file:///Users/tahmid/Documents/cineplex.html"
    headers = []
    options = [timeout: 15000, recv_timeout: 15000]

    case HTTPoison.get(url, headers, options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        parsed_body = Floki.parse(body)
        movie_names = get_movie_names(parsed_body)
        movie_times = get_movie_times(parsed_body)
        movie_dates = get_movie_dates(parsed_body)
        showtimes = merge_movie_date_time(movie_dates, movie_times)
        movie_with_showtimes = merge_movie_with_showtime(movie_names, showtimes)
        {:ok, movie_with_showtimes}

      # movie_names_uniq = movie_names |> Enum.uniq()
      # movie_showtime_with_date = {:ok, [movie_names, movie_times, movie_dates]}

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        IO.puts("404 block")
        {:err, "Tough luck, 404, Chekc the url again"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        IO.puts(reason)
        {:err, "Something fucked up"}
    end
  end

  def index(conn, _params) do
    case get_cineplex_movie_list() do
      {:ok, movies} -> json(conn, %{movies: movies})
      {:err, msg} -> json(conn, %{err: msg})
    end
  end
end