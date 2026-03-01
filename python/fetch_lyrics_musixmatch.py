#!/usr/bin/env python3
"""
Fetch lyrics from Musixmatch API.
Usage: python3 fetch_lyrics_musixmatch.py "artist name" "track title"
Returns JSON with lyrics or error.
"""
import sys
import json

def main():
    if len(sys.argv) < 3:
        print(json.dumps({"success": False, "error": "Usage: fetch_lyrics_musixmatch.py 'artist' 'title'"}))
        sys.exit(1)

    artist = sys.argv[1]
    title = sys.argv[2]

    try:
        from musicxmatch_api import MusixMatchAPI
        api = MusixMatchAPI()

        # Search for the track
        search_query = f"{artist} {title}"
        results = api.search_tracks(search_query)

        if not results or "message" not in results:
            print(json.dumps({"success": False, "error": "No results from API"}))
            sys.exit(0)

        body = results.get("message", {}).get("body", {})
        track_list = body.get("track_list", [])

        if not track_list:
            print(json.dumps({"success": False, "error": "No tracks found"}))
            sys.exit(0)

        # Try to find the best matching track (prefer exact artist match)
        track = None
        artist_lower = artist.lower().strip()
        title_lower = title.lower().strip()

        # Score each track for relevance
        best_score = -1
        for item in track_list:
            t = item.get("track", {})
            track_artist = t.get("artist_name", "").lower()
            track_title = t.get("track_name", "").lower()

            score = 0

            # Exact artist match is best
            if track_artist == artist_lower:
                score += 100
            elif artist_lower in track_artist:
                score += 50
            elif track_artist in artist_lower:
                score += 30

            # Title match
            if track_title == title_lower:
                score += 50
            elif title_lower in track_title:
                score += 25

            # Penalize covers, karaoke, etc.
            if any(word in track_title for word in ['cover', 'karaoke', 'tribute', 'piano']):
                score -= 20
            if any(word in track_artist for word in ['cover', 'karaoke', 'tribute', 'piano']):
                score -= 20

            # Prefer non-live versions unless specifically asked
            if 'live' in track_title and 'live' not in title_lower:
                score -= 10

            if score > best_score:
                best_score = score
                track = t

        # Fallback to first result if no good match
        if not track:
            track = track_list[0].get("track", {})

        track_id = track.get("track_id")

        if not track_id:
            print(json.dumps({"success": False, "error": "No track ID found"}))
            sys.exit(0)

        # Get lyrics for this track
        lyrics_result = api.get_track_lyrics(track_id=track_id)

        if not lyrics_result or "message" not in lyrics_result:
            print(json.dumps({"success": False, "error": "Failed to get lyrics"}))
            sys.exit(0)

        lyrics_body = lyrics_result.get("message", {}).get("body", {})

        # Handle case where body is an empty list (API rate limit / captcha)
        if isinstance(lyrics_body, list):
            print(json.dumps({"success": False, "error": "API rate limited"}))
            sys.exit(0)

        lyrics_obj = lyrics_body.get("lyrics", {})
        lyrics_text = lyrics_obj.get("lyrics_body", "")

        if not lyrics_text:
            print(json.dumps({"success": False, "error": "No lyrics available"}))
            sys.exit(0)

        # Clean up the lyrics (remove the Musixmatch disclaimer at the end if present)
        lines = lyrics_text.split('\n')
        clean_lines = []
        for line in lines:
            if "******* This Lyrics is NOT for Commercial use *******" in line:
                break
            clean_lines.append(line)

        clean_lyrics = '\n'.join(clean_lines).strip()

        print(json.dumps({
            "success": True,
            "lyrics": clean_lyrics,
            "track_name": track.get("track_name", ""),
            "artist_name": track.get("artist_name", ""),
            "source": "musixmatch"
        }))

    except ImportError:
        print(json.dumps({"success": False, "error": "musicxmatch_api not installed"}))
        sys.exit(1)
    except Exception as e:
        print(json.dumps({"success": False, "error": str(e)}))
        sys.exit(1)

if __name__ == "__main__":
    main()
