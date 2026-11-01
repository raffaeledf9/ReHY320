/*
 * Sends one key=value string to the audio HAL, as AudioService itself does.
 *
 *   CLASSPATH=/data/local/tmp/audioparam.dex app_process / AudioParam screen_state=on
 *   CLASSPATH=/data/local/tmp/audioparam.dex app_process / AudioParam ?screen_state
 *
 * A leading '?' reads instead of writes (AudioSystem.getParameters). Nothing is persisted:
 * the HAL forgets it at the next restart. Built because the vendor's AudioService sends
 * "screen_state=off" on SCREEN_OFF (which uninitialises the Trident sound core) and never
 * sends the matching "on", so this is how the "on" half is tested by hand.
 */
public class AudioParam {
    public static void main(String[] args) throws Exception {
        if (args.length != 1) {
            System.err.println("usage: AudioParam key=value | ?key");
            System.exit(2);
        }
        Class<?> as = Class.forName("android.media.AudioSystem");
        if (args[0].startsWith("?")) {
            Object r = as.getMethod("getParameters", String.class).invoke(null, args[0].substring(1));
            System.out.println("get " + args[0].substring(1) + " -> [" + r + "]");
        } else {
            Object r = as.getMethod("setParameters", String.class).invoke(null, args[0]);
            System.out.println("set " + args[0] + " -> " + r);
        }
    }
}
