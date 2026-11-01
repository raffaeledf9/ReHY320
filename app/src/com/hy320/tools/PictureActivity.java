package com.hy320.tools;

import android.app.Activity;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.os.Bundle;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.TextView;

/**
 * Brightness, contrast, saturation, hue and colour temperature.
 *
 * These go straight to the projector's display service, which answers an ordinary app, so
 * this screen needs no superuser and keeps working if root is ever removed. Each change
 * shows at once.
 *
 * Colour temperature is a mode number rather than a percentage, and which number is which
 * mode is not written down anywhere, so it shows the raw value and is found by trying.
 *
 * Each row is laid out in columns -- name, bar, value -- rather than padded text, because
 * the writing is not monospaced and padded text does not line up.
 */
public class PictureActivity extends Activity {

    private static final String[] NAMES = {
            "Brightness", "Contrast", "Saturation", "Hue", "Colour temperature"};
    private static final int[] IDS = {
            Picture.BRIGHTNESS, Picture.CONTRAST, Picture.SATURATION, Picture.HUE,
            Picture.COLOUR_TEMPERATURE};
    /** The first four run from 0 to 100; colour temperature is a small mode number. */
    private static final int[] MOST = {100, 100, 100, 100, Picture.MOST_TEMPERATURE};
    private static final int[] STEP = {2, 2, 2, 2, 1};

    private static final int BACKGROUND = Color.parseColor("#0162B1");
    private static final int DIM = Color.parseColor("#AFD3F2");
    private static final int TROUBLE = Color.parseColor("#FF8A80");

    private final int[] values = new int[IDS.length];
    private final TextView[] names = new TextView[IDS.length];
    private final TextView[] readings = new TextView[IDS.length];
    private final Bar[] bars = new Bar[IDS.length];

    private int row = 0;
    private boolean refused = false;
    private TextView hint;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        for (int i = 0; i < IDS.length; i++) {
            values[i] = Picture.get(IDS[i], defaultFor(i));
        }

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(BACKGROUND);
        root.setPadding(pad(64), pad(44), pad(64), pad(36));

        // The settings sit in the middle of the picture, with the help pinned at the foot,
        // so the screen does not look top-heavy on a wide projection.
        LinearLayout middle = new LinearLayout(this);
        middle.setOrientation(LinearLayout.VERTICAL);
        middle.setGravity(Gravity.CENTER);
        middle.setLayoutParams(new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        TextView head = text(28, Color.WHITE);
        head.setText("Picture");
        head.setGravity(Gravity.CENTER_HORIZONTAL);
        head.setPadding(0, 0, 0, pad(30));
        middle.addView(head);

        for (int i = 0; i < IDS.length; i++) {
            LinearLayout line = new LinearLayout(this);
            line.setOrientation(LinearLayout.HORIZONTAL);
            line.setGravity(Gravity.CENTER_VERTICAL);
            line.setPadding(0, pad(9), 0, pad(9));

            names[i] = text(20, DIM);
            names[i].setText(NAMES[i]);
            names[i].setLayoutParams(new LinearLayout.LayoutParams(pad(230), ViewGroup.LayoutParams.WRAP_CONTENT));
            line.addView(names[i]);

            bars[i] = new Bar(this);
            bars[i].setLayoutParams(new LinearLayout.LayoutParams(pad(360), pad(14)));
            line.addView(bars[i]);

            readings[i] = text(20, DIM);
            readings[i].setGravity(Gravity.END);
            readings[i].setLayoutParams(new LinearLayout.LayoutParams(pad(110), ViewGroup.LayoutParams.WRAP_CONTENT));
            line.addView(readings[i]);

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

    private static int defaultFor(int i) {
        return IDS[i] == Picture.COLOUR_TEMPERATURE
                ? Picture.DEFAULT_TEMPERATURE : Picture.DEFAULT_LEVEL;
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
                return change(-STEP[row]);
            case KeyEvent.KEYCODE_DPAD_RIGHT:
                return change(STEP[row]);
            case KeyEvent.KEYCODE_MENU:
                for (int i = 0; i < IDS.length; i++) {
                    values[i] = defaultFor(i);
                    refused |= !Picture.set(IDS[i], values[i]);
                }
                redraw();
                return true;
            default:
                return super.onKeyDown(code, event);
        }
    }

    private boolean change(int delta) {
        int next = Math.max(0, Math.min(MOST[row], values[row] + delta));
        if (next != values[row]) {
            values[row] = next;
            refused |= !Picture.set(IDS[row], next);
        }
        redraw();
        return true;
    }

    private void redraw() {
        for (int i = 0; i < IDS.length; i++) {
            boolean here = i == row;
            int colour = here ? Color.WHITE : DIM;
            names[i].setTextColor(colour);
            readings[i].setTextColor(colour);
            readings[i].setText(IDS[i] == Picture.COLOUR_TEMPERATURE
                    ? "mode " + values[i] + " of " + Picture.MOST_TEMPERATURE
                    : values[i] + "%");
            bars[i].set(values[i] / (float) MOST[i], here);
        }
        hint.setText(refused
                ? "This projector refused the change, so the picture cannot be set from here."
                : "Up and down: choose a setting      Left and right: change it      "
                + "Menu: all back to default\n"
                + "Colour temperature has three modes: try them and keep the one that looks "
                + "right.");
        hint.setTextColor(refused ? TROUBLE : DIM);
    }

    /** One level, drawn as a track with the filled part over it. */
    private static final class Bar extends View {

        private final Paint track = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint fill = new Paint(Paint.ANTI_ALIAS_FLAG);
        private float part = 0f;

        Bar(Context context) {
            super(context);
            track.setStyle(Paint.Style.FILL);
            fill.setStyle(Paint.Style.FILL);
            set(0f, false);
        }

        void set(float part, boolean chosen) {
            this.part = Math.max(0f, Math.min(1f, part));
            track.setColor(chosen ? Color.parseColor("#2A7FC4") : Color.parseColor("#1E6FB4"));
            fill.setColor(chosen ? Color.WHITE : DIM);
            invalidate();
        }

        @Override
        protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            float h = getHeight();
            float r = h / 2;
            canvas.drawRoundRect(new RectF(0, 0, getWidth(), h), r, r, track);
            if (part > 0) {
                float w = Math.max(h, getWidth() * part);
                canvas.drawRoundRect(new RectF(0, 0, w, h), r, r, fill);
            }
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
