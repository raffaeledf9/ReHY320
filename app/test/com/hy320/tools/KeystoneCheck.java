package com.hy320.tools;

/**
 * Runs the keystone maths on the PC, with no projector and no Android involved.
 *
 *   javac -source 8 -target 8 -bootclasspath <android.jar> -sourcepath src -d <out> \
 *         test/com/hy320/tools/KeystoneCheck.java
 *   java -cp <out> com.hy320.tools.KeystoneCheck
 */
public class KeystoneCheck {

    private static int checks = 0;

    private static void eq(Object got, Object want, String what) {
        checks++;
        if (!got.equals(want)) {
            throw new AssertionError(what + ": got " + got + ", wanted " + want);
        }
    }

    public static void main(String[] args) {
        // reading a stored value as an offset from neutral
        eq(Keystone.toOffset("125"), 0, "neutral reads as no offset");
        eq(Keystone.toOffset("139"), 14, "the measured top-left move");
        eq(Keystone.toOffset("115"), -10, "the measured bottom-right move");
        eq(Keystone.toOffset("0"), -125, "the bottom of the range");
        eq(Keystone.toOffset("250"), 125, "the top of the range");
        eq(Keystone.toOffset(" 130 "), 5, "spaces are ignored");
        eq(Keystone.toOffset(null), 0, "a missing value reads as neutral");
        eq(Keystone.toOffset("rubbish"), 0, "a malformed value reads as neutral");
        eq(Keystone.toOffset("251"), 0, "a value above the range reads as neutral");
        eq(Keystone.toOffset("-1"), 0, "a value below the range reads as neutral");

        // writing an offset back as a stored value
        eq(Keystone.toValue(0), 125, "no offset writes neutral");
        eq(Keystone.toValue(14), 139, "a positive offset");
        eq(Keystone.toValue(-10), 115, "a negative offset");
        eq(Keystone.toValue(5000), 250, "a huge offset is capped at the top");
        eq(Keystone.toValue(-5000), 0, "a huge offset is capped at the bottom");

        // a value survives a round trip
        for (int v = 0; v <= 250; v += 25) {
            eq(Keystone.toValue(Keystone.toOffset(String.valueOf(v))), v, "round trip of " + v);
        }

        // the limit
        eq(Keystone.clamp(10), 10, "a small offset is kept");
        eq(Keystone.clamp(200), Keystone.LIMIT, "a large offset is capped");
        eq(Keystone.clamp(-200), -Keystone.LIMIT, "a large negative offset is capped");

        // pressing an arrow repeatedly stops at the limit instead of wrapping
        int offset = 0;
        for (int i = 0; i < 400; i++) {
            offset = Keystone.clamp(offset + Keystone.STEP);
        }
        eq(offset, Keystone.LIMIT, "pressing past the limit holds there");
        eq(Keystone.toValue(offset), Keystone.NEUTRAL + Keystone.LIMIT, "and writes the top of the range");
        for (int i = 0; i < 400; i++) {
            offset = Keystone.clamp(offset - Keystone.STEP);
        }
        eq(offset, -Keystone.LIMIT, "and holds at the other limit");
        eq(Keystone.toValue(offset), 0, "which is the bottom of the range");

        // the property names, and which side of the picture each corner is on
        eq(Keystone.key(0, false), "persist.display.keystone_ltx", "top left, sideways");
        eq(Keystone.key(0, true), "persist.display.keystone_lty", "top left, up and down");
        eq(Keystone.key(3, false), "persist.display.keystone_rbx", "bottom right, sideways");
        eq(Keystone.key(3, true), "persist.display.keystone_rby", "bottom right, up and down");
        eq(Keystone.isLeft(0), true, "the top left is on the left");
        eq(Keystone.isLeft(1), false, "the top right is not");
        eq(Keystone.isTop(0), true, "the top left is at the top");
        eq(Keystone.isTop(2), false, "the bottom left is not");
        eq(Keystone.CORNERS.length, Keystone.CORNER_LABELS.length, "a label for every corner");

        // Which way a press moves a corner. Both numbers grow inwards, so the arrow that
        // increases a number differs per corner. The two anchors here were measured on the
        // projector itself; the rest follow from the same rule.
        eq(Keystone.deltaFor(0, false, 1), Keystone.STEP, "top left, Right grows x (measured)");
        eq(Keystone.deltaFor(3, true, 1), -Keystone.STEP, "bottom right, Down shrinks y (measured)");
        eq(Keystone.deltaFor(0, true, 1), Keystone.STEP, "top left, Down grows y");
        eq(Keystone.deltaFor(1, false, 1), -Keystone.STEP, "top right, Right shrinks x");
        eq(Keystone.deltaFor(1, true, 1), Keystone.STEP, "top right, Down grows y");
        eq(Keystone.deltaFor(2, false, 1), Keystone.STEP, "bottom left, Right grows x");
        eq(Keystone.deltaFor(2, true, 1), -Keystone.STEP, "bottom left, Down shrinks y");
        eq(Keystone.deltaFor(3, false, 1), -Keystone.STEP, "bottom right, Right shrinks x");
        // the opposite arrow always undoes the first
        for (int c = 0; c < Keystone.CORNERS.length; c++) {
            for (boolean v : new boolean[]{false, true}) {
                eq(Keystone.deltaFor(c, v, 1) + Keystone.deltaFor(c, v, -1), 0,
                        "opposite arrows cancel on " + Keystone.CORNER_LABELS[c]);
            }
        }

        // OK steps round the corners clockwise from the top left
        eq(Keystone.nextCorner(0), 1, "top left then top right");
        eq(Keystone.nextCorner(1), 3, "top right then bottom right");
        eq(Keystone.nextCorner(3), 2, "bottom right then bottom left");
        eq(Keystone.nextCorner(2), 0, "bottom left then back to the top left");
        boolean[] visited = new boolean[Keystone.CORNERS.length];
        int at = 0;
        for (int i = 0; i < Keystone.CORNERS.length; i++) {
            visited[at] = true;
            at = Keystone.nextCorner(at);
        }
        eq(at, 0, "four presses of OK come back to the start");
        for (int c = 0; c < visited.length; c++) {
            eq(visited[c], true, "the cycle visits " + Keystone.CORNER_LABELS[c]);
        }

        System.out.println(checks + " checks passed");
    }
}
