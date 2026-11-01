package com.hy320.tools;

import android.app.Activity;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.os.Bundle;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;
import android.os.SystemClock;
import android.view.KeyEvent;
import android.view.View;

/**
 * Corner-by-corner keystone correction.
 *
 * The projector applies the real correction in its compositor, and the compositor only
 * accepts a live change from the system itself -- the vendor's own settings app can do it
 * because it runs as the system; an ordinary app cannot, and this one is refused. What it
 * can do is save the values and have them taken up when the compositor next starts.
 *
 * With superuser the change is applied the moment it is made, so the whole projected
 * picture moves as the arrows are pressed, exactly as the vendor's own screen does. The
 * frame drawn here stays square on purpose: the projector is already warping everything on
 * screen, so the frame shows the correction by being warped with it.
 *
 * Without superuser the values are still saved and applied when the compositor next
 * starts; the screen says so, and restarts it once on the way out.
 *
 * OK moves to the next corner, the arrows move it, holding OK puts all four back.
 */
public class KeystoneActivity extends Activity {

    /**
     * How late a key event may be and still count.
     *
     * Holding an arrow produces twenty events a second. If this screen is held up for a
     * moment, those events wait in the queue and are then delivered all at once, which
     * lands as a sudden jump on what felt like a single press some time later. Anything
     * older than this is dropped: live pressing is unaffected, a delivered backlog is not
     * acted on twice.
     */
    private static final long STALE_MS = 120;

    /**
     * How long an arrow must be held, without a break, before it starts sliding.
     *
     * Measured on this remote: repeats begin 400 ms after a press and then arrive every
     * 50 ms. Anything shorter than this counts as a tap and moves exactly one step.
     */
    private static final long HOLD_MS = 600;

    /**
     * The longest gap between two events that still counts as the same press.
     *
     * Tapping quickly loses the key-up in between, so the next tap arrives marked as a
     * repeat of the first and carries its old press time -- which is how a burst of taps
     * was being taken for a hold. A real hold arrives as a steady stream 50 ms apart,
     * while tapping leaves bigger gaps, so the gap is what tells them apart. Anything
     * slower than this starts a fresh press however it is labelled.
     */
    private static final long GAP_MS = 90;

    /**
     * How far one step of a slide moves a corner.
     *
     * Applying costs about 170 ms on this projector, because each one starts a process and
     * reopens the connection to the compositor, so the picture can only change about six
     * times a second. Repeats arrive twenty times a second, so while sliding the corner is
     * moved only when an apply can actually go out, and by more at a time -- which keeps
     * the number and the picture moving together, and a little quicker than before.
     */
    private static final int HOLD_STEP = 6;

    private long pressStartedAt = 0;
    private long lastEventAt = 0;

    private KeystoneView view;
    private boolean resetByHold = false;
    private boolean changedSomething = false;

    /** Applying runs off the main thread: it goes out through superuser and takes a moment. */
    private HandlerThread worker;
    private Handler background;
    private final Handler ui = new Handler(Looper.getMainLooper());

    /** Set by a press, cleared by an apply: there is a newer state to send. */
    private volatile boolean dirty = false;
    /** Whether an apply is already on its way, so presses do not pile up behind it. */
    private volatile boolean scheduled = false;
    /** Whether one is running right now, so a slide waits for it instead of running ahead. */
    private volatile boolean applying = false;

    private final Runnable applyNow = new Runnable() {
        @Override
        public void run() {
            scheduled = false;
            applying = true;
            boolean ok = true;
            // Keep going while presses are still arriving, always sending the newest
            // state. Each apply waits for the projector, so this paces itself and no
            // backlog of stale corners can build up.
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
                    if (view.notLive == live) {
                        view.notLive = !live;
                        view.invalidate();
                    }
                }
            });
        }
    };

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        Keystone.load();
        view = new KeystoneView(this);
        setContentView(view);
        worker = new HandlerThread("keystone-apply");
        worker.start();
        background = new Handler(worker.getLooper());
    }

    /** The values live in memory while this screen is open; store them when it is not. */
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
            case KeyEvent.KEYCODE_DPAD_UP:
                return arrow(event, true, -1);
            case KeyEvent.KEYCODE_DPAD_DOWN:
                return arrow(event, true, 1);
            case KeyEvent.KEYCODE_DPAD_LEFT:
                return arrow(event, false, -1);
            case KeyEvent.KEYCODE_DPAD_RIGHT:
                return arrow(event, false, 1);
            case KeyEvent.KEYCODE_DPAD_CENTER:
            case KeyEvent.KEYCODE_ENTER:
                if (event.getRepeatCount() == 0) {
                    resetByHold = false;
                    event.startTracking();
                }
                return true;
            case KeyEvent.KEYCODE_MENU:
                doReset();
                return true;
            default:
                return super.onKeyDown(code, event);
        }
    }

    @Override
    public boolean onKeyLongPress(int code, KeyEvent event) {
        if (code == KeyEvent.KEYCODE_DPAD_CENTER || code == KeyEvent.KEYCODE_ENTER) {
            resetByHold = true;
            doReset();
            return true;
        }
        return super.onKeyLongPress(code, event);
    }

    @Override
    public boolean onKeyUp(int code, KeyEvent event) {
        if (code == KeyEvent.KEYCODE_DPAD_CENTER || code == KeyEvent.KEYCODE_ENTER) {
            if (!resetByHold) {
                view.corner = Keystone.nextCorner(view.corner);
                view.invalidate();
            }
            resetByHold = false;
            return true;
        }
        return super.onKeyUp(code, event);
    }

    /**
     * One arrow press or repeat.
     *
     * Measured from this remote: a tap arrives as a single event, and holding produces
     * repeats after 400 ms at one every 50 ms. Every one of them moves the corner by a
     * single unit, which is what the vendor's own screen does -- so a tap is a nudge of
     * about two pixels and a hold slides the corner smoothly.
     *
     * @param towards 1 for the right or down arrow, -1 for the left or up arrow
     */
    private boolean arrow(KeyEvent event, boolean vertical, int towards) {
        if (SystemClock.uptimeMillis() - event.getEventTime() > STALE_MS) {
            return true;    // queued while the screen was busy; acting on it now would jump
        }
        long now = event.getEventTime();
        boolean fresh = event.getRepeatCount() == 0 || now - lastEventAt > GAP_MS;
        lastEventAt = now;
        if (fresh) {
            pressStartedAt = now;
        } else if (now - pressStartedAt < HOLD_MS) {
            return true;    // still a tap as far as anyone pressing it is concerned
        } else if (applying || scheduled) {
            return true;    // the picture is still catching up; do not run ahead of it
        }
        int delta = Keystone.deltaFor(view.corner, vertical, towards) * (fresh ? 1 : HOLD_STEP);
        view.refused |= !Keystone.move(view.corner, vertical, delta);
        changed();
        return true;
    }

    private void doReset() {
        view.refused |= !Keystone.reset();
        changed();
    }

    /**
     * Redraws at once and makes sure an apply is on its way.
     *
     * An apply already queued is left alone rather than pushed back, so a held-down arrow
     * keeps being applied at a steady rate instead of waiting for the person to stop.
     */
    private void changed() {
        changedSomething = true;
        view.invalidate();
        dirty = true;
        if (!scheduled) {
            scheduled = true;
            background.post(applyNow);
        }
    }

    /**
     * If applying live was refused -- no superuser, say -- the values are still saved, and
     * the only way left to show them is to restart the compositor. That is done once, on
     * the way out, rather than after every press.
     */
    @Override
    public void onBackPressed() {
        if (changedSomething && view.notLive && !view.refused) {
            changedSomething = false;
            Keystone.applyByRestart();
        }
        super.onBackPressed();
    }

    /** Draws the shape the picture will take, with a dot at each corner. */
    static final class KeystoneView extends View {

        /**
         * The projector's own blue and white, read straight off its keystone screen: a
         * screenshot of the vendor's own screen is almost entirely #0162B1, with #FFFFFF
         * for the frame and the writing.
         */
        private static final int PICTURE = Color.parseColor("#0162B1");
        private static final int LINE = Color.WHITE;
        private static final int TROUBLE = Color.parseColor("#FF8A80");

        int corner = 0;
        boolean refused = false;
        boolean notLive = false;

        private final Paint stroke = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint fill = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint label = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint caption = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final float density;
        /** The projector's own drawing of the remote, which its keystone screen shows. */
        private final Bitmap remote;

        KeystoneView(Context context) {
            super(context);
            density = context.getResources().getDisplayMetrics().density;
            setFocusable(true);
            setBackgroundColor(PICTURE);
            stroke.setStyle(Paint.Style.STROKE);
            stroke.setColor(LINE);
            stroke.setStrokeWidth(dp(3));
            fill.setStyle(Paint.Style.FILL);
            fill.setColor(LINE);
            label.setColor(LINE);
            label.setTextSize(dp(15));
            label.setFakeBoldText(true);
            caption.setColor(Color.WHITE);
            caption.setTextSize(dp(14));
            caption.setTextAlign(Paint.Align.CENTER);
            Bitmap picture = null;
            try {
                picture = BitmapFactory.decodeStream(
                        context.getAssets().open("correction_enter.png"));
            } catch (Throwable ignored) {
                // the screen works perfectly well without it
            }
            remote = picture;
        }

        private float dp(float v) {
            return v * density;
        }

        @Override
        protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            float w = getWidth();
            float h = getHeight();
            // The frame is drawn square and stays put. The projector warps everything on
            // screen as the corners change, so the frame itself shows the correction: a
            // second, drawn deformation would double it and mislead.
            //
            // The margin is the same number of pixels on all four sides, measured against
            // the shorter side, so the frame sits evenly inside the picture.
            float margin = Math.min(w, h) * 0.0875f;
            float left = margin;
            float right = w - margin;
            float top = margin;
            float bottom = h - margin;

            float[][] at = {{left, top}, {right, top}, {left, bottom}, {right, bottom}};

            if (remote != null) {
                float side = (bottom - top) * 0.5f;
                canvas.drawBitmap(remote, null,
                        new RectF(w / 2 - side / 2, h / 2 - side / 2,
                                w / 2 + side / 2, h / 2 + side / 2), null);
            }

            canvas.drawRect(left, top, right, bottom, stroke);

            for (int i = 0; i < at.length; i++) {
                float x = at[i][0];
                float y = at[i][1];
                if (i == corner) {
                    canvas.drawCircle(x, y, dp(11), stroke);
                    arrows(canvas, x, y);
                } else {
                    canvas.drawCircle(x, y, dp(11), fill);
                }
                String text = Keystone.value(i, false) + "," + Keystone.value(i, true);
                float tx = Keystone.isLeft(i) ? x + dp(20) : x - label.measureText(text) - dp(20);
                float ty = Keystone.isTop(i) ? y - dp(16) : y + dp(34);
                canvas.drawText(text, tx, ty, label);
            }

            caption.setColor(refused || notLive ? TROUBLE : Color.WHITE);
            canvas.drawText(refused
                            ? "This projector refused the change, so correction is not available here."
                            : notLive
                            ? "Saved, but it will only show once the projector restarts"
                            : "Hold OK to pull all four corners back at default",
                    w / 2, top + caption.getTextSize() * 2f, caption);
            canvas.drawText("Press OK to select the next corner    Use the Arrows to move the"
                            + " corner    Press Return to save and exit",
                    w / 2, bottom - caption.getTextSize() * 1.4f, caption);
        }

        /** The four little arrows that mark the corner now being moved. */
        private void arrows(Canvas canvas, float x, float y) {
            float gap = dp(22);
            float size = dp(7);
            tri(canvas, x, y - gap, 0, -1, size);
            tri(canvas, x, y + gap, 0, 1, size);
            tri(canvas, x - gap, y, -1, 0, size);
            tri(canvas, x + gap, y, 1, 0, size);
        }

        private void tri(Canvas canvas, float x, float y, float dx, float dy, float size) {
            Path p = new Path();
            p.moveTo(x + dx * size, y + dy * size);
            p.lineTo(x - dx * size + dy * size, y - dy * size + dx * size);
            p.lineTo(x - dx * size - dy * size, y - dy * size - dx * size);
            p.close();
            canvas.drawPath(p, fill);
        }
    }
}
