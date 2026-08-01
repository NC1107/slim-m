package top.npcserver.slimm

import android.content.pm.ActivityInfo
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    /**
     * Locks phones to portrait and leaves tablets alone.
     *
     * The decision comes from `R.bool.slimm_portrait_only`, which the
     * values-sw600dp override flips to false, because sw600dp is Android's
     * own phone/tablet line and it is resolved against the live device
     * configuration here. It could not be `android:screenOrientation` in the
     * manifest: that attribute is read while parsing the package with the
     * default configuration, so the qualified resource would never be picked
     * and every tablet would be locked as well.
     */
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestedOrientation = if (resources.getBoolean(R.bool.slimm_portrait_only)) {
            ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        } else {
            ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ClipboardImageChannel(applicationContext).attach(flutterEngine.dartExecutor.binaryMessenger)
    }
}
