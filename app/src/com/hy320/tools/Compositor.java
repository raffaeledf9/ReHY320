package com.hy320.tools;

import android.os.IBinder;
import android.os.Parcel;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.lang.reflect.Method;
import java.util.Locale;

/**
 * Talks to the part of Android that draws the screen, to apply keystone correction at once.
 *
 * The projector's compositor reads the eight corner properties only when it starts, so
 * writing them changes nothing until something tells it to take them up. The vendor's own
 * settings app does that with one private call, recovered from it on 2026-10-24: the
 * service is "SurfaceFlinger", the interface is "android.ui.ISurfaceComposer", the call is
 * number 1050, and it carries the eight corner values as floats, each a thousandth of the
 * stored number, in this order:
 *
 *     bottom left x, bottom left y, top left x, top left y,
 *     top right x, top right y, bottom right x, bottom right y
 *
 * which is the order the compositor prints them in its own log. No reply is expected.
 *
 * The compositor accepts that call only from the system itself, and this app is an
 * ordinary one, so it goes through superuser instead. A superuser shell is opened once and
 * kept, because starting one per keypress is far too slow to follow a held-down arrow.
 *
 * None of this is a published interface, so every step is guarded: if the service is
 * missing, superuser is refused, or the call fails, this says so and the caller falls back
 * to writing the properties and restarting the compositor.
 */
final class Compositor {

    private static final String SERVICE = "SurfaceFlinger";
    private static final String INTERFACE = "android.ui.ISurfaceComposer";
    private static final int SET_KEYSTONE = 1050;
    /** The compositor wants a fraction; the properties hold it multiplied by a thousand. */
    private static final float SCALE = 0.001f;
    /** How long to wait for the superuser shell, which may ask the person the first time. */
    private static final long SHELL_WAIT_MS = 20000;
    /** How long to wait for one command to finish before giving up on the shell. */
    private static final long REPLY_WAIT_MS = 3000;
    /** Printed by the shell when a command is done, so the next one is not piled on top. */
    private static final String DONE = "KEYSTONE-DONE";

    private static IBinder cached;
    private static boolean directRefused = false;

    private static Process shell;
    private static BufferedWriter toShell;
    private static BufferedReader fromShell;

    private Compositor() {
    }

    private static IBinder service() {
        if (cached != null && cached.isBinderAlive()) {
            return cached;
        }
        try {
            Method m = Class.forName("android.os.ServiceManager")
                    .getMethod("getService", String.class);
            Object b = m.invoke(null, SERVICE);
            cached = b instanceof IBinder ? (IBinder) b : null;
        } catch (Throwable t) {
            cached = null;
        }
        return cached;
    }

    /**
     * Applies the eight corner values immediately.
     *
     * @param values the stored numbers, in the order the compositor expects them
     * @return true only if the call was made and accepted
     */
    static boolean setKeystone(int[] values) {
        if (values.length != 8) {
            throw new IllegalArgumentException("the compositor expects eight values");
        }
        if (!directRefused) {
            if (direct(values)) {
                return true;
            }
            // The compositor only takes this from the system, so once refused it always
            // will be. Remembering that keeps a refusal out of the log on every press.
            directRefused = true;
        }
        return send(command(values));
    }

    /** Lets go of the superuser shell. Called when the screen using it closes. */
    static synchronized void done() {
        closeShell();
    }

    /** The call made as ourselves. Works only if this app ever runs as the system. */
    private static boolean direct(int[] values) {
        IBinder sf = service();
        if (sf == null) {
            return false;
        }
        Parcel data = Parcel.obtain();
        try {
            data.writeInterfaceToken(INTERFACE);
            for (int v : values) {
                data.writeFloat(v * SCALE);
            }
            return sf.transact(SET_KEYSTONE, data, null, 0);
        } catch (Throwable t) {
            return false;
        } finally {
            data.recycle();
        }
    }

    /**
     * The same call as a shell command.
     *
     * The numbers are formatted in a fixed way on purpose: with an Italian or other
     * comma-decimal locale, the default formatting would write "0,125" and the command
     * would be read as extra arguments.
     */
    private static String command(int[] values) {
        StringBuilder cmd = new StringBuilder("service call ").append(SERVICE).append(' ')
                .append(SET_KEYSTONE);
        for (int v : values) {
            cmd.append(String.format(Locale.US, " f %.3f", v * SCALE));
        }
        return cmd.toString();
    }

    private static synchronized boolean alive() {
        if (shell == null) {
            return false;
        }
        try {
            shell.exitValue();
            return false;
        } catch (IllegalThreadStateException stillRunning) {
            return true;
        }
    }

    /** Opens the superuser shell, or confirms the one already open. */
    private static synchronized boolean open() {
        if (alive()) {
            return true;
        }
        closeShell();
        try {
            shell = new ProcessBuilder("su").redirectErrorStream(true).start();
            toShell = new BufferedWriter(new OutputStreamWriter(shell.getOutputStream()));
            fromShell = new BufferedReader(new InputStreamReader(shell.getInputStream()));
            toShell.write("echo READY\n");
            toShell.flush();
            long deadline = System.currentTimeMillis() + SHELL_WAIT_MS;
            while (System.currentTimeMillis() < deadline) {
                if (fromShell.ready()) {
                    String line = fromShell.readLine();
                    if (line == null) {
                        break;
                    }
                    if (line.contains("READY")) {
                        return true;
                    }
                } else if (!alive()) {
                    break;      // superuser refused, so the shell ended at once
                } else {
                    Thread.sleep(40);
                }
            }
        } catch (Throwable ignored) {
            // treated as "no superuser" below
        }
        closeShell();
        return false;
    }

    /**
     * Sends one command and waits for the shell to finish it.
     *
     * Waiting matters: without it, a held-down arrow writes commands faster than the shell
     * can run them, and the backlog keeps moving the picture long after the key is
     * released -- and eventually fills the pipe and stops it altogether. Waiting makes the
     * rate settle at whatever the projector can actually manage.
     */
    private static synchronized boolean send(String cmd) {
        if (!open()) {
            return false;
        }
        try {
            toShell.write(cmd);
            toShell.write("\necho " + DONE + "\n");
            toShell.flush();
            long deadline = System.currentTimeMillis() + REPLY_WAIT_MS;
            while (System.currentTimeMillis() < deadline) {
                if (fromShell.ready()) {
                    String line = fromShell.readLine();
                    if (line == null) {
                        break;
                    }
                    if (line.contains(DONE)) {
                        return true;
                    }
                } else if (!alive()) {
                    break;
                } else {
                    Thread.sleep(5);
                }
            }
        } catch (Throwable ignored) {
            // treated as a failure below
        }
        closeShell();
        return false;
    }

    private static synchronized void closeShell() {
        try {
            if (toShell != null) {
                toShell.write("exit\n");
                toShell.flush();
                toShell.close();
            }
        } catch (Throwable ignored) {
            // closing is best effort
        }
        try {
            if (fromShell != null) {
                fromShell.close();
            }
        } catch (Throwable ignored) {
            // likewise
        }
        if (shell != null) {
            shell.destroy();
        }
        shell = null;
        toShell = null;
        fromShell = null;
    }
}
