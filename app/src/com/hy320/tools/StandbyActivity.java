package com.hy320.tools;

import android.app.Activity;
import android.graphics.Color;
import android.os.Bundle;
import android.provider.Settings;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.TextView;

/**
 * When the picture gives way to the screen saver.
 *
 * This projector has two timers for the same thing: the firmware's own, in a pair of
 * properties, and Android's, in its settings. Whichever is shorter wins, so this screen
 * sets both to the same value and says plainly if it could not set Android's -- which
 * needs a permission a person grants once, in Android's own settings.
 *
 * Laid out like the picture screen: columns rather than padded text, the settings in the
 * middle and the help at the foot.
 */
public class StandbyActivity extends Activity {

    private static final String ENABLE = "persist.sys.screendream.enable";
    private static final String TIME = "persist.sys.screendream.time";
    /*
     * Android's sleep timeout matters as much as this one -- without it the projector
     * dreams for ever and never goes dark -- but it is a Secure setting, which needs a
     * signature permission no ordinary app can hold. The watcher in the Magisk module
     * keeps it in step with whatever is chosen here, because it runs as root.
     */
    /** Every five minutes up to an hour. */
    private static final int[] MINUTES = {5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60};

    private static final int BACKGROUND = Color.parseColor("#0162B1");
    private static final int DIM = Color.parseColor("#AFD3F2");
    private static final int TROUBLE = Color.parseColor("#FF8A80");

    private static final String[] NAMES = {"Screen saver", "Start it after"};

    private int row = 0;
    private String trouble = null;

    private final TextView[] names = new TextView[NAMES.length];
    private final TextView[] readings = new TextView[NAMES.length];
    private Toggle toggle;
    private TextView hint;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(BACKGROUND);
        root.setPadding(pad(64), pad(44), pad(64), pad(36));

        LinearLayout middle = new LinearLayout(this);
        middle.setOrientation(LinearLayout.VERTICAL);
        middle.setGravity(Gravity.CENTER);
        middle.setLayoutParams(new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        TextView head = text(28, Color.WHITE);
        head.setText("Screen saver");
        head.setGravity(Gravity.CENTER_HORIZONTAL);
        head.setPadding(0, 0, 0, pad(30));
        middle.addView(head);

        for (int i = 0; i < NAMES.length; i++) {
            LinearLayout line = new LinearLayout(this);
            line.setOrientation(LinearLayout.HORIZONTAL);
            line.setGravity(Gravity.CENTER_VERTICAL);
            line.setPadding(0, pad(11), 0, pad(11));

            names[i] = text(20, DIM);
            names[i].setText(NAMES[i]);
            names[i].setLayoutParams(new LinearLayout.LayoutParams(
                    pad(260), ViewGroup.LayoutParams.WRAP_CONTENT));
            line.addView(names[i]);

            if (i == 0) {
                toggle = new Toggle(this);
                LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(pad(58), pad(30));
                p.gravity = Gravity.CENTER_VERTICAL;
                toggle.setLayoutParams(p);
                line.addView(toggle);
                readings[i] = text(20, DIM);   // kept for colouring, shown empty
                readings[i].setLayoutParams(new LinearLayout.LayoutParams(
                        pad(162), ViewGroup.LayoutParams.WRAP_CONTENT));
                line.addView(readings[i]);
            } else {
                readings[i] = text(20, DIM);
                readings[i].setLayoutParams(new LinearLayout.LayoutParams(
                        pad(220), ViewGroup.LayoutParams.WRAP_CONTENT));
                line.addView(readings[i]);
            }

            line.setLayoutParams(new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));
            middle.addView(line);
        }
        root.addView(middle);

        hint = text(14, DIM);
        hint.setGravity(Gravity.CENTER_HORIZONTAL);
        hint.setPadding(0, pad(20), 0, 0);
        hint.setLineSpacing(pad(5), 1f);
        root.addView(hint);

        setContentView(root);
        redraw();
    }

    private boolean on() {
        return !"false".equals(Props.get(ENABLE, "true"));
    }

    /** The closest offered value to what the firmware currently holds. */
    private int minutesIndex() {
        int ms = Props.getInt(TIME, 30 * 60000);
        int best = 0;
        for (int i = 1; i < MINUTES.length; i++) {
            if (Math.abs(MINUTES[i] * 60000 - ms) < Math.abs(MINUTES[best] * 60000 - ms)) {
                best = i;
            }
        }
        return best;
    }

    @Override
    public boolean onKeyDown(int code, KeyEvent event) {
        switch (code) {
            case KeyEvent.KEYCODE_DPAD_UP:
                row = (row + NAMES.length - 1) % NAMES.length;
                redraw();
                return true;
            case KeyEvent.KEYCODE_DPAD_DOWN:
                row = (row + 1) % NAMES.length;
                redraw();
                return true;
            case KeyEvent.KEYCODE_DPAD_LEFT:
                change(-1);
                return true;
            case KeyEvent.KEYCODE_DPAD_RIGHT:
            case KeyEvent.KEYCODE_DPAD_CENTER:
            case KeyEvent.KEYCODE_ENTER:
                change(1);
                return true;
            default:
                return super.onKeyDown(code, event);
        }
    }

    private void change(int direction) {
        trouble = null;
        if (row == 0) {
            if (!Props.set(ENABLE, on() ? "false" : "true")) {
                trouble = "The projector refused to turn the screen saver on or off.";
            }
        } else {
            int next = (minutesIndex() + direction + MINUTES.length) % MINUTES.length;
            int ms = MINUTES[next] * 60000;
            if (!Props.set(TIME, String.valueOf(ms))) {
                trouble = "The projector refused the new time.";
            }
            try {
                Settings.System.putInt(getContentResolver(), Settings.System.SCREEN_OFF_TIMEOUT, ms);
            } catch (Throwable t) {
                trouble = "Set in the projector's own timer, but Android's needs permission: "
                        + "Android settings, apps, special access, modify system settings.";
            }
        }
        redraw();
    }

    private void redraw() {
        int android = -1;
        try {
            android = Settings.System.getInt(getContentResolver(), Settings.System.SCREEN_OFF_TIMEOUT);
        } catch (Throwable ignored) {
            // shown as a mismatch below, which is the honest thing to show
        }
        int minutes = MINUTES[minutesIndex()];
        toggle.set(on(), row == 0);
        readings[0].setText("");
        readings[1].setText(minutes + " minutes"
                + (android > 0 && android != minutes * 60000
                        ? "   (Android: " + android / 60000 + ")" : ""));
        for (int i = 0; i < NAMES.length; i++) {
            int colour = i == row ? Color.WHITE : DIM;
            names[i].setTextColor(colour);
            readings[i].setTextColor(colour);
        }
        hint.setText(trouble != null ? trouble
                : "Up and down: choose      Left and right: change      Back: leave\n"
                + "The picture shown is set by putting a file named screensaver.jpg in the "
                + "shared Pictures folder.");
        hint.setTextColor(trouble != null ? TROUBLE : DIM);
    }

    /** A switch, drawn rather than borrowed, so it matches the rest of these screens. */
    private static final class Toggle extends android.view.View {

        private final android.graphics.Paint paint =
                new android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG);
        private boolean on = false;
        private boolean chosen = false;

        Toggle(android.content.Context context) {
            super(context);
            paint.setStyle(android.graphics.Paint.Style.FILL);
        }

        void set(boolean on, boolean chosen) {
            this.on = on;
            this.chosen = chosen;
            invalidate();
        }

        @Override
        protected void onDraw(android.graphics.Canvas canvas) {
            super.onDraw(canvas);
            float w = getWidth();
            float h = getHeight();
            float r = h / 2;
            paint.setColor(on
                    ? (chosen ? Color.WHITE : DIM)
                    : Color.parseColor(chosen ? "#2A7FC4" : "#1E6FB4"));
            canvas.drawRoundRect(new android.graphics.RectF(0, 0, w, h), r, r, paint);
            paint.setColor(on ? BACKGROUND : (chosen ? Color.WHITE : DIM));
            canvas.drawCircle(on ? w - r : r, r, r * 0.68f, paint);
        }
    }

    private TextView text(int sp, int colour) {
        TextView t = new TextView(this);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp);
        t.setTextColor(colour);
        return t;
    }

    private int pad(int dp) {
        return (int) (dp * getResources().getDisplayMetrics().density);
    }
}
