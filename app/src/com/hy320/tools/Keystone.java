package com.hy320.tools;

/**
 * Keystone correction: the four corners of the projected rectangle.
 *
 * What the firmware actually reads, worked out on the projector on 2026-10-24:
 *
 *  - The values live in eight properties, one per corner and axis, named
 *    persist.display.keystone_ltx and so on.
 *  - 125 is neutral. The compositor divides by a thousand, so 125 reaches it as 0.125.
 *  - x counts to the right and y counts upwards, one unit per press of the vendor's own
 *    screen. This was measured: ten presses of Right on the top left moved its x from 125
 *    to 139, and ten of Down on the bottom right moved its y from 125 to 115.
 *  - The vendor-patched compositor reads all eight when it starts, and only then. Writing
 *    a property changes nothing by itself, which is why the first attempt at this appeared
 *    to work and did not. Restarting the compositor applies it in about five seconds,
 *    without restarting the projector.
 *
 * The screen above works in offsets from neutral, which is what a person thinks in.
 *
 * Note: an ordinary app may write these properties on this projector because its blocking
 * layer (SELinux) is in logging mode. If that is ever switched to enforcing, this stops
 * working and the vendor's own screen is the fallback.
 */
final class Keystone {

    /** The four corners, in the firmware's own naming. */
    static final String[] CORNERS = {"lt", "rt", "lb", "rb"};
    static final String[] CORNER_LABELS = {"top left", "top right", "bottom left", "bottom right"};

    /** The value that means "not corrected". */
    static final int NEUTRAL = 125;
    /** How far from neutral a corner may go, which is as far as the firmware's own range. */
    static final int LIMIT = 125;
    /** What one press of an arrow key changes, matching the vendor's own screen. */
    static final int STEP = 1;

    /**
     * The order the compositor wants the eight values in: bottom left, top left, top
     * right, bottom right, each x then y. Written as corner indexes into CORNERS.
     */
    private static final int[] PARCEL_ORDER = {2, 2, 0, 0, 1, 1, 3, 3};
    private static final boolean[] PARCEL_VERTICAL = {false, true, false, true, false, true, false, true};

    private static final String PREFIX = "persist.display.keystone_";
    private static final String RESTART = "ctl.restart";
    private static final String COMPOSITOR = "surfaceflinger";

    private Keystone() {
    }

    static String key(int corner, boolean vertical) {
        return PREFIX + CORNERS[corner] + (vertical ? "y" : "x");
    }

    static boolean isLeft(int corner) {
        return CORNERS[corner].charAt(0) == 'l';
    }

    static boolean isTop(int corner) {
        return CORNERS[corner].charAt(1) == 't';
    }

    /**
     * The order the OK key steps through the corners: clockwise from the top left, which
     * is how the vendor's own screen moves. Indexed by the corner it is leaving.
     */
    private static final int[] NEXT = {1, 3, 0, 2};

    static int nextCorner(int corner) {
        return NEXT[corner];
    }

    /**
     * How much to change a corner for a press, given which way the person pressed.
     *
     * Both of a corner's numbers grow **inwards**, towards the middle of the picture, not
     * in a fixed screen direction. So on the top left they grow right and down, while on
     * the top right they grow left and down. Measured on the projector: ten presses of
     * Right on the top left raised its x from 125 to 139, and ten of Down on the bottom
     * right lowered its y from 125 to 115.
     *
     * @param towards 1 for the right or down arrow, -1 for the left or up arrow
     */
    static int deltaFor(int corner, boolean vertical, int towards) {
        int inwards = vertical
                ? (isTop(corner) ? 1 : -1)
                : (isLeft(corner) ? 1 : -1);
        return towards * inwards * STEP;
    }

    static int clamp(int offset) {
        return Math.max(-LIMIT, Math.min(LIMIT, offset));
    }

    /** Turns a stored value into an offset from neutral, treating nonsense as neutral. */
    static int toOffset(String value) {
        if (value != null) {
            try {
                int v = Integer.parseInt(value.trim());
                if (v >= NEUTRAL - LIMIT && v <= NEUTRAL + LIMIT) {
                    return v - NEUTRAL;
                }
            } catch (NumberFormatException ignored) {
                // treated as neutral below
            }
        }
        return 0;
    }

    /** Turns an offset back into the value the firmware stores. */
    static int toValue(int offset) {
        return NEUTRAL + clamp(offset);
    }

    /**
     * The eight offsets while a screen is working on them.
     *
     * They are kept here rather than read back from the properties on every press for two
     * reasons. A property write does not land straight away, so reading one back as the
     * basis for the next press makes the value jump about. And these are persisted
     * properties: every write goes to storage, which is far too much for a held-down arrow.
     * The properties are written once, on the way out.
     */
    private static final int[] offsets = new int[CORNERS.length * 2];
    private static boolean loaded = false;

    private static int index(int corner, boolean vertical) {
        return corner * 2 + (vertical ? 1 : 0);
    }

    /** Takes the current values from the projector. Call when a screen opens. */
    static synchronized void load() {
        for (int c = 0; c < CORNERS.length; c++) {
            offsets[index(c, false)] = toOffset(Props.get(key(c, false), null));
            offsets[index(c, true)] = toOffset(Props.get(key(c, true), null));
        }
        loaded = true;
        zoomInward = 0;     // how much of what is stored came from zooming is unknowable
    }

    static synchronized int read(int corner, boolean vertical) {
        if (!loaded) {
            load();
        }
        return offsets[index(corner, vertical)];
    }

    /** Writes all eight to the projector, so they survive a restart. */
    static synchronized boolean save() {
        boolean ok = true;
        for (int c = 0; c < CORNERS.length; c++) {
            ok &= Props.set(key(c, false), String.valueOf(toValue(offsets[index(c, false)])));
            ok &= Props.set(key(c, true), String.valueOf(toValue(offsets[index(c, true)])));
        }
        return ok;
    }

    /**
     * The number the projector itself keeps for this corner and axis: 125 in the middle,
     * 0 and 250 at the ends of its range. Shown on screen as-is, so what is read there is
     * what the firmware holds, not an offset that would call the middle zero.
     */
    static int value(int corner, boolean vertical) {
        return toValue(read(corner, vertical));
    }

    /** Moves one corner, in memory. Saving and applying are separate. */
    static synchronized boolean move(int corner, boolean vertical, int delta) {
        if (!loaded) {
            load();
        }
        offsets[index(corner, vertical)] = clamp(offsets[index(corner, vertical)] + delta);
        return true;
    }

    /**
     * How far the zoom screen has pulled every corner in, from 0 to the limit.
     *
     * Kept apart from the corners themselves so the zoom reading is exact. Working it out
     * from the corners instead would be skewed by any keystone correction, which is what
     * made the percentage uneven and able to pass 100.
     */
    private static int zoomInward = 0;

    /**
     * Moves every corner inward or outward by the same amount, which on this projector is
     * what "screen zoom" is: there is no separate zoom, and the property the vendor calls
     * persist.sys.zoom.value turns out to hold a copy of these eight corner numbers.
     *
     * Any keystone correction already set is kept, because this adds to each corner rather
     * than replacing it. The move happens only if every corner can take the whole step, so
     * the steps stay even instead of some corners stopping at their limit before others.
     *
     * @param inward positive to shrink the picture, negative to grow it
     * @return false if it would go outside the range, so nothing moved
     */
    static synchronized boolean zoom(int inward) {
        if (!loaded) {
            load();
        }
        int target = zoomInward + inward;
        if (target < 0 || target > LIMIT) {
            return false;
        }
        for (int o : offsets) {
            int next = o + inward;
            if (next < -LIMIT || next > LIMIT) {
                return false;       // one corner cannot take the step, so none does
            }
        }
        for (int i = 0; i < offsets.length; i++) {
            offsets[i] += inward;
        }
        zoomInward = target;
        return true;
    }

    /** How far the zoom has pulled the corners in: 0 is the full picture. */
    static synchronized int zoomAmount() {
        return zoomInward;
    }

    /** Puts all four corners back to neutral, in memory. */
    static synchronized boolean reset() {
        if (!loaded) {
            load();
        }
        for (int i = 0; i < offsets.length; i++) {
            offsets[i] = 0;
        }
        zoomInward = 0;
        return true;
    }

    /**
     * Makes the firmware pick the corners up, by restarting the part of Android that reads
     * them. The picture goes away for a few seconds and comes back corrected.
     */
    static boolean apply() {
        int[] values = new int[PARCEL_ORDER.length];
        synchronized (Keystone.class) {
            for (int i = 0; i < values.length; i++) {
                values[i] = toValue(read(PARCEL_ORDER[i], PARCEL_VERTICAL[i]));
            }
        }
        return Compositor.setKeystone(values);
    }

    /**
     * The last resort if the compositor refuses the call: restart it, so it reads the
     * properties afresh. This blanks the picture for a few seconds, which is why it is not
     * the usual route.
     */
    static void applyByRestart() {
        // Through superuser where it is available, since that is certain to be allowed,
        // and directly otherwise.
        if (Props.run("su", "-c", "setprop " + RESTART + " " + COMPOSITOR) == null) {
            Props.command(RESTART, COMPOSITOR);
        }
    }
}
