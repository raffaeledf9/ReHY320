package com.hy320.tools;

import android.app.Activity;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.graphics.Color;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

/**
 * Says that the projector is about to go to standby.
 *
 * It is an ordinary screen, not a screen saver: this projector powers its lamp down the
 * moment Android starts dreaming, so a dream would announce the dark by going dark.
 *
 * It is put on screen by the watcher in the Magisk module, one minute before the standby
 * the display timeout will cause. Showing it does not count as using the projector --
 * checked on 2026-10-25, where launching a screen left `mLastUserActivityTime` untouched
 * while a single keypress moved it -- so this does not postpone the sleep it announces.
 *
 * Any key closes it, and that keypress is real input, so it also puts standby off for
 * another full timeout. It closes itself the moment standby begins, so nobody wakes the
 * projector to find a stale warning on the wall: the key that wakes it goes to the dream,
 * not to this screen, so it cannot close it. Seen on 2026-10-27, woken 11 s into standby
 * with the warning still up. The 70 s timer stays as a fallback.
 */
public class WarningActivity extends Activity {

    /** Long enough to outlast the minute it announces, short enough not to linger. */
    private static final long CLOSE_AFTER_MS = 70_000L;

    /** Standby has begun: the dream starts, and with it the lamp goes out. */
    private final BroadcastReceiver asleep = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            finish();
        }
    };

    private final Handler handler = new Handler(Looper.getMainLooper());
    private TextView clock;
    private final Runnable tick = new Runnable() {
        @Override
        public void run() {
            showTime();
        }
    };
    private final Runnable close = new Runnable() {
        @Override
        public void run() {
            finish();
        }
    };

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER);
        root.setBackgroundColor(Color.BLACK);

        clock = new TextView(this);
        clock.setTextColor(Color.WHITE);
        clock.setTextSize(TypedValue.COMPLEX_UNIT_SP, 64);
        clock.setGravity(Gravity.CENTER);
        clock.setPadding(0, 0, 0, (int) (18 * getResources().getDisplayMetrics().density));
        root.addView(clock, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        TextView message = new TextView(this);
        message.setText("Going to sleep in 1 minute…");
        message.setTextColor(Color.WHITE);
        message.setTextSize(TypedValue.COMPLEX_UNIT_SP, 34);
        message.setGravity(Gravity.CENTER);
        root.addView(message, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        TextView note = new TextView(this);
        note.setText("Press any key to stay awake");
        note.setTextColor(Color.parseColor("#9E9E9E"));
        note.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
        note.setGravity(Gravity.CENTER);
        note.setPadding(0, (int) (24 * getResources().getDisplayMetrics().density), 0, 0);
        root.addView(note, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        setContentView(root);
        showTime();
        handler.postDelayed(close, CLOSE_AFTER_MS);

        IntentFilter standby = new IntentFilter(Intent.ACTION_DREAMING_STARTED);
        standby.addAction(Intent.ACTION_SCREEN_OFF);
        registerReceiver(asleep, standby);
    }

    /** The time, to the second, so it is plainly a live clock rather than a picture. */
    private void showTime() {
        clock.setText(new SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(new Date()));
        handler.postDelayed(tick, 1000L);
    }

    @Override
    public boolean onKeyDown(int code, KeyEvent event) {
        finish();
        return true;
    }

    @Override
    protected void onDestroy() {
        try {
            unregisterReceiver(asleep);
        } catch (IllegalArgumentException ignored) {
            // never registered: onCreate did not get that far
        }
        handler.removeCallbacks(tick);
        handler.removeCallbacks(close);
        super.onDestroy();
    }
}
