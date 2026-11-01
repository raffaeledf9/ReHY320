package com.hy320.tools;

import android.app.Activity;
import android.graphics.Color;
import android.os.Bundle;
import android.util.TypedValue;
import android.view.KeyEvent;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.TextView;

/**
 * How the picture is thrown: front or rear, upright or hanging from the ceiling.
 *
 * Proved on the projector on 2026-10-24: the compositor reads `persist.sys.projection`
 * when it starts, and nothing else applies it -- writing the property alone changes
 * nothing, and setting it to 1 and restarting the compositor flipped the picture. So this
 * screen writes the value and restarts the compositor, which blanks the picture for a few
 * seconds and brings it back the new way round. That is said plainly on screen, because
 * unlike keystone it cannot be done live.
 *
 * The vendor's own settings app keeps a second copy in `persist.sys.projection.position`,
 * so that is written too, to leave the projector's own records consistent.
 *
 * The four values it uses are 0, 1, 3 and 2. Which one is which orientation is not written
 * down anywhere, so the raw value is shown beside each name and the right one is found by
 * trying it on the wall.
 */
public class ProjectionActivity extends Activity {

    private static final String PROPERTY = "persist.sys.projection";
    private static final String VENDOR_COPY = "persist.sys.projection.position";
    private static final int[] VALUES = {0, 1, 3, 2};
    private static final String[] NAMES = {
            "front, upright", "front, ceiling", "rear, upright", "rear, ceiling"};

    private int index = 0;
    private boolean refused = false;
    private boolean applying = false;
    private TextView[] rows;
    private TextView hint;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        int current = Props.getInt(PROPERTY, 0);
        for (int i = 0; i < VALUES.length; i++) {
            if (VALUES[i] == current) {
                index = i;
            }
        }
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.parseColor("#0162B1"));
        root.setPadding(pad(48), pad(40), pad(48), pad(40));
        TextView head = text(26);
        head.setText("Projection");
        head.setTextColor(Color.WHITE);
        head.setPadding(0, 0, 0, pad(24));
        root.addView(head);
        rows = new TextView[VALUES.length];
        for (int i = 0; i < VALUES.length; i++) {
            rows[i] = text(20);
            root.addView(rows[i]);
        }
        hint = text(15);
        hint.setPadding(0, pad(28), 0, 0);
        root.addView(hint);
        setContentView(root);
        redraw();
    }

    @Override
    public boolean onKeyDown(int code, KeyEvent event) {
        switch (code) {
            case KeyEvent.KEYCODE_DPAD_UP:
                index = (index + VALUES.length - 1) % VALUES.length;
                redraw();
                return true;
            case KeyEvent.KEYCODE_DPAD_DOWN:
                index = (index + 1) % VALUES.length;
                redraw();
                return true;
            case KeyEvent.KEYCODE_DPAD_CENTER:
            case KeyEvent.KEYCODE_ENTER:
                apply();
                return true;
            default:
                return super.onKeyDown(code, event);
        }
    }

    /**
     * Writes the value and restarts the compositor so it takes it up. The picture goes
     * dark for a few seconds and comes back; this screen goes away with it.
     */
    private void apply() {
        if (applying) {
            return;
        }
        String value = String.valueOf(VALUES[index]);
        refused = !Props.set(PROPERTY, value);
        Props.set(VENDOR_COPY, value);
        if (!refused) {
            applying = true;
            redraw();
            Keystone.applyByRestart();
        } else {
            redraw();
        }
    }

    private void redraw() {
        int current = Props.getInt(PROPERTY, 0);
        for (int i = 0; i < rows.length; i++) {
            boolean selected = i == index;
            boolean active = VALUES[i] == current;
            rows[i].setText(String.format("%s %-18s (value %d)%s",
                    selected ? "▸" : "  ", NAMES[i], VALUES[i], active ? "   in use" : ""));
            rows[i].setTextColor(selected ? Color.WHITE
                    : active ? Color.parseColor("#B3D9FF") : Color.parseColor("#9FC4E8"));
        }
        hint.setText(refused
                ? "This projector refused the change, so it cannot be set from this app."
                : applying
                ? "Applying: the picture goes dark for a few seconds and comes back."
                : "Up and down: choose   Centre: apply   Back: leave\n"
                + "Applying blanks the picture for a few seconds, because the projector only "
                + "reads this when its display starts.\n"
                + "If a name does not match what you see, try each value and keep the right one.");
        hint.setTextColor(refused ? Color.parseColor("#FF8A80") : Color.WHITE);
    }

    private TextView text(int sp) {
        TextView t = new TextView(this);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp);
        t.setTextColor(Color.WHITE);
        t.setLayoutParams(new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        t.setPadding(0, pad(6), 0, pad(6));
        return t;
    }

    private int pad(int dp) {
        return (int) (dp * getResources().getDisplayMetrics().density);
    }
}
