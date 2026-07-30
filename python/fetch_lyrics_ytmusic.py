#!/usr/bin/env python3
"""
Fetch lyrics from YouTube Music (ytmusicapi, no API key required).
Usage: python3 fetch_lyrics_ytmusic.py "artist name" "track title"
Returns JSON with plain lyrics and, when available, timestamped LRC.

Used as a fallback in get_lyrics.php when LRClib.net is unreachable and the
track has no embedded lyrics. YouTube Music serves both plain and time-synced
lyrics for a large catalogue and stays reachable when other providers are down.
"""
import sys
import json


def _ms_to_lrc_tag(ms):
    """Convert a millisecond offset to an LRC timestamp tag [mm:ss.cc]."""
    try:
        total_cs = int(round(int(ms) / 10.0))  # centiseconds
    except (TypeError, ValueError):
        total_cs = 0
    if total_cs < 0:
        total_cs = 0
    minutes = total_cs // 6000
    seconds = (total_cs % 6000) // 100
    centis = total_cs % 100
    return f"[{minutes:02d}:{seconds:02d}.{centis:02d}]"


def _line_field(line, key):
    """LyricLine may be an object with attributes or a plain dict."""
    if isinstance(line, dict):
        return line.get(key)
    return getattr(line, key, None)


def main():
    if len(sys.argv) < 3:
        print(json.dumps({"success": False, "error": "Usage: fetch_lyrics_ytmusic.py 'artist' 'title'"}))
        sys.exit(1)

    artist = sys.argv[1]
    title = sys.argv[2]

    try:
        from ytmusicapi import YTMusic
        yt = YTMusic()

        results = yt.search(f"{artist} {title}", filter="songs") or []
        if not results:
            print(json.dumps({"success": False, "error": "No tracks found"}))
            sys.exit(0)

        artist_lower = artist.lower().strip()
        title_lower = title.lower().strip()

        # Score each candidate; prefer exact artist + title matches.
        best_score = -1
        best = None
        for item in results:
            if not item.get("videoId"):
                continue
            item_title = (item.get("title") or "").lower()
            item_artists = " ".join(
                (a.get("name") or "") for a in (item.get("artists") or [])
            ).lower()

            score = 0
            if item_artists == artist_lower:
                score += 100
            elif artist_lower and artist_lower in item_artists:
                score += 50
            elif item_artists and item_artists in artist_lower:
                score += 30

            if item_title == title_lower:
                score += 50
            elif title_lower and title_lower in item_title:
                score += 25

            for junk in ("cover", "karaoke", "tribute", "instrumental"):
                if junk in item_title and junk not in title_lower:
                    score -= 20
            if "live" in item_title and "live" not in title_lower:
                score -= 10

            if score > best_score:
                best_score = score
                best = item

        if not best:
            best = results[0]

        video_id = best.get("videoId")
        if not video_id:
            print(json.dumps({"success": False, "error": "No video id"}))
            sys.exit(0)

        watch = yt.get_watch_playlist(video_id)
        browse_id = (watch or {}).get("lyrics")
        if not browse_id:
            print(json.dumps({"success": False, "error": "No lyrics available"}))
            sys.exit(0)

        synced_lrc = ""
        plain = ""
        source = ""

        # First try timestamped lyrics so clients can highlight the current line.
        try:
            timed = yt.get_lyrics(browse_id, timestamps=True)
        except Exception:
            timed = None

        timed_lines = (timed or {}).get("lyrics") if isinstance(timed, dict) else None
        if isinstance(timed_lines, list) and timed_lines and not isinstance(timed_lines, str):
            lrc_lines = []
            plain_lines = []
            for line in timed_lines:
                text = _line_field(line, "text")
                start = _line_field(line, "start_time")
                if text is None:
                    continue
                text = str(text)
                if start is not None:
                    lrc_lines.append(f"{_ms_to_lrc_tag(start)}{text}")
                plain_lines.append(text)
            synced_lrc = "\n".join(lrc_lines).strip()
            plain = "\n".join(plain_lines).strip()
            if isinstance(timed, dict):
                source = timed.get("source") or ""

        # Fall back to plain lyrics if no usable timestamps came back.
        if not plain:
            plain_res = yt.get_lyrics(browse_id, timestamps=False)
            if isinstance(plain_res, dict):
                plain = (plain_res.get("lyrics") or "").strip()
                source = plain_res.get("source") or source
            elif isinstance(plain_res, str):
                plain = plain_res.strip()

        if not plain and not synced_lrc:
            print(json.dumps({"success": False, "error": "Empty lyrics"}))
            sys.exit(0)

        out = {
            "success": True,
            "lyrics": plain,
            "source": "ytmusic",
            "matched_title": best.get("title", ""),
            "matched_artist": ", ".join(
                (a.get("name") or "") for a in (best.get("artists") or [])
            ),
        }
        if synced_lrc:
            out["syncedLyrics"] = synced_lrc
        if source:
            out["provider"] = source
        print(json.dumps(out))

    except ImportError:
        print(json.dumps({"success": False, "error": "ytmusicapi not installed"}))
        sys.exit(1)
    except Exception as e:
        print(json.dumps({"success": False, "error": str(e)}))
        sys.exit(1)


if __name__ == "__main__":
    main()
