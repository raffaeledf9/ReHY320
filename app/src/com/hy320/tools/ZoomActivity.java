package com.hy320.tools;

import android.app.Activity;
import android.graphics.Color;
import android.os.Bundle;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;
import android.util.TypedValue;
import android.view.KeyEvent;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.TextView;

/**
 * Screen zoom: shrinks the whole picture, for fitting it inside a wall or a screen.
 *
 * On this projector zoom is not a thing of its own. The only geometry the firmware has is
 * the four keystone corners, and what the vendor's own settings app calls
 * persist.sys.zoom.value turns out to hold a comma-separated copy of those eight corner
 * numbers, not a zoom level. So shrinking the picture means moving all four corners inward
 * together, which is exactly what this screen does -- and because it adds to each corner,
 * any keystone correction already set is preserved.
 *
 * Applying goes the same way as the keystone screen: through superuser to the compositor,
 * which is the only route it accepts.
 */
public class ZoomActivity extends Activity {

    /** How much one press moves every corner. */
    private static final int STEP = 2;

    private boolean refused = false;
    private boolean notLive = false;
    private TextView value;
    private TextView bar;
    private TextView hint;

    private HandlerThread worker;
    private Handler background;
    private final Handler ui = new Handler(Looper.getMainLooper());
    private volatile boolean dirty = false;
    private volatile boolean scheduled = false;
    private volatile boolean applying = false;

    private final Runnable applyNow = new Runnable() {
        @Override
        public void run() {
            scheduled = false;
            applying = true;
            boolean ok = true;
            while (dirty) {
                dirty = false;
                ok = Keystone.apply();
                if (!ok) {
                    break;
                }
            }
            applying = false;
            final boolean live = ok;
            ui.post(new Runnable() {
                @Override
                public void run() {
                    notLive = !live;
                    redraw();
                }
            });
        }
    };

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        Keystone.load();
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.parseColor("#0162B1"));
        root.setPadding(pad(48), pad(40), pad(48), pad(40));
        TextView head = text(26);
        head.setText("Screen zoom");
        head.setTextColor(Color.WHITE);
        head.setPadding(0, 0, 0, pad(24));
        root.addView(head);
        value = text(22);
        root.addView(value);
        bar = text(20);
        root.addView(bar);
        hint = text(15);
        hint.setPadding(0, pad(28), 0, 0);
        root.addView(hint);
        setContentView(root);
        worker = new HandlerThread("zoom-apply");
        worker.start();
        background = new Handler(worker.getLooper());
        redraw();
    }

    @Override
    protected void onPause() {
        super.onPause();
        background.post(new Runnable() {
            @Override
            public void run() {
                Keystone.save();
            }
        });
    }

    @Override
    protected void onDestroy() {
        background.removeCallbacks(applyNow);
        background.post(new Runnable() {
            @Override
            public void run() {
                Compositor.done();
            }
        });
        worker.quitSafely();
        super.onDestroy();
    }

    @Override
    public boolean onKeyDown(int code, KeyEvent event) {
        switch (code) {
            case KeyEvent.KEYCODE_DPAD_LEFT:
                return change(STEP);         // smaller: corners move inward
            case KeyEvent.KEYCODE_DPAD_RIGHT:
                return change(-STEP);        // bigger: corners move back out
            case KeyEvent.KEYCODE_MENU:
                refused |= !Keystone.reset();
                changed();
                return true;
            default:
                return super.onKeyDown(code, event);
        }
    }

    private boolean change(int inward) {
        if (applying || scheduled) {
            return true;    // the picture is still catching up; do not run ahead of it
        }
        if (Keystone.zoom(inward)) {
            changed();
        }
        return true;
    }

    private void changed() {
        dirty = true;
        redraw();
        if (!scheduled) {
            scheduled = true;
            background.post(applyNow);
        }
    }

    private void redraw() {
        int percent = 100 - Math.round(Keystone.zoomAmount() * 100f / Keystone.LIMIT);
        value.setText(percent + "% of the full picture");
        value.setTextColor(Color.WHITE);
        int filled = Math.max(0, Math.min(20, Math.round(percent * 20f / 100f)));
        StringBuilder sb = new StringBuilder("  ");
        for (int i = 0; i < 20; i++) {
            sb.append(i < filled ? '█' : '░');
        }
        bar.setText(sb);
        bar.setTextColor(Color.WHITE);
        hint.setText(refused
                ? "This projector refused the change, so zoom is not available here."
                : notLive
                ? "Saved, but it will only show once the projector restarts."
                : "Left: smaller   Right: bigger   Menu: back to the full picture   Back: leave\n"
                + "This moves all four corners together, so any keystone correction is kept.");
        hint.setTextColor(refused || notLive ? Color.parseColor("#FF8A80") : Color.WHITE);
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
