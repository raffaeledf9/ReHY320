"""The exact edits patch.py makes, as (old, new) pairs per file. See patch.py for why."""

K = "app/src/main/kotlin/io/github/jqssun/airplay/"


def player():
    return [
        (
            "    var onEnded: (() -> Unit)? = null\n",
            "    var onEnded: (() -> Unit)? = null\n"
            "    // hy320: the player stopped by itself (true: reached the end; false: failed) and\n"
            "    // is kept so the sender can read that; the service decides when to give up\n"
            "    var onFinished: ((ended: Boolean) -> Unit)? = null\n",
        ),
        (
            "        override fun onPlayerError(error: androidx.media3.common.PlaybackException) {\n"
            "            Log.w(TAG, \"playback error\", error)\n"
            "            onEnded?.invoke()\n"
            "        }\n"
            "        override fun onPlaybackStateChanged(state: Int) {\n"
            "            if (state == Player.STATE_ENDED) onEnded?.invoke()\n"
            "        }\n",
            "        // hy320: neither of these tears the session down any more. Releasing the player\n"
            "        // here left the -1 sentinel for the sender's next poll, and UxPlay then hung up\n"
            "        // on the sender mid-session. Kept, the report tick answers with where it stopped\n"
            "        // (at the end: position = duration, rate 0), and the sender ends the session.\n"
            "        override fun onPlayerError(error: androidx.media3.common.PlaybackException) {\n"
            "            Log.w(TAG, \"playback error\", error)\n"
            "            _reportPlaybackInfo()\n"
            "            onFinished?.invoke(false)\n"
            "        }\n"
            "        override fun onPlaybackStateChanged(state: Int) {\n"
            "            if (state == Player.STATE_ENDED) {\n"
            "                _reportPlaybackInfo()\n"
            "                onFinished?.invoke(true)\n"
            "            }\n"
            "        }\n",
        ),
    ]


def service():
    return [
        (
            "    @Volatile private var _videoPollSuppressed = false\n",
            "    @Volatile private var _videoPollSuppressed = false\n"
            "\n"
            "    // hy320: a finished video is held for the sender to end; this stops it if it never does\n"
            "    private val _finishHandler = Handler(Looper.getMainLooper())\n"
            "    private val _finishFallback = Runnable {\n"
            "        _endVideoPlayback(\"AirPlay Video stopped (finished, sender idle)\")\n"
            "    }\n",
        ),
        (
            "        airPlayVideoPlayer.onEnded = { _endVideoPlayback(\"AirPlay Video stopped (player)\") }\n",
            "        airPlayVideoPlayer.onEnded = { _endVideoPlayback(\"AirPlay Video stopped (player)\") }\n"
            "        airPlayVideoPlayer.onFinished = { ended ->\n"
            "            log(if (ended) \"AirPlay Video ended; holding for the sender\"\n"
            "                else \"AirPlay Video failed; holding for the sender\")\n"
            "            _finishHandler.removeCallbacks(_finishFallback)\n"
            "            _finishHandler.postDelayed(_finishFallback, FINISHED_HOLD_MS)\n"
            "        }\n",
        ),
        (
            "    private fun _endVideoPlayback(message: String) {\n"
            "        if (!_videoPlaybackActive.value) return\n",
            "    private fun _endVideoPlayback(message: String) {\n"
            "        _finishHandler.removeCallbacks(_finishFallback)\n"
            "        if (!_videoPlaybackActive.value) return\n",
        ),
        (
            "    override fun onVideoPlay(location: String, startPositionSeconds: Float) {\n",
            "    override fun onVideoPlay(location: String, startPositionSeconds: Float) {\n"
            "        _finishHandler.removeCallbacks(_finishFallback)\n",
        ),
        (
            "    override fun onVideoScrub(positionSeconds: Float) {\n"
            "        airPlayVideoPlayer.scrub(positionSeconds)\n",
            "    override fun onVideoScrub(positionSeconds: Float) {\n"
            "        _finishHandler.removeCallbacks(_finishFallback)\n"
            "        airPlayVideoPlayer.scrub(positionSeconds)\n",
        ),
        # /rate is deliberately left alone: at STATE_ENDED a rate of 1 plays nothing, so it
        # must not cancel the fallback. A /scrub does restart playback (above), and does.
        (
            "        const val VIDEO_POLL_PENDING_TIMEOUT_MS = 3_000L\n",
            "        const val VIDEO_POLL_PENDING_TIMEOUT_MS = 3_000L\n"
            "        // hy320: how long a finished video waits for the sender's /stop or next /play\n"
            "        private const val FINISHED_HOLD_MS = 30_000L\n",
        ),
    ]


def gradle():
    return [
        ('        versionName = "0.0.36"\n', '        versionName = "0.0.36-hy320.5"\n'),
    ]


def native_bridge():
    # Diagnostics, temporary: UxPlay's own INFO lines (and the hy320 ones below) reach logcat
    # only at INFO. Upstream ships ERR. Revert once the Next-episode path is understood.
    return [
        ("    raop_set_log_level(ctx->raop, LOGGER_ERR);\n",
         "    raop_set_log_level(ctx->raop, LOGGER_INFO);  /* hy320: diagnostics */\n"),
    ]


def uxplay_diag():
    return [
        # every request the sender makes, method and URL
        ('    logger_log(raop->logger, LOGGER_DEBUG, "Handling request %s with URL %s", method, url);\n',
         '    logger_log(raop->logger, LOGGER_INFO, "hy320 request %s %s", method, url);\n'),
    ]


def uxplay_action_diag():
    # The handler gives up at once when no video is current, before reading the body, so the
    # body is logged first: on 2026-10-28 03:41:19 two requests were refused this way right
    # after Next, and what they asked for is the missing piece.
    return [
        (
            "    bool logger_debug = (logger_get_level(raop->logger) >= LOGGER_DEBUG);\n"
            "    if (!airplay_video) goto post_action_error;\n",
            "    bool logger_debug = (logger_get_level(raop->logger) >= LOGGER_DEBUG);\n"
            "    {   /* hy320 diagnostics: what the sender asked for, before any early exit */\n"
            "        int dl = 0;\n"
            "        const char *dd = http_request_get_data(request, &dl);\n"
            "        plist_t n = NULL;\n"
            "        if (dd && dl > 0) plist_from_bin(dd, dl, &n);\n"
            "        plist_t tn = n ? plist_dict_get_item(n, \"type\") : NULL;\n"
            "        char *ts = NULL;\n"
            "        if (tn && PLIST_IS_STRING(tn)) plist_get_string_val(tn, &ts);\n"
            "        if (ts && strcmp(ts, \"unhandledURLResponse\")) {\n"
            "            char *xml = NULL;\n"
            "            uint32_t xl = 0;\n"
            "            plist_to_xml(n, &xml, &xl);\n"
            "            logger_log(raop->logger, LOGGER_INFO, \"hy320 action %s (current_video %d):\\n%s\",\n"
            "                       ts, raop->current_video, xml ? xml : \"\");\n"
            "            if (xml) plist_mem_free(xml);\n"
            "        }\n"
            "        if (ts) plist_mem_free(ts);\n"
            "        if (n) plist_free(n);\n"
            "    }\n"
            "    if (!airplay_video) goto post_action_error;\n",
        ),
        (
            "    if (!playback_uuid) {\n"
            "        playback_uuid = strdup(apple_session_id);\n"
            "    }\n",
            "    if (!playback_uuid) {\n"
            "        playback_uuid = strdup(apple_session_id);\n"
            "    }\n"
            "    logger_log(raop->logger, LOGGER_INFO, \"hy320 play: uuid %s start %f location %s\",\n"
            "               playback_uuid, start_position_seconds, playback_location);\n",
        ),
    ]


# UxPlay, as already patched by the app's own 0001-0009 (patch.sh applies those first).
UXPLAY = "app/src/main/cpp/third_party/UxPlay/lib/http_handlers.h"


def uxplay():
    # THE BUG (seen 2026-10-28 03:10:08): the iPad's /play for the NEXT episode carried no
    # uuid, so the session id stood in for it -- the same id as the episode before. The
    # stored entry matched, and the reuse branch played its stored location: episode 6
    # again, while Shirox showed episode 7. A stored entry is only the same video if it is
    # the same location; otherwise it is dropped and the request is taken as new.
    # Direct URLs only: an HLS entry stores a rewritten localhost location, which never
    # equals the request's, and its reuse (resuming after an advert) must keep working.
    return [
        (
            "    id = get_playlist_by_uuid(raop, playback_uuid);\n"
            "\n"
            "    if (id >= 0 && !get_playback_location(raop->airplay_video[id])) {\n",
            "    id = get_playlist_by_uuid(raop, playback_uuid);\n"
            "\n"
            "    /* hy320: a uuid-less sender (the session id stands in) reuses the same id for the\n"
            "       next item; a stored direct-URL entry is only the same video at the same URL */\n"
            "    if (id >= 0 && !strstr(playback_location, \"/master.m3u8\") &&\n"
            "        get_playback_location(raop->airplay_video[id]) &&\n"
            "        strcmp(get_playback_location(raop->airplay_video[id]), playback_location)) {\n"
            "        logger_log(raop->logger, LOGGER_INFO, \"play: same uuid, new location: new video\");\n"
            "        raop_destroy_airplay_video(raop, id);\n"
            "        id = -1;\n"
            "    }\n"
            "\n"
            "    if (id >= 0 && !get_playback_location(raop->airplay_video[id])) {\n",
        ),
    ]


INSERT_FN = r'''/* hy320: AirPlay's playlistInsert, for a direct (non-HLS) URL.
   iOS changes the item on a live AirPlay video session with playlistRemove + playlistInsert,
   not a new /play: measured 2026-10-28 03:57:38-46 with Shirox pressing Next, the insert
   carrying the next episode's Content-Location and uuid, then /scrub 0 and /rate 1. UxPlay
   has never implemented the insert ("FIXME: playlistInsert is not yet implemented"), so the
   new URL was dropped and scrub/rate restarted the old item. This does for the inserted item
   what /play does for a direct URL. HLS items need the FCUP playlist fetch and are left alone. */
static bool
hy320_playlist_insert(raop_conn_t *conn, http_request_t *request) {
    raop_t *raop = conn->raop;
    bool handled = false;
    plist_t root = NULL, params = NULL, item = NULL, n = NULL;
    char *type = NULL, *uuid = NULL, *loc = NULL;
    double start = 0.0;
    int id = -1;
    int dl = 0;
    const char *dd = http_request_get_data(request, &dl);
    const char *session = http_request_get_header(request, "X-Apple-Session-ID");
    airplay_video_t *v = NULL;

    if (!dd || dl <= 0 || !session) return false;
    plist_from_bin(dd, dl, &root);
    if (!root || !PLIST_IS_DICT(root)) goto done;
    n = plist_dict_get_item(root, "type");
    if (n && PLIST_IS_STRING(n)) plist_get_string_val(n, &type);
    if (!type || strcmp(type, "playlistInsert")) goto done;
    params = plist_dict_get_item(root, "params");
    if (params && PLIST_IS_DICT(params)) item = plist_dict_get_item(params, "item");
    if (!item || !PLIST_IS_DICT(item)) goto done;
    n = plist_dict_get_item(item, "uuid");
    if (n && PLIST_IS_STRING(n)) plist_get_string_val(n, &uuid);
    n = plist_dict_get_item(item, "Content-Location");
    if (n && PLIST_IS_STRING(n)) plist_get_string_val(n, &loc);
    if (!uuid || !loc) goto done;
    if (strncmp(loc, "http://", 7) && strncmp(loc, "https://", 8)) goto done;
    if (strstr(loc, "/master.m3u8")) goto done;
    n = plist_dict_get_item(item, "Start-Position-Seconds");
    if (!n) n = plist_dict_get_item(item, "Start-Position");
    if (n && PLIST_IS_REAL(n)) plist_get_real_val(n, &start);

    id = get_playlist_by_uuid(raop, uuid);
    if (id >= 0) raop_destroy_airplay_video(raop, id);
    id = -1;
    for (int i = 0; i < MAX_AIRPLAY_VIDEO; i++) {
        if (!raop->airplay_video[i]) { id = i; break; }
    }
    if (id < 0) {
        id = (raop->current_video + 1 + MAX_AIRPLAY_VIDEO) % MAX_AIRPLAY_VIDEO;
        raop_destroy_airplay_video(raop, id);
    }
    raop->airplay_video[id] = airplay_video_init(raop, raop->port, raop->lang);
    v = raop->airplay_video[id];
    if (!v) goto done;
    raop->current_video = id;
    set_apple_session_id(v, session, strlen(session));
    set_playback_uuid(v, uuid, strlen(uuid));
    set_playback_location(v, loc, strlen(loc));
    set_start_position_seconds(v, (float) start);
    logger_log(raop->logger, LOGGER_INFO, "hy320 playlistInsert: playing %s @ %f", loc, start);
    raop->callbacks.on_video_play(raop->callbacks.cls, get_playback_location(v), (float) start);
    raop->video_play_conn = (void *) conn;
    hy320_current_item_event(raop, v);
    handled = true;

 done:
    if (type) plist_mem_free(type);
    if (uuid) plist_mem_free(uuid);
    if (loc) plist_mem_free(loc);
    if (root) plist_free(root);
    return handled;
}

'''


def uxplay_insert():
    return [
        (
            "static void\n"
            "http_handler_action(raop_conn_t *conn, http_request_t *request, http_response_t *response,\n",
            INSERT_FN +
            "static void\n"
            "http_handler_action(raop_conn_t *conn, http_request_t *request, http_response_t *response,\n",
        ),
        (
            "    if (!airplay_video) goto post_action_error;\n"
            "\n"
            "    const char* session_id = http_request_get_header(request, \"X-Apple-Session-ID\");\n",
            "    if (hy320_playlist_insert(conn, request)) {\n"
            "        hy320_action_ok(response, response_data, response_datalen);\n"
            "        return;\n"
            "    }\n"
            "    if (!airplay_video) goto post_action_error;\n"
            "\n"
            "    const char* session_id = http_request_get_header(request, \"X-Apple-Session-ID\");\n",
        ),
        # hy320.5: the other actions that succeed (playlistRemove, unhandledURLResponse) answer
        # the same way, as upstream UxPlay does since PR #579; the 400 error path is unchanged
        (
            "    plist_mem_free(type);\n"
            "    plist_free(req_root_node);\n"
            "    return;\n",
            "    hy320_action_ok(response, response_data, response_datalen);\n"
            "    plist_mem_free(type);\n"
            "    plist_free(req_root_node);\n"
            "    return;\n",
        ),
    ]


# hy320.5 -- the sender's controls. Measured 2026-10-28 04:11-04:13 (logcat-hy320.4.txt):
# with Shirox, the time stayed at 0:00 and the 10 s jumps did nothing useful, while the drag
# bar (an absolute /scrub) and play/pause (/rate) worked; after Next the iPad polled 8 more
# times, then stopped asking. iOS ties each /playback-info answer to its item by the "uuid"
# key, which UxPlay never sent (raop.h has it commented out); the 10 s jumps are computed
# from the time the iPad thinks it is at, so they fail with it. Upstream UxPlay added the key
# and a currentItemChanged event after playlistInsert in PR #579 (merged 2026-09-25); that PR
# does not apply to the app's UxPlay, so the needed parts are written here.
EVENTS_FN = r'''/* hy320: events to the sender on the reverse ("PTTH") connection, sent as fcup_request()
   sends its requests there. httpd already drops the sender's 200 replies on that connection. */
#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif

static bool hy320_end_reported = false;

static int
hy320_send_event(raop_t *raop, airplay_video_t *video, plist_t event, const char *what) {
    int fd = httpd_get_connection_socket_by_type(raop->httpd, CONNECTION_TYPE_PTTH, 1);
    const char *session = video ? get_apple_session_id(video) : NULL;
    if (fd <= 0 || !session) {
        logger_log(raop->logger, LOGGER_WARNING, "hy320 event %s: no reverse connection", what);
        plist_free(event);
        return -1;
    }
    char *xml = NULL;
    uint32_t xl = 0;
    plist_to_xml(event, &xml, &xl);
    plist_free(event);
    http_response_t *req = http_response_create();
    http_response_reverse_request_init(req, "POST", "/event", "HTTP/1.1");
    http_response_add_header(req, "X-Apple-Session-ID", session);
    http_response_add_header(req, "Content-Type", "text/x-apple-plist+xml");
    http_response_finish(req, xml, (int) xl);
    plist_mem_free(xml);
    int len = 0, sent = 0;
    const char *data = http_response_get_data(req, &len);
    while (sent < len) {
#ifdef MSG_NOSIGNAL
        int n = send(fd, data + sent, len - sent, MSG_NOSIGNAL);
#else
        int n = send(fd, data + sent, len - sent, 0);
#endif
        if (n <= 0) break;
        sent += n;
    }
    http_response_destroy(req);
    logger_log(raop->logger, sent == len ? LOGGER_INFO : LOGGER_ERR, "hy320 event %s: %s",
               what, sent == len ? "sent" : "send failed");
    return sent == len ? 0 : -1;
}

/* after a playlistInsert: the inserted item is now the current one */
static void
hy320_current_item_event(raop_t *raop, airplay_video_t *video) {
    const char *uuid = get_playback_uuid(video);
    if (!uuid) return;
    plist_t event = plist_new_dict();
    plist_dict_set_item(event, "sessionID", plist_new_uint(1));
    plist_dict_set_item(event, "type", plist_new_string("currentItemChanged"));
    plist_dict_set_item(event, "uuid", plist_new_string(uuid));
    plist_t item = plist_new_dict();
    plist_dict_set_item(item, "uuid", plist_new_string(uuid));
    plist_dict_set_item(event, "itemCurrent", item);
    hy320_send_event(raop, video, event, "currentItemChanged");
}

'''


EVENTS_FN += r'''/* The item reached its end (ready, at its duration, rate 0): logged once per end. What a real
   Apple TV tells the sender then is not documented; the classic video event is
   {category video, sessionID, state loading|playing|paused|stopped}. Which state is sent, if
   any, is read from debug.hy320.endstate at that moment (unset or "none": nothing), so the
   choice can be tried without a rebuild:   adb shell setprop debug.hy320.endstate stopped */
static void
hy320_check_end(raop_t *raop, const playback_info_t *info) {
    bool at_end = info->ready_to_play && info->duration > 1.0 && info->rate == 0.0f &&
                  info->position >= info->duration - 0.5;
    if (!at_end) {
        hy320_end_reported = false;
        return;
    }
    if (hy320_end_reported) return;
    hy320_end_reported = true;
    char state[92] = "";   /* PROP_VALUE_MAX */
#ifdef __ANDROID__
    __system_property_get("debug.hy320.endstate", state);
#endif
    logger_log(raop->logger, LOGGER_INFO, "hy320 item ended at %.3f of %.3f s; end event: %s",
               info->position, info->duration, state[0] ? state : "none");
    if (!state[0] || !strcmp(state, "none")) return;
    airplay_video_t *video = raop->current_video >= 0 ? raop->airplay_video[raop->current_video] : NULL;
    plist_t event = plist_new_dict();
    plist_dict_set_item(event, "category", plist_new_string("video"));
    plist_dict_set_item(event, "sessionID", plist_new_uint(1));
    plist_dict_set_item(event, "state", plist_new_string(state));
    hy320_send_event(raop, video, event, state);
}

/* the reply to an action that succeeded: an empty 200 does not acknowledge a queue change */
static void
hy320_action_ok(http_response_t *response, char **response_data, int *response_datalen) {
    plist_t status = plist_new_dict();
    plist_dict_set_item(status, "errorCode", plist_new_uint(0));
    plist_to_xml(status, response_data, (uint32_t *) response_datalen);
    plist_free(status);
    http_response_add_header(response, "Content-Type", "text/x-apple-plist+xml");
}

'''


def uxplay_controls():
    return [
        (
            "    plist_t res_root_node = plist_new_dict();\n"
            "\n"
            "    plist_t duration_node = plist_new_real(playback_info->duration);\n",
            "    plist_t res_root_node = plist_new_dict();\n"
            "\n"
            "    if (playback_info->uuid) {   /* hy320: the item this answer is about */\n"
            "        plist_dict_set_item(res_root_node, \"uuid\", plist_new_string(playback_info->uuid));\n"
            "    }\n"
            "\n"
            "    plist_t duration_node = plist_new_real(playback_info->duration);\n",
        ),
        (
            "static void\n"
            "http_handler_playback_info(",
            EVENTS_FN +
            "static void\n"
            "http_handler_playback_info(",
        ),
        (
            "    raop->callbacks.on_video_acquire_playback_info(raop->callbacks.cls, &playback_info);\n",
            "    raop->callbacks.on_video_acquire_playback_info(raop->callbacks.cls, &playback_info);\n"
            "    /* hy320: the sender matches this answer to its item by uuid */\n"
            "    playback_info.uuid = raop->current_video >= 0 && raop->airplay_video[raop->current_video] ?\n"
            "        get_playback_uuid(raop->airplay_video[raop->current_video]) : NULL;\n",
        ),
        (
            "    *response_datalen =  create_playback_info_plist_xml(&playback_info, response_data);\n",
            "    hy320_check_end(raop, &playback_info);\n"
            "    *response_datalen =  create_playback_info_plist_xml(&playback_info, response_data);\n",
        ),
    ]


def uxplay_raop_h():
    return [
        ("  //char * uuid;\n",
         "    const char *uuid;  /* hy320: the current item's playback uuid, or NULL */\n"),
    ]


def edits(part="app"):
    # "uxplay" edits the UxPlay submodule after the app's own patches; patch.sh turns that
    # into patches/UxPlay/0010-*.patch, because the build resets those files and re-applies
    # the patch files before compiling, which would wipe a direct edit.
    if part == "uxplay":
        return {
            "lib/http_handlers.h": uxplay() + uxplay_action_diag() + uxplay_insert() + uxplay_controls(),
            "lib/raop.c": uxplay_diag(),
            "lib/raop.h": uxplay_raop_h(),
        }
    return {
        K + "renderer/AirPlayVideoPlayer.kt": player(),
        K + "service/AirPlayService.kt": service(),
        "app/build.gradle.kts": gradle(),
        "app/src/main/cpp/native_bridge.cpp": native_bridge(),
    }
