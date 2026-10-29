#!/usr/bin/env python3
"""Tests recommend.py's matching of Trakt recommendations to the Jellyfin library (no network). Usage: python3 test_recommend.py"""
import recommend


def main():
    assert recommend.interleave([1, 2, 3], ["a"]) == [1, "a", 2, 3]
    library = [
        {"Id": "m1", "Type": "Movie", "ProviderIds": {"Tmdb": "120"}, "UserData": {}},
        {"Id": "s1", "Type": "Series", "ProviderIds": {"Tvdb": "372264", "Imdb": "tt5875444"}, "UserData": {}},
        {"Id": "done", "Type": "Movie", "ProviderIds": {"Imdb": "tt1"}, "UserData": {"Played": True}},
        {"Id": "started", "Type": "Movie", "ProviderIds": {"Tmdb": "7"}, "UserData": {"PlaybackPositionTicks": 5}},
    ]
    recs = [
        {"title": "Slow Horses", "ids": {"tvdb": 372264, "imdb": "tt5875444"}},
        {"title": "Not on the server", "ids": {"tmdb": 999}},
        {"title": "Fellowship", "ids": {"tmdb": 120, "imdb": "tt0120737"}},
        {"title": "Finished", "ids": {"imdb": "tt1"}},
        {"title": "Started", "ids": {"tmdb": 7}},
        {"title": "Slow Horses again", "ids": {"imdb": "tt5875444"}},
    ]
    assert [i["Id"] for i in recommend.matches(recs, library)] == ["s1", "m1"]
    recs[1]["_kind"] = "movies"
    assert recommend.missing(recs, library) == [{"type": "movie", "tmdb": 999, "title": "Not on the server", "year": None}]
    print("ok")


if __name__ == "__main__":
    main()
