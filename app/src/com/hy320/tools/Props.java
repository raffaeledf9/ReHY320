package com.hy320.tools;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.lang.reflect.Method;

/**
 * Reads and writes Android system properties.
 *
 * The projector's own firmware keeps the keystone corners and the projection mode in
 * properties, so this is the whole mechanism the app needs. Two routes are tried: the
 * framework class first, then the setprop command, because which one an ordinary app is
 * allowed to use depends on settings on the device.
 */
final class Props {

    private Props() {
    }

    static String get(String key, String fallback) {
        try {
            Method m = Class.forName("android.os.SystemProperties")
                    .getMethod("get", String.class, String.class);
            Object v = m.invoke(null, key, "");
            if (v instanceof String && !((String) v).isEmpty()) {
                return (String) v;
            }
        } catch (Throwable ignored) {
        }
        String out = run("getprop", key);
        return out == null || out.isEmpty() ? fallback : out;
    }

    /** True only when the value can be read back, so a silent refusal is not mistaken for success. */
    static boolean set(String key, String value) {
        try {
            Method m = Class.forName("android.os.SystemProperties")
                    .getMethod("set", String.class, String.class);
            m.invoke(null, key, value);
            if (value.equals(get(key, null))) {
                return true;
            }
        } catch (Throwable ignored) {
        }
        run("setprop", key, value);
        return value.equals(get(key, null));
    }

    /**
     * Writes a property that cannot be read back, such as the ctl.* ones that ask init to
     * start or stop something. Verifying is impossible, so this tries the framework class
     * and only falls back to the command if that throws -- otherwise the action would be
     * asked for twice.
     */
    static void command(String key, String value) {
        try {
            Method m = Class.forName("android.os.SystemProperties")
                    .getMethod("set", String.class, String.class);
            m.invoke(null, key, value);
            return;
        } catch (Throwable ignored) {
            // fall through to the command
        }
        run("setprop", key, value);
    }

    static int getInt(String key, int fallback) {
        try {
            return Integer.parseInt(get(key, String.valueOf(fallback)).trim());
        } catch (NumberFormatException e) {
            return fallback;
        }
    }

    /** Runs a command and returns everything it printed, or null if it could not run. */
    static String run(String... command) {
        Process p = null;
        try {
            p = new ProcessBuilder(command).redirectErrorStream(true).start();
            BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream()));
            StringBuilder sb = new StringBuilder();
            String line;
            while ((line = r.readLine()) != null) {
                sb.append(line);
            }
            p.waitFor();
            return sb.toString().trim();
        } catch (Throwable t) {
            return null;
        } finally {
            if (p != null) {
                p.destroy();
            }
        }
    }
}
