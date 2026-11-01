package com.hy320.tools;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.os.Bundle;
import android.provider.Settings;
import android.view.KeyEvent;
import android.view.View;

/**
 * The projector's own settings, as a grid of tiles like the screen this replaces.
 *
 * Eight of them, over two rows of four, which leaves each tile big enough to read across a
 * room. The HDMI input is not among them: it has a tile of its own on the home screen now.
 * Android's own settings are, in the slot that left behind, so they can be reached from
 * here rather than only by going back out to the home screen.
 *
 * AirPlay took its place. It belongs here rather than on the home screen because nobody
 * starts a cast from the projector: the iPad does that, and the app is only ever opened to
 * change a setting.
 *
 * Most icons are the projector's own, taken from the vendor settings app before it was
 * removed, and the blue is the one read off its screen, so this looks like part of the
 * projector rather than something bolted on. The AirPlay one is drawn to the same
 * measure by art/make-airplay-icon.py.
 */
public class MainActivity extends Activity {

    /** The AirPlay app, which is here for its settings only: casting starts at the iPad. */
    private static final String AIRPLAY = "io.github.jqssun.airplay";

    /** The file manager, and the one screen of its own that is worth a tile here. */
    private static final String FILES = "me.zhanghai.android.files";
    private static final String MANAGE_FTP_SERVER =
            "me.zhanghai.android.files.intent.action.MANAGE_FTP_SERVER";

    private static final String[] LABELS = {
            "Keystone", "Picture", "Screen zoom", "Projection", "Screen saver", "AirPlay",
            "File server", "Settings"};
    private static final String[] ICONS = {
            "icon_mode_trapezoid", "icon_mode_color", "icon_mode_zoom",
            "icon_mode_projection", "icon_mode_screensaver", "icon_mode_airplay",
            "icon_mode_server", "icon_mode_settings"};
    private static final String[] ICONS_LIT = {
            "icon_mode_trapezoid_focus", "icon_mode_color_focus", "icon_mode_zoom_focus",
            "icon_mode_projection_focus", "icon_mode_screensaver_focus",
            "icon_mode_airplay_focus", "icon_mode_server_focus",
            "icon_mode_settings_focus"};

    private HomeView view;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        view = new HomeView(this);
        setContentView(view);
    }

    @Override
    public boolean onKeyDown(int code, KeyEvent event) {
        switch (code) {
            case KeyEvent.KEYCODE_DPAD_LEFT:
                move(-1, 0);
                return true;
            case KeyEvent.KEYCODE_DPAD_RIGHT:
                move(1, 0);
                return true;
            case KeyEvent.KEYCODE_DPAD_UP:
                move(0, -1);
                return true;
            case KeyEvent.KEYCODE_DPAD_DOWN:
                move(0, 1);
                return true;
            case KeyEvent.KEYCODE_DPAD_CENTER:
            case KeyEvent.KEYCODE_ENTER:
                open(view.index);
                return true;
            default:
                return super.onKeyDown(code, event);
        }
    }

    /** Steps around the grid, wrapping at every edge so no press does nothing. */
    private void move(int acrossBy, int downBy) {
        int across = (view.index % HomeView.COLUMNS + acrossBy + HomeView.COLUMNS) % HomeView.COLUMNS;
        int down = (view.index / HomeView.COLUMNS + downBy + HomeView.ROWS) % HomeView.ROWS;
        // Guards a last row that is not full: its empty corner falls back onto the last
        // real tile rather than leaving the arrow pointing at nothing.
        view.index = Math.min(down * HomeView.COLUMNS + across, LABELS.length - 1);
        view.invalidate();
    }

    private void open(int which) {
        switch (which) {
            case 0:
                start(new Intent(this, KeystoneActivity.class));
                return;
            case 1:
                start(new Intent(this, PictureActivity.class));
                return;
            case 2:
                start(new Intent(this, ZoomActivity.class));
                return;
            case 3:
                start(new Intent(this, ProjectionActivity.class));
                return;
            case 4:
                start(new Intent(this, StandbyActivity.class));
                return;
            case 5:
                // Someone else's app, so it gets its own task, the way a launcher starts
                // one. If it is ever uninstalled the press simply does nothing.
                Intent airplay = getPackageManager().getLaunchIntentForPackage(AIRPLAY);
                if (airplay != null) {
                    start(airplay);
                }
                return;
            case 6:
                // The file manager's own FTP server screen, which it answers to directly,
                // so this lands on it rather than in the file list with a drawer to walk.
                // Named by package as well, so no chooser can appear.
                Intent server = new Intent(MANAGE_FTP_SERVER);
                server.setPackage(FILES);
                start(server);
                return;
            default:
                // Android's own settings. On this firmware they carry no launcher entry of
                // either kind, so this action is the only way in; the manifest asks about
                // it by name, or Android 11 would hide the activity that answers.
                start(new Intent(Settings.ACTION_SETTINGS));
        }
    }

    private void start(Intent intent) {
        try {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(intent);
        } catch (Throwable ignored) {
            // nothing sensible to do if a screen will not open
        }
    }

    /** A grid of tiles: an icon above a name, the chosen one lit. */
    static final class HomeView extends View {

        static final int COLUMNS = 4;
        static final int ROWS = 2;

        private static final int BACKGROUND = Color.parseColor("#0162B1");
        private static final int TILE = Color.parseColor("#1C74BD");
        private static final int TILE_ON = Color.WHITE;

        int index = 0;

        private final Bitmap[] icons = new Bitmap[LABELS.length];
        private final Bitmap[] lit = new Bitmap[LABELS.length];
        private final Paint tile = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint label = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint title = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final float density;

        HomeView(Context context) {
            super(context);
            density = context.getResources().getDisplayMetrics().density;
            setFocusable(true);
            setBackgroundColor(BACKGROUND);
            for (int i = 0; i < LABELS.length; i++) {
                icons[i] = load(context, ICONS[i]);
                lit[i] = load(context, ICONS_LIT[i]);
            }
            tile.setStyle(Paint.Style.FILL);
            label.setTextAlign(Paint.Align.CENTER);
            label.setTextSize(dp(15));
            title.setTextSize(dp(22));
            title.setColor(Color.WHITE);
        }

        private static Bitmap load(Context context, String name) {
            try {
                return BitmapFactory.decodeStream(context.getAssets().open(name + ".png"));
            } catch (Throwable t) {
                return null;    // the tile still works, just without its picture
            }
        }

        private float dp(float v) {
            return v * density;
        }

        @Override
        protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            float w = getWidth();
            float h = getHeight();
            canvas.drawText("Projector", dp(40), dp(54), title);

            // The grid takes whatever is left under the title, and the tiles are square,
            // so the side is whichever of width or height fits worse.
            float margin = dp(52);
            float gap = dp(22);
            float top = dp(86);
            float bottom = h - dp(48);
            float side = Math.min((w - margin * 2 - gap * (COLUMNS - 1)) / COLUMNS,
                    (bottom - top - gap * (ROWS - 1)) / ROWS);
            float x0 = (w - (side * COLUMNS + gap * (COLUMNS - 1))) / 2;
            float y0 = top + (bottom - top - (side * ROWS + gap * (ROWS - 1))) / 2;

            label.setTextSize(side * 0.1f);
            for (int i = 0; i < LABELS.length; i++) {
                boolean on = i == index;
                float left = x0 + (i % COLUMNS) * (side + gap);
                float topOfTile = y0 + (i / COLUMNS) * (side + gap);
                RectF box = new RectF(left, topOfTile, left + side, topOfTile + side);
                tile.setColor(on ? TILE_ON : TILE);
                canvas.drawRoundRect(box, dp(18), dp(18), tile);

                Bitmap picture = on && lit[i] != null ? lit[i] : icons[i];
                if (picture != null) {
                    float iconWidth = side * 0.52f;
                    float iconHeight = iconWidth * picture.getHeight() / picture.getWidth();
                    float cx = box.centerX();
                    // Icon and name are placed as one block, centred in the tile, so no
                    // gap opens up between them as the tiles grow.
                    float iconTop = box.top + side * 0.19f;
                    canvas.drawBitmap(picture, null,
                            new RectF(cx - iconWidth / 2, iconTop, cx + iconWidth / 2, iconTop + iconHeight),
                            null);
                }
                label.setColor(on ? BACKGROUND : Color.WHITE);
                canvas.drawText(LABELS[i], box.centerX(), box.top + side * 0.80f, label);
            }

        }
    }
}
