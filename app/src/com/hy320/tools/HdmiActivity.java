package com.hy320.tools;

import android.app.Activity;
import android.content.ComponentName;
import android.content.Intent;
import android.os.Bundle;
import android.widget.Toast;

/**
 * A home-screen tile that switches straight to the HDMI input.
 *
 * The projector's own input viewer is an Allwinner app; several names exist across these
 * boards, so each is tried in turn and the first that starts wins.
 */
public class HdmiActivity extends Activity {

    private static final String[][] CANDIDATES = {
            {"com.softwinner.awlivetv", "com.softwinner.awlivetv.MainActivity"},
            {"com.softwinner.awsource", "com.softwinner.awsource.MainActivity"},
            {"com.softwinner.vis", "com.softwinner.vis.VideoInputActivity"},
    };

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        for (String[] c : CANDIDATES) {
            if (start(new Intent().setComponent(new ComponentName(c[0], c[1])))) {
                finish();
                return;
            }
        }
        for (String[] c : CANDIDATES) {
            Intent launch = getPackageManager().getLaunchIntentForPackage(c[0]);
            if (launch != null && start(launch)) {
                finish();
                return;
            }
        }
        Toast.makeText(this, "The HDMI input app is not installed", Toast.LENGTH_LONG).show();
        finish();
    }

    private boolean start(Intent intent) {
        try {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(intent);
            return true;
        } catch (Throwable t) {
            return false;
        }
    }
}
