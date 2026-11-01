package com.hy320.tools;

import android.app.Activity;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.RectF;
import android.graphics.drawable.Drawable;
import android.net.Uri;
import android.os.Bundle;
import android.provider.Settings;
import android.view.KeyEvent;
import android.view.View;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * The home screen.
 *
 * Two sections. The top row is the handful of things that run the projector itself, in the
 * order the owner chose; everything below is simply every other app on the unit.
 *
 * The second section is not a list anybody keeps. It is asked of the package manager every
 * time this screen comes forward, so an app installed a minute ago is already there when
 * you come back from the Play Store. That is the whole reason this replaces the previous
 * launcher, which sorted apps into its sections once, on its very first run, and never
 * again.
 *
 * Two of the remote's dead keys are answered here as well: the one under the cast symbol
 * opens the HDMI input, and the menu key opens the projector's own settings. The one under
 * the source symbol is left alone, because the firmware already opens the Miracast
 * receiver with it, from wherever you happen to be.
 */
public class LauncherActivity extends Activity {

    /**
     * The first row, read left to right. One that is not installed is skipped, and the row
     * scrolls sideways rather than wrapping, so it stays one row however long it grows.
     *
     * Each entry is a package, an activity to insist on or null for whichever the launcher
     * query found, the short name to put under it, and an action to fall back on.
     *
     * Two of them name an activity. This package puts two tiles here, the HDMI input and
     * the settings menu, so neither can be left to chance. Android's own settings need the
     * last field instead: on this firmware `com.android.tv.settings` carries no launcher
     * entry of either kind, so no amount of asking for launchable activities will ever
     * turn it up, and it answers only to the settings action.
     *
     * AirPlay is deliberately absent. Nobody starts a cast from the projector, so it lives
     * inside the settings menu with the other things you only open to change.
     */
    static final String[][] SYSTEM = {
            {"com.hy320.tools", "com.hy320.tools.HdmiActivity", "HDMI", null},
            {"com.hy320.tools", "com.hy320.tools.MainActivity", "Projector", null},
            {"me.zhanghai.android.files", null, "Files", null},
            {"com.android.vending", null, "Store", null},
            {"com.softwinner.miracastReceiver", null, "Miracast", null},
            {"com.android.tv.settings", null, "Settings", "android.settings.SETTINGS"},
            {"com.topjohnwu.magisk", null, "Magisk", null},
    };

    /**
     * Installed, but given a home somewhere else, so the second section leaves it alone.
     *
     * AirPlay is the only one: it is reached from inside the settings menu, because a cast
     * is started at the iPad and the app itself is only ever opened to change something.
     * Listing it here as well would be the same app twice.
     */
    static final String[] ELSEWHERE = {
            "io.github.jqssun.airplay",
    };

    /**
     * The remote's top centre key, under the cast symbol.
     *
     * The firmware calls it KEYCODE_PRJ_FOCUS_DN and gives it a keycode of its own
     * invention, 289, so there is no constant in Android to name it by. It opened the
     * vendor's AirPlay app, which the cleaning removed, and the firmware has thrown
     * ActivityNotFoundException on every press since; the HDMI input is a better use of
     * a key that was doing nothing.
     *
     * Asked for by name rather than by number, so a firmware that has never heard of it
     * answers KEYCODE_UNKNOWN and the key is simply left alone.
     *
     * Its neighbour under the source symbol is not here: that one is KEYCODE_PRJ_FOCUS_UP,
     * and the firmware already opens the Miracast receiver with it, from whatever app is
     * in front. It fails only while the Miracast module is disabled, which is the switch
     * that is meant to control it.
     */
    private static final int HDMI_KEY = KeyEvent.keyCodeFromString("KEYCODE_PRJ_FOCUS_DN");

    private HomeView view;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        view = new HomeView(this);
        setContentView(view);
    }

    @Override
    protected void onResume() {
        super.onResume();
        view.reload();      // what is installed may have changed while we were away
    }

    @Override
    public boolean onKeyDown(int code, KeyEvent event) {
        switch (code) {
            case KeyEvent.KEYCODE_DPAD_LEFT:
                view.move(-1, 0);
                return true;
            case KeyEvent.KEYCODE_DPAD_RIGHT:
                view.move(1, 0);
                return true;
            case KeyEvent.KEYCODE_DPAD_UP:
                view.move(0, -1);
                return true;
            case KeyEvent.KEYCODE_DPAD_DOWN:
                view.move(0, 1);
                return true;
            case KeyEvent.KEYCODE_DPAD_CENTER:
            case KeyEvent.KEYCODE_ENTER:
                // Opening happens on the way up, so that holding OK can mean something
                // else. Tracking has to be asked for, or onKeyLongPress never fires.
                if (event.getRepeatCount() == 0) {
                    event.startTracking();
                }
                return true;
            case KeyEvent.KEYCODE_MENU:
                // Claimed here so Android does not go looking for an options menu, and
                // acted on when it comes back up, like everything else on this screen.
                return true;
            default:
                return super.onKeyDown(code, event);
        }
    }

    /**
     * Hold OK: the app's own page in Android's settings, which is where its permissions,
     * its storage and its Uninstall button are.
     *
     * This is the only way to reach that page for some of what is installed. Settings
     * lists an app under "See all apps" only if it declares a TV launcher entry, and
     * several ordinary Android apps declare only the phone kind -- Magisk and anything
     * sideloaded from an APK built for phones. Measured on this unit: of nine packages,
     * the five with a TV entry were listed and the four without were not, with no
     * exceptions. The page itself opens for any of them; it is only the list that filters.
     */
    @Override
    public boolean onKeyLongPress(int code, KeyEvent event) {
        if (code == KeyEvent.KEYCODE_DPAD_CENTER || code == KeyEvent.KEYCODE_ENTER) {
            details(view.focused());
            return true;
        }
        return super.onKeyLongPress(code, event);
    }

    @Override
    public boolean onKeyUp(int code, KeyEvent event) {
        if (code == KeyEvent.KEYCODE_DPAD_CENTER || code == KeyEvent.KEYCODE_ENTER) {
            // isTracking goes false once the long press has been handled, so a hold does
            // not also start the app on release.
            if (event.isTracking() && !event.isCanceled()) {
                open(view.focused());
            }
            return true;
        }
        // Both of these arrive on the way up only: the firmware's own handler takes the
        // press for itself before any app sees it, and lets go of the release.
        if (HDMI_KEY != KeyEvent.KEYCODE_UNKNOWN && code == HDMI_KEY) {
            startOwn(new Intent(this, HdmiActivity.class));
            return true;
        }
        if (code == KeyEvent.KEYCODE_MENU) {
            startOwn(new Intent(this, MainActivity.class));
            return true;
        }
        return super.onKeyUp(code, event);
    }

    /** One of ours, started the way a tile of ours is: on this task, not a new one. */
    private void startOwn(Intent intent) {
        try {
            startActivity(intent);
        } catch (Throwable ignored) {
            // a screen that will not open is no reason to take the home screen down
        }
    }

    /** Home is where you already are, so back must not take the screen away. */
    @Override
    public void onBackPressed() {
        // deliberately nothing
    }

    private void open(Item item) {
        if (item == null) {
            return;
        }
        try {
            Intent intent = new Intent(Intent.ACTION_MAIN);
            intent.setClassName(item.packageName, item.activityName);
            if (!getPackageName().equals(item.packageName)) {
                // The flags a launcher owes another app: its own task, brought back to
                // its own first screen. Used on one of ours they do the opposite — this
                // screen is the root of a singleTask task, so resetting it throws away
                // the very activity being started, and the press appears to do nothing.
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK
                        | Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED);
            }
            startActivity(intent);
        } catch (Throwable ignored) {
            // an app that will not start is no reason to take the home screen down
        }
    }

    private void details(Item item) {
        if (item == null) {
            return;
        }
        try {
            Intent intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.fromParts("package", item.packageName, null));
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(intent);
        } catch (Throwable ignored) {
            // no settings app to answer, or it refused: the home screen stays up
        }
    }

    /** One tile: an app, the name under it, and the activity to start for it. */
    static final class Item {
        final String packageName;
        final String activityName;
        final String label;
        final Drawable icon;

        Item(String packageName, String activityName, String label, Drawable icon) {
            this.packageName = packageName;
            this.activityName = activityName;
            this.label = label;
            this.icon = icon;
        }
    }

    /**
     * Every app that can be started, one entry each.
     *
     * Both kinds of launcher entry are asked for: the TV kind Android TV shows, and the
     * ordinary phone kind, which is the only way apps like Magisk reach the screen at all.
     * The TV kind is asked for first, so an app answering to both is kept as its TV entry.
     */
    static Map<String, Item> installed(Context context) {
        PackageManager pm = context.getPackageManager();
        Map<String, Item> byPackage = new LinkedHashMap<String, Item>();
        String[] categories = {Intent.CATEGORY_LEANBACK_LAUNCHER, Intent.CATEGORY_LAUNCHER};
        for (String category : categories) {
            Intent query = new Intent(Intent.ACTION_MAIN);
            query.addCategory(category);
            List<ResolveInfo> found;
            try {
                found = pm.queryIntentActivities(query, 0);
            } catch (Throwable t) {
                continue;
            }
            for (ResolveInfo info : found) {
                String pkg = info.activityInfo.packageName;
                if (byPackage.containsKey(pkg)) {
                    continue;
                }
                byPackage.put(pkg, toItem(pm, info, pkg, info.activityInfo.name));
            }
        }
        return byPackage;
    }

    /** One named activity, for a package that puts more than one tile in the first row. */
    static Item byComponent(PackageManager pm, String pkg, String activity, String label) {
        try {
            ActivityInfo info = pm.getActivityInfo(new ComponentName(pkg, activity), 0);
            Drawable icon = null;
            try {
                icon = info.loadIcon(pm);
            } catch (Throwable ignored) {
                // a tile with no picture still works
            }
            return new Item(pkg, activity, label, icon);
        } catch (Throwable t) {
            return null;        // not installed, so the row is simply one tile shorter
        }
    }

    /** The way in for an app with no launcher entry, such as Android's own settings. */
    static Item byAction(PackageManager pm, String pkg, String action, String label) {
        try {
            ResolveInfo info = pm.resolveActivity(new Intent(action), 0);
            if (info == null || !pkg.equals(info.activityInfo.packageName)) {
                return null;
            }
            return new Item(pkg, info.activityInfo.name, label, toItem(pm, info, pkg, "").icon);
        } catch (Throwable t) {
            return null;
        }
    }

    private static Item toItem(PackageManager pm, ResolveInfo info, String pkg, String activity) {
        CharSequence label = info.loadLabel(pm);
        Drawable icon = null;
        try {
            icon = info.loadIcon(pm);
        } catch (Throwable ignored) {
            // a tile with no picture still works
        }
        return new Item(pkg, activity, label == null ? pkg : label.toString(), icon);
    }

    /** The grid: one row of the projector's own apps, every other app underneath. */
    static final class HomeView extends View {

        static final int COLUMNS = 6;

        private static final String FIRST_HEADING = "Projector and system";
        private static final String SECOND_HEADING = "Apps";

        private final int background = Color.parseColor("#0162B1");
        private final int tileColour = Color.parseColor("#1C74BD");

        /** Row 0 is the projector's own; the rest are the other apps, six to a row. */
        private final List<List<Item>> rows = new ArrayList<List<Item>>();
        private int row = 0;
        private int column = 0;
        private int firstDrawnRow = 1;
        private int firstDrawnColumn = 0;

        private final Paint tile = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint label = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint title = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint heading = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final float density;

        HomeView(Context context) {
            super(context);
            density = context.getResources().getDisplayMetrics().density;
            setFocusable(true);
            setBackgroundColor(background);
            tile.setStyle(Paint.Style.FILL);
            label.setTextAlign(Paint.Align.CENTER);
            title.setTextSize(dp(22));
            title.setColor(Color.WHITE);
            heading.setTextSize(dp(14));
            heading.setColor(Color.parseColor("#AFD4EE"));
        }

        private float dp(float v) {
            return v * density;
        }

        /** Rebuilds both sections from what is installed right now. */
        void reload() {
            Context context = getContext();
            PackageManager pm = context.getPackageManager();
            Map<String, Item> all = installed(context);

            List<Item> system = new ArrayList<Item>();
            for (String[] entry : SYSTEM) {
                String pkg = entry[0];
                String activity = entry[1];
                String name = entry[2];
                String action = entry[3];
                Item item;
                if (activity != null) {
                    item = byComponent(pm, pkg, activity, name);
                } else {
                    item = all.get(pkg);
                    if (item != null) {
                        // The curated row gets the short names the owner chose, not the
                        // apps' own, which run off the end of a tile.
                        item = new Item(item.packageName, item.activityName, name, item.icon);
                    } else if (action != null) {
                        item = byAction(pm, pkg, action, name);
                    }
                }
                if (item != null) {
                    system.add(item);       // one that is missing just shortens the row
                }
            }
            // Whatever the first row claims belongs to it alone, however many tiles it
            // took, so the section below is only ever the apps nobody has placed.
            for (String[] entry : SYSTEM) {
                all.remove(entry[0]);
            }
            for (String pkg : ELSEWHERE) {
                all.remove(pkg);
            }

            List<Item> others = new ArrayList<Item>(all.values());
            Collections.sort(others, new Comparator<Item>() {
                @Override
                public int compare(Item a, Item b) {
                    return a.label.compareToIgnoreCase(b.label);
                }
            });

            rows.clear();
            rows.add(system);
            for (int i = 0; i < others.size(); i += COLUMNS) {
                rows.add(new ArrayList<Item>(
                        others.subList(i, Math.min(i + COLUMNS, others.size()))));
            }
            clampFocus();
            invalidate();
        }

        Item focused() {
            if (rows.isEmpty() || row >= rows.size()) {
                return null;
            }
            List<Item> here = rows.get(row);
            return column < here.size() ? here.get(column) : null;
        }

        /** Steps around, wrapping top to bottom, and never onto an empty slot. */
        void move(int acrossBy, int downBy) {
            if (rows.isEmpty()) {
                return;
            }
            if (downBy != 0) {
                int wanted = column;
                for (int step = 0; step < rows.size(); step++) {
                    row = (row + downBy + rows.size()) % rows.size();
                    if (!rows.get(row).isEmpty()) {
                        break;
                    }
                }
                column = Math.min(wanted, Math.max(0, rows.get(row).size() - 1));
            }
            if (acrossBy != 0) {
                int width = rows.get(row).size();
                if (width > 0) {
                    column = (column + acrossBy + width) % width;
                }
            }
            clampFocus();
            invalidate();
        }

        private void clampFocus() {
            if (rows.isEmpty()) {
                return;
            }
            row = Math.max(0, Math.min(row, rows.size() - 1));
            column = Math.max(0, Math.min(column, Math.max(0, rows.get(row).size() - 1)));
        }

        @Override
        protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            if (rows.isEmpty()) {
                return;
            }
            float w = getWidth();
            float h = getHeight();
            float margin = dp(40);
            float gap = dp(16);
            float side = (w - margin * 2 - gap * (COLUMNS - 1)) / COLUMNS;
            float headingGap = dp(26);

            canvas.drawText("HY320 Projector", margin, dp(44), title);
            label.setTextSize(side * 0.115f);

            float top = dp(72);
            float firstSection = headingGap + side + dp(22);
            float room = h - top - firstSection - headingGap - dp(20);
            int visible = Math.max(1, (int) ((room + gap) / (side + gap)));

            // The view follows the focus rather than drawing off the bottom of the screen.
            if (row == 0) {
                firstDrawnRow = 1;
            } else if (row < firstDrawnRow) {
                firstDrawnRow = row;
            } else if (row > firstDrawnRow + visible - 1) {
                firstDrawnRow = row - visible + 1;
            }

            // The first row never wraps onto a second: it slides sideways under the focus,
            // so however many tiles are pinned there it stays the one row it is meant to be.
            int firstWidth = rows.get(0).size();
            if (row == 0) {
                if (column < firstDrawnColumn) {
                    firstDrawnColumn = column;
                } else if (column > firstDrawnColumn + COLUMNS - 1) {
                    firstDrawnColumn = column - COLUMNS + 1;
                }
            }
            firstDrawnColumn = Math.max(0,
                    Math.min(firstDrawnColumn, Math.max(0, firstWidth - COLUMNS)));

            float y = top;
            canvas.drawText(FIRST_HEADING, margin, y + dp(11), heading);
            y += headingGap;
            drawRow(canvas, rows.get(0), 0, firstDrawnColumn, margin, y, side, gap);
            y += side + dp(22);

            canvas.drawText(SECOND_HEADING, margin, y + dp(11), heading);
            y += headingGap;
            for (int r = firstDrawnRow; r < rows.size() && r < firstDrawnRow + visible; r++) {
                drawRow(canvas, rows.get(r), r, 0, margin, y, side, gap);
                y += side + gap;
            }
        }

        private void drawRow(Canvas canvas, List<Item> items, int r, int from,
                             float margin, float y, float side, float gap) {
            for (int slot = 0; slot < COLUMNS && from + slot < items.size(); slot++) {
                int c = from + slot;
                Item item = items.get(c);
                boolean on = r == row && c == column;
                float left = margin + slot * (side + gap);
                RectF box = new RectF(left, y, left + side, y + side);
                tile.setColor(on ? Color.WHITE : tileColour);
                canvas.drawRoundRect(box, dp(14), dp(14), tile);

                if (item.icon != null) {
                    float picture = side * 0.46f;
                    float cx = box.centerX();
                    float iconTop = box.top + side * 0.17f;
                    item.icon.setBounds(new Rect((int) (cx - picture / 2), (int) iconTop,
                            (int) (cx + picture / 2), (int) (iconTop + picture)));
                    item.icon.draw(canvas);
                }
                label.setColor(on ? background : Color.WHITE);
                canvas.drawText(shorten(item.label, side), box.centerX(),
                        box.top + side * 0.84f, label);
            }
        }

        /** Keeps a long app name inside its own tile rather than over its neighbours. */
        private String shorten(String text, float side) {
            float room = side * 0.86f;
            if (label.measureText(text) <= room) {
                return text;
            }
            for (int end = text.length() - 1; end > 1; end--) {
                String tried = text.substring(0, end) + "…";
                if (label.measureText(tried) <= room) {
                    return tried;
                }
            }
            return text;
        }
    }
}
