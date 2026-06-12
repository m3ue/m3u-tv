package com.m3ue.m3utv

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var media3Plugin: Media3PlaybackPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        media3Plugin = Media3PlaybackPlugin(this, flutterEngine)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        media3Plugin?.dispose()
        media3Plugin = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
