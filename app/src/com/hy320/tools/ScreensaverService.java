package com.hy320.tools;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.service.dreams.DreamService;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.TextView;

import java.io.File;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

/**
 * What the projector shows when it has been idle.
 *
 * In practice it shows nothing, and that is the point: this dream exists so that standby
 * can happen at all. The firmware cuts the lamp the moment Android starts dreaming, so a
 * dream is the only thing that puts this projector to sleep, and dreams must stay enabled
 * for that reason. What it must not do is hold the screen bright, which would stop the
 * very sleep it is there to begin. See onAttachedToWindow.
 *
 * The clock and the optional picture below are kept for a projector that behaves
 * differently, or for a later firmware. On this one they are never seen.
 *
 * Replacing the picture needs no tools: copy a file into that folder with the file manager
 * or from a USB stick, and name it screensaver.jpg.
 */
public class ScreensaverService extends DreamService {

    private static final String FILE_NAME = "screensaver.jpg";
    private static final long CLOCK_STEP_MS = 30_000L;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private TextView clock;
    private Runnable tick;

    @Override
    public void onAttachedToWindow() {
        super.onAttachedToWindow();
        setInteractive(false);
        setFullscreen(true);
        // Dimmed, deliberately, though it means nothing is shown at all.
        //
        // Asking for a bright dream takes a SCREEN_BRIGHT_WAKE_LOCK, and on this projector
        // that holds the display powered, so the firmware never cuts the lamp and standby
        // simply does not arrive. Measured on 2026-10-25: dreaming for 469 seconds against
        // a 300-second timeout, with the lock held by this very service.
        //
        // I had set it bright so the clock below could be seen. That was the wrong trade:
        // the projector has no screen saver worth the name -- the firmware kills the lamp
        // the moment it dreams -- and what it does have is standby, announced a minute
        // ahead by WarningActivity. Keeping the lamp alight to show a clock nobody asked
        // for cost the standby everybody did.
        setScreenBright(false);

        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(Color.BLACK);

        Bitmap picture = loadPicture();
        if (picture != null) {
            ImageView image = new ImageView(this);
            image.setImageBitmap(picture);
            image.setScaleType(ImageView.ScaleType.FIT_CENTER);
            root.addView(image, new FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        } else {
            clock = new TextView(this);
            clock.setTextSize(TypedValue.COMPLEX_UNIT_SP, 64);
            clock.setTextColor(Color.WHITE);
            clock.setGravity(Gravity.CENTER);
            FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            lp.gravity = Gravity.CENTER;
            root.addView(clock, lp);
            showTime();
        }
        setContentView(root);
    }

    @Override
    public void onDetachedFromWindow() {
        if (tick != null) {
            handler.removeCallbacks(tick);
            tick = null;
        }
        super.onDetachedFromWindow();
    }

    /** The user's own picture, if they put one there and it can be read. */
    private Bitmap loadPicture() {
        try {
            File f = new File(Environment.getExternalStoragePublicDirectory(
                    Environment.DIRECTORY_PICTURES), FILE_NAME);
            if (!f.isFile() || !f.canRead()) {
                return null;
            }
            BitmapFactory.Options o = new BitmapFactory.Options();
            o.inPreferredConfig = Bitmap.Config.RGB_565;   // 1 GB of memory, so be frugal
            return BitmapFactory.decodeFile(f.getAbsolutePath(), o);
        } catch (Throwable t) {
            return null;
        }
    }

    private void showTime() {
        clock.setText(new SimpleDateFormat("HH:mm", Locale.getDefault()).format(new Date()));
        tick = new Runnable() {
            @Override
            public void run() {
                showTime();
            }
        };
        handler.postDelayed(tick, CLOCK_STEP_MS);
    }
}
