package com.hy320.tools;

import java.lang.reflect.Method;

/**
 * The projector's picture settings: brightness, contrast, saturation, hue and colour
 * temperature.
 *
 * These live behind the projector's own display service rather than in properties. The
 * interface, the call numbers and the identifiers were recovered from the vendor settings
 * app's own bytecode on 2026-10-25, before that app was removed, and then checked on the
 * projector itself:
 *
 *   service    vendor.aw.homlet.tvsystem.tvserver@1.0::ITvServer, instance "default"
 *   get        call 98, takes the identifier, returns the value
 *   set        call 97, takes the identifier and the value
 *
 * Unlike keystone, this needs no superuser: the call was made from an ordinary caller and
 * worked, and this unit's policy allows an ordinary app to reach that service. Everything
 * goes through reflection because android.os.HwBinder and android.os.HwParcel are not part
 * of the public platform.
 *
 * Which identifier is which was found by setting each one between its extremes and
 * watching a plain blue screen: saturation drains the blue while leaving white alone,
 * contrast moves both, and hue turns the blue green.
 */
final class Picture {

    static final int BRIGHTNESS = 1;
    static final int SATURATION = 2;
    static final int CONTRAST = 3;
    static final int HUE = 4;
    static final int COLOUR_TEMPERATURE = 12;

    /** Where each one sits on a projector that has not been adjusted. */
    static final int DEFAULT_LEVEL = 50;
    static final int DEFAULT_TEMPERATURE = 0;

    /**
     * The highest colour temperature mode that works.
     *
     * The display service accepts any number and stores it, but only 0, 1 and 2 do
     * anything: tried on the projector on 2026-10-25, 3 and above blank the picture
     * completely. Nothing offers this limit, so it is enforced here.
     */
    static final int MOST_TEMPERATURE = 2;

    private static final String IFACE = "vendor.aw.homlet.tvsystem.tvserver@1.0::ITvServer";
    private static final int GET = 98;
    private static final int SET = 97;

    private static Object service;
    private static Class<?> parcelClass;
    private static Method transact;
    private static Method writeToken;
    private static Method writeInt;
    private static Method verify;
    private static Method readInt;
    private static Method release;
    private static boolean unavailable = false;

    private Picture() {
    }

    /** True once the display service has been reached, false if it cannot be. */
    private static synchronized boolean connect() {
        if (service != null) {
            return true;
        }
        if (unavailable) {
            return false;
        }
        try {
            Class<?> hwBinder = Class.forName("android.os.HwBinder");
            parcelClass = Class.forName("android.os.HwParcel");
            Class<?> binderClass = Class.forName("android.os.IHwBinder");
            Object found = hwBinder.getMethod("getService", String.class, String.class)
                    .invoke(null, IFACE, "default");
            if (found == null) {
                unavailable = true;
                return false;
            }
            transact = binderClass.getMethod("transact", int.class, parcelClass, parcelClass, int.class);
            writeToken = parcelClass.getMethod("writeInterfaceToken", String.class);
            writeInt = parcelClass.getMethod("writeInt32", int.class);
            verify = parcelClass.getMethod("verifySuccess");
            readInt = parcelClass.getMethod("readInt32");
            release = parcelClass.getMethod("release");
            service = found;
            return true;
        } catch (Throwable t) {
            unavailable = true;
            return false;
        }
    }

    /** Reads one value, or the fallback if the display service cannot be reached. */
    static synchronized int get(int id, int fallback) {
        if (!connect()) {
            return fallback;
        }
        Object request = null;
        Object reply = null;
        try {
            request = parcelClass.newInstance();
            reply = parcelClass.newInstance();
            writeToken.invoke(request, IFACE);
            writeInt.invoke(request, id);
            transact.invoke(service, GET, request, reply, 0);
            verify.invoke(reply);
            return (Integer) readInt.invoke(reply);
        } catch (Throwable t) {
            return fallback;
        } finally {
            free(reply);
            free(request);
        }
    }

    /** Writes one value. Returns false if the display service refused or is absent. */
    static synchronized boolean set(int id, int value) {
        if (!connect()) {
            return false;
        }
        Object request = null;
        Object reply = null;
        try {
            request = parcelClass.newInstance();
            reply = parcelClass.newInstance();
            writeToken.invoke(request, IFACE);
            writeInt.invoke(request, id);
            writeInt.invoke(request, value);
            transact.invoke(service, SET, request, reply, 0);
            verify.invoke(reply);
            return true;
        } catch (Throwable t) {
            return false;
        } finally {
            free(reply);
            free(request);
        }
    }

    private static void free(Object parcel) {
        if (parcel == null) {
            return;
        }
        try {
            release.invoke(parcel);
        } catch (Throwable ignored) {
            // nothing useful to do while cleaning up
        }
    }
}
