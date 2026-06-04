# Gullify — Web Radio API integration guide (Android client)

**Audience:** Claude instance working in Android Studio on the Gullify mobile app.
**Purpose:** Bring the Android radio screens back in sync with the server side that has been refactored on `main` between 2026-05-04 and 2026-06-04.

This document covers:

1. Auth model
2. Stream format support (what the server hands you to play)
3. The new station data model (catalog + custom + per-user state + folders)
4. All HTTP endpoints
5. Required behavior changes on the client
6. Backwards-compat notes
7. Quick recipes (Kotlin pseudocode)

If you only have time to read three sections: **§3 data model**, **§4 endpoints**, **§5 client changes**.

---

## 1. Authentication

The Android client uses **Bearer token** auth on every Gullify API call.

### Getting a token

```
POST  https://gullify.app/api/login.php
Content-Type: application/json
{
  "username": "...",
  "password": "..."
}
```

Returns:
```json
{
  "success": true,
  "token":    "64-char hex string",
  "username": "maxime",
  "user_id":  1
}
```

Store `token` securely (Android Keystore-backed `EncryptedSharedPreferences` is fine).

### Sending the token

```
Authorization: Bearer <token>
```

The web radio endpoint **requires** this header for any per-user action (favorites, folders, custom stations, hidden flag). Anonymous calls only get the raw Radio Browser catalog with no personalization, and **the new POST actions will return HTTP 401** without a valid token.

The server-side gate is `src/auth_required.php`. It accepts either the Bearer token or a browser session cookie; the Android app should always use Bearer.

---

## 2. Stream format support

The server now **resolves playlist URLs server-side at insert time**, so the `streams[0].url` you get back is always something a player should be able to consume directly. Specifically:

| Source                         | What you get back                                   | Android player (ExoPlayer) |
|--------------------------------|------------------------------------------------------|------------------------------|
| Direct MP3 / Icecast / Shoutcast | The same URL, `format: "mp3"`                       | ✓ progressive HTTP source    |
| Direct AAC                     | Same URL, `format: "aac"` or `"aacp"`               | ✓ progressive                |
| Direct OGG / Opus / FLAC       | Same URL, `format: "ogg"` / `"opus"` / `"flac"`     | ✓ progressive                |
| `.m3u` / `.m3u8` playlist of streams | First inner URL extracted, `is_playlist: true` | ✓ progressive                |
| `.pls` playlist                | First `FileN=` URL extracted, `is_playlist: true`   | ✓ progressive                |
| HLS (`.m3u8` with `#EXT-X-STREAM-INF`) | URL passed through unchanged, `format: "hls"` | ✓ **use `HlsMediaSource`** |

**Client rule:** if the response has `streams[0].format == "hls"`, build an `HlsMediaSource`. Otherwise build a `ProgressiveMediaSource`. ExoPlayer's `DefaultMediaSourceFactory` will do the right thing automatically if you simply hand it the URL with the right MIME hint.

Helper extension on the JSON shape:

```kotlin
data class RadioStream(
    val url: String,
    val format: String?,        // mp3 | aac | ogg | opus | flac | hls | mp4 | unknown
    val bitrate: Int?,
    val secure: Boolean,
)

fun RadioStream.isHls(): Boolean = format?.equals("hls", ignoreCase = true) == true
```

`is_playlist` on a station means *the original URL was a playlist that the server already resolved* — you don't need to re-resolve it. It's there only as a UI cue if you want to surface "playlist source" in the edit dialog.

The full list of supported formats and detection rules lives in `src/RadioStreamResolver.php`.

---

## 3. Data model

There are three tables and one merge step.

### 3.1 Tables

```sql
radio_custom_stations
  id, user, name,
  stream_url,        -- resolved (what the player streams)
  original_url,      -- what the user typed (may be a playlist URL)
  logo, homepage,
  genres,            -- CSV string
  country, language,
  bitrate, format,   -- detected codec, e.g. "mp3"
  is_playlist,       -- 1 if stream_url was extracted from a playlist
  created_at, updated_at

radio_user_state
  user, station_id,  -- PK
  is_favorite,
  is_hidden,         -- per-user flag to hide a catalog station
  folder_id,         -- nullable, points at radio_folders.id

radio_folders
  id, user, name, color, sort_order, created_at
```

`station_id` is a **string**:
- For catalog stations (from Radio Browser), the Radio Browser `stationuuid` (UUID format).
- For custom stations, the string `"custom:N"` where `N` is `radio_custom_stations.id`.

So a station id is *always* a `String`, not an `Int`. Use a `String` field for it in your data classes.

### 3.2 The merged list

`GET ?action=list` returns the Radio Browser catalog merged with the user's custom stations, with per-user state decorated on each row, and hidden ones filtered out. Sort order: favorites first, then custom, then catalog by popularity.

```json
{
  "success": true,
  "data": {
    "updated":  "2026-06-04T…",
    "source":   "radio-browser",
    "count":    317,
    "stations": [
      {
        "id":           "custom:42",
        "custom":       true,
        "favorite":     true,
        "folder_id":    3,
        "name":         "CKOI 96.9",
        "country":      "Canada",
        "language":     "French",
        "genres":       ["pop", "dance"],
        "original_url": "https://stream.example.com/playlist.pls",
        "is_playlist":  true,
        "streams":      [{ "url": "https://stream.example.com/live", "format": "mp3", "bitrate": 128, "secure": true }],
        "logo":         "/serve_radio_logo.php?f=maxime_abc123_171…png",
        "website":      null
      },
      {
        "id":        "962c…UUID…",
        "custom":    false,
        "favorite":  false,
        "folder_id": null,
        "name":      "CBC Radio One",
        "genres":    ["news", "talk"],
        "streams":   [{ "url": "https://cbcradiolive…/master.m3u8", "format": "hls", "bitrate": 128, "secure": true }],
        "logo":      "https://www.cbc.ca/radio/images/cbc-radio-one-logo.png"
      }
    ]
  }
}
```

Important fields per station:

| Field          | Meaning                                                                                       |
|----------------|-----------------------------------------------------------------------------------------------|
| `id`           | String. `"custom:N"` or Radio Browser UUID                                                    |
| `custom`       | true if user-created (the only ones that can be **edited** or **deleted**)                    |
| `favorite`     | Per-user, comes from `radio_user_state`                                                       |
| `folder_id`    | int or null; nullable. Drives folder filtering                                                 |
| `streams[0]`   | The one you play. `format` tells you HLS vs progressive (§2).                                  |
| `original_url` | What the user pasted (only on custom stations). Show in the edit dialog as the input URL.      |
| `is_playlist`  | Bool. Only on custom stations. UI cue.                                                         |

The previous shape (catalog only, no `favorite` / `folder_id` / `custom`) is gone. You need to read those new fields.

### 3.3 Sort and visibility

The server already filters out hidden stations and sorts by:

1. `favorite DESC`
2. `custom DESC`
3. (catalog popularity)

Do not re-sort favorites yourself client-side or you'll fight the server.

---

## 4. HTTP endpoints

Base URL: `https://gullify.app/api/web-radio.php` *(canonical)*. The older entry point `https://gullify.app/web_radio_api.php` still works; it simply includes the canonical file. Either path is fine; the Android app should use `/api/web-radio.php` going forward.

All endpoints return JSON. All write endpoints (`add`, `update`, `remove*`, `toggle_*`, `folders_*`, `station_move`, `unhide_all`) require a Bearer token.

### 4.1 Read

| Action          | Method | Query / Body                       | Description |
|-----------------|--------|------------------------------------|-------------|
| `list`          | GET    | —                                  | Catalog + custom + decorated state, hidden filtered out |
| `search`        | GET    | `q=<text>`                         | Same shape as `list`, filtered |
| `genres`        | GET    | —                                  | Top 20 genres `{ genre: count, … }` |
| `refresh`       | GET    | —                                  | Force the catalog cache refresh from Radio Browser (1h TTL otherwise) |
| `get`           | GET    | `station_id=<id>`                  | Single station object (catalog or custom). Used to populate the edit dialog. |
| `folders_list`  | GET    | —                                  | All folders for the user with `station_count` |

### 4.2 Custom stations (CRUD)

| Action       | Method | Body (JSON)                                                                                          | Notes |
|--------------|--------|------------------------------------------------------------------------------------------------------|-------|
| `add`        | POST   | `{ name, url, logo?, genres?, country?, language?, homepage?, bitrate? }`                            | Returns `{ id: "custom:N", station: {...} }`. URL is auto-resolved (M3U/PLS → inner stream). |
| `update`     | POST   | `{ station_id: "custom:N", name, url, logo?, genres?, country?, language?, homepage?, bitrate? }`    | Only works on `custom:*` ids. Returns the updated station. URL is re-resolved if it changed. |
| `add_bulk`   | POST   | `{ items: [ { name, url, ... }, ... ] }`                                                             | Returns `{ added, failed }`. Used by the Import dialog. |
| `remove`     | POST   | `station_id=<id>`                                                                                    | If `custom:N` → real DELETE. If catalog id → toggles `is_hidden` (i.e. hide on first call, unhide on second). |
| `remove_bulk`| POST   | `{ station_ids: [...] }`                                                                              | Mixed list ok; custom deleted, catalog hidden |
| `unhide_all` | POST   | —                                                                                                    | Reset all `is_hidden` flags for the user |

### 4.3 Per-user state

| Action            | Method | Body                                                                              |
|-------------------|--------|-----------------------------------------------------------------------------------|
| `toggle_favorite` | POST   | `station_id=<id>` (works on **any** station id). Returns `{ favorite: bool }`     |

### 4.4 Folders

| Action            | Method | Body                                                              | Notes |
|-------------------|--------|-------------------------------------------------------------------|-------|
| `folders_create`  | POST   | `{ name, color? }`                                                | Returns `{ id }` |
| `folders_rename`  | POST   | `{ id, name, color? }`                                            | Color is optional CSS color string (e.g. `"#ff8030"`). |
| `folders_delete`  | POST   | `id=<int>`                                                        | Stations in the folder become unfiled, **not deleted** |
| `station_move`    | POST   | `{ station_ids: [...], folder_id: <int or null> }`                | `folder_id: null` to unfile |

### 4.5 Logo upload / fetch (custom stations)

| Endpoint                        | Method                | Notes |
|---------------------------------|-----------------------|-------|
| `/upload_radio_logo.php`        | POST multipart        | Field `logo` = file. JPEG / PNG / WebP, ≤ 4 MB. Returns `{ url }`. |
| `/upload_radio_logo.php?url=…`  | POST (form or query)  | Server-side fetch from the URL — use when the source server blocks hotlinking. Returns same shape. |
| `/serve_radio_logo.php?f=…`     | GET                   | Serves the saved PNG with ETag + Last-Modified. Public read. |

The returned `url` is what you store in `station.logo`. Do **not** keep the original external URL.

### 4.6 Common error shape

```json
{ "success": false, "error": "Nom et URL valides requis" }
```

HTTP status codes used:
- `200` on success
- `400` on validation failure (still has `success: false, error`)
- `401` on missing/invalid Bearer token
- `500` on server errors

---

## 5. Required behavior changes on the Android client

Things the client must do differently after this rewrite. Each item lists the *symptom* you'd see if you skip it.

1. **Send `Authorization: Bearer <token>` on every web-radio call.**
   Otherwise: 401 on every write, no favorites, no folders, no custom stations.

2. **Treat `station.id` as a String.**
   Both UUIDs (`"abcd-1234-…"`) and `"custom:N"` need to round-trip intact.
   Otherwise: parsing crashes or wrong rows deleted.

3. **Read `station.favorite`, `station.custom`, `station.folder_id` from the list response.**
   The previous shape didn't carry these.
   Otherwise: hearts always off, can't filter by folder, "Edit" shown on read-only catalog rows.

4. **For playback, branch on `streams[0].format`:**
   ```kotlin
   val item = MediaItem.Builder()
       .setUri(stream.url)
       .apply {
           if (stream.isHls()) setMimeType(MimeTypes.APPLICATION_M3U8)
       }
       .build()
   ```
   Otherwise: HLS stations (CBC, ICI Musique) won't play.

5. **When editing a station, fetch a fresh copy with `?action=get&station_id=…` to pre-fill the dialog.**
   The list version is decorated; `get` returns the raw row including `original_url` for custom stations.
   Otherwise: the URL field shows the resolved inner URL instead of what the user typed.

6. **On Save:**
   - If the station is custom (`station.custom == true`), call `?action=update`.
   - If it's a catalog station and the user edited fields, call `?action=add` with the new payload, then call `?action=remove` with the **original** catalog id to hide it. The grid will then show only the user's copy.
   - Pure favorite/unfavorite toggles always go through `?action=toggle_favorite`.

7. **Logo handling**
   - File picker → `POST /upload_radio_logo.php` (multipart). Use returned `url` as the logo field.
   - User pastes URL but image won't load (CORS / hotlink / mixed content) → offer a "Capturer URL" button that calls `POST /upload_radio_logo.php?url=<encoded URL>`. Replace the field with the returned `url`.
   - Never send the user's raw external URL to `?action=add` if you can avoid it — call the upload endpoint first so the image is mirrored on Gullify.

8. **Folders**
   - Fetch via `?action=folders_list` once when the screen opens.
   - Render as a horizontal chip strip above the grid: All + each folder (color dot + count) + Unfiled.
   - Filter the grid locally based on `station.folder_id`.
   - Long-press a station card → "Move to folder" action sheet, calls `?action=station_move`.
   - "+" chip → simple text dialog → `?action=folders_create`.

9. **Bulk import**
   - The textarea/M3U/PLS parser lives client-side on the web; the Android equivalent should send the parsed list to `?action=add_bulk` with `{ items: [{name, url, ...}, ...] }`.
   - If the user pastes raw M3U on Android, parse it like the web version (regex below).

10. **Drop the "Custom" badge from the UI** if you had one. It was confusing for the user and is gone from the web client.

---

## 6. Backwards-compat notes

- The Radio Browser-only response shape (`{ count, stations: [{ id, name, streams, logo }] }`) still works for anonymous (unauthenticated) calls.
- The legacy column `image` on `artists` (and any legacy base64 on stations) is no longer written; stations have no equivalent column to worry about.
- The Settings screen on the web exposes a "Restore hidden stations" path (`?action=unhide_all`). If the Android app has its own settings, add the same button there to recover from accidental hides.

---

## 7. Quick recipes (Kotlin)

### 7.1 Auth header

```kotlin
class AuthInterceptor(private val tokenStore: TokenStore) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val token = tokenStore.get() ?: return chain.proceed(chain.request())
        val req = chain.request().newBuilder()
            .header("Authorization", "Bearer $token")
            .build()
        return chain.proceed(req)
    }
}
```

### 7.2 Fetch list

```kotlin
interface RadioApi {
    @GET("api/web-radio.php?action=list")
    suspend fun listStations(): RadioListResponse

    @GET("api/web-radio.php")
    suspend fun getStation(@Query("action") a: String = "get", @Query("station_id") id: String): StationResponse

    @POST("api/web-radio.php")
    suspend fun toggleFavorite(
        @Query("action") a: String = "toggle_favorite",
        @Query("station_id") id: String
    ): FavoriteResponse

    @POST("api/web-radio.php")
    suspend fun addStation(
        @Query("action") a: String = "add",
        @Body body: AddStationBody
    ): StationResponse

    @POST("api/web-radio.php")
    suspend fun updateStation(
        @Query("action") a: String = "update",
        @Body body: UpdateStationBody
    ): StationResponse

    @POST("api/web-radio.php")
    suspend fun removeStation(
        @Query("action") a: String = "remove",
        @Query("station_id") id: String
    ): ApiResponse

    @POST("api/web-radio.php")
    suspend fun listFolders(@Query("action") a: String = "folders_list"): FoldersResponse

    @POST("api/web-radio.php")
    suspend fun moveStations(
        @Query("action") a: String = "station_move",
        @Body body: MoveStationsBody
    ): MoveResponse

    @Multipart
    @POST("upload_radio_logo.php")
    suspend fun uploadLogoFile(@Part logo: MultipartBody.Part): LogoResponse

    @FormUrlEncoded
    @POST("upload_radio_logo.php")
    suspend fun fetchLogoFromUrl(@Field("url") url: String): LogoResponse
}

data class RadioListResponse(val success: Boolean, val data: RadioListData)
data class RadioListData(val count: Int, val stations: List<Station>)

data class Station(
    val id: String,
    val name: String,
    @Json(name="custom")      val isCustom: Boolean = false,
    @Json(name="favorite")    val isFavorite: Boolean = false,
    @Json(name="folder_id")   val folderId: Int? = null,
    val genres: List<String> = emptyList(),
    val country: String? = null,
    val language: String? = null,
    val logo: String? = null,
    val streams: List<RadioStream> = emptyList(),
    @Json(name="original_url") val originalUrl: String? = null,
    @Json(name="is_playlist")  val isPlaylist: Boolean = false,
)

data class AddStationBody(
    val name: String,
    val url: String,
    val logo: String? = null,
    val genres: String = "",
    val country: String? = null,
    val language: String? = null,
)

data class UpdateStationBody(
    @Json(name="station_id") val stationId: String,
    val name: String,
    val url: String,
    val logo: String? = null,
    val genres: String = "",
    val country: String? = null,
    val language: String? = null,
)

data class MoveStationsBody(
    @Json(name="station_ids") val stationIds: List<String>,
    @Json(name="folder_id")   val folderId: Int?,
)
```

### 7.3 ExoPlayer setup

```kotlin
fun mediaItemFor(station: Station): MediaItem {
    val stream = station.streams.firstOrNull() ?: return MediaItem.EMPTY
    val mime = when (stream.format?.lowercase()) {
        "hls"          -> MimeTypes.APPLICATION_M3U8
        "aac", "aacp"  -> MimeTypes.AUDIO_AAC
        "mp3"          -> MimeTypes.AUDIO_MPEG
        "ogg"          -> MimeTypes.AUDIO_OGG
        "opus"         -> MimeTypes.AUDIO_OPUS
        "flac"         -> MimeTypes.AUDIO_FLAC
        else           -> null
    }
    return MediaItem.Builder()
        .setUri(stream.url)
        .apply { mime?.let { setMimeType(it) } }
        .build()
}
```

### 7.4 Parsing pasted M3U / PLS / URL list (matches the web parser)

```kotlin
fun parseBulk(text: String): List<AddStationBody> {
    val trimmed = text.trim()
    if (trimmed.isEmpty()) return emptyList()

    // JSON?
    if (trimmed.startsWith("[")) {
        return runCatching { moshi.adapter<List<AddStationBody>>(...).fromJson(trimmed) }
            .getOrNull().orEmpty()
    }

    val out = mutableListOf<AddStationBody>()
    var pendingName: String? = null
    trimmed.lineSequence().forEach { raw ->
        val line = raw.trim()
        if (line.isEmpty()) return@forEach
        when {
            line.startsWith("#EXTM3U") || line.startsWith("#EXTVLCOPT") -> Unit
            line.startsWith("#EXTINF") -> {
                pendingName = Regex("^#EXTINF:[^,]*,(.+)$").find(line)?.groupValues?.get(1)?.trim()
            }
            line.startsWith("#") -> Unit
            Regex("^https?://", RegexOption.IGNORE_CASE).containsMatchIn(line) -> {
                val host = runCatching { Uri.parse(line).host?.removePrefix("www.") }.getOrNull() ?: "Radio"
                out += AddStationBody(name = pendingName ?: host, url = line)
                pendingName = null
            }
        }
    }
    // PLS
    if (out.isEmpty() && trimmed.lowercase().contains("[playlist]")) {
        Regex("^File\\d+\\s*=\\s*(\\S+)", RegexOption.MULTILINE).findAll(trimmed)
            .map { it.groupValues[1].trim() }
            .filter { Regex("^https?://", RegexOption.IGNORE_CASE).containsMatchIn(it) }
            .forEach { out += AddStationBody(name = Uri.parse(it).host ?: "Radio", url = it) }
    }
    return out
}
```

---

## Reference: the relevant server files

If something behaves unexpectedly, these are the files to read on `main`:

| File                                          | Role |
|-----------------------------------------------|------|
| `public/api/web-radio.php`                    | All HTTP routes for the radio module |
| `public/web_radio_api.php`                    | Thin alias that delegates to `api/web-radio.php` |
| `src/RadioStations.php`                       | DB layer: custom stations, state, folders |
| `src/RadioStreamResolver.php`                 | URL → resolved stream + format detection |
| `public/upload_radio_logo.php`                | Logo upload + URL fetch (multipart and `?url=`) |
| `public/serve_radio_logo.php`                 | Public read of `/data/cache/radio_logos/*` |
| `src/auth_required.php`                       | Bearer + session auth gate |
| `public/api/login.php`                        | Token issuance for the Android client |

All schema is auto-bootstrapped on the first call: `radio_custom_stations`, `radio_user_state` (with the `folder_id` column added on upgrade), `radio_folders`. No manual migration is required when the server pulls the latest code.
