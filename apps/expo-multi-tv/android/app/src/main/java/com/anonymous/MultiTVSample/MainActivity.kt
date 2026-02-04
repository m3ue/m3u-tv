package com.anonymous.MultiTVSample

import android.os.Build
// @generated begin react-native-keyevent-import - expo prebuild (DO NOT MODIFY) sync-623c552ef74f8e382965ed2451e2658312c33112
import android.view.KeyEvent
import com.github.kevinejohn.keyevent.KeyEventModule
// @generated end react-native-keyevent-import
import android.os.Bundle

import com.facebook.react.ReactActivity
import com.facebook.react.ReactActivityDelegate
import com.facebook.react.defaults.DefaultNewArchitectureEntryPoint.fabricEnabled
import com.facebook.react.defaults.DefaultReactActivityDelegate

import expo.modules.ReactActivityDelegateWrapper

class MainActivity : ReactActivity() {
// @generated begin react-native-keyevent-body - expo prebuild (DO NOT MODIFY) sync-4e643b1f863a7b24063f5e26e0cc2645f10e8742
override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
   // // Uncomment this if key events should only trigger once when key is held down
  // if (event.getRepeatCount() == 0) {
  //   KeyEventModule.getInstance().onKeyDownEvent(keyCode, event)
  // }

  // // This will trigger the key repeat if the key is held down
  // // Comment this out if uncommenting the above
  KeyEventModule.getInstance().onKeyDownEvent(keyCode, event)

  // // Uncomment this if you want the default keyboard behavior
  // return super.onKeyDown(keyCode, event)

  // // The default keyboard behaviour wll be overridden
  // // This is similar to what e.preventDefault() does in a browser
  // // comment this if uncommenting the above
  super.onKeyDown(keyCode, event)
  return true
}

override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean {
  KeyEventModule.getInstance().onKeyUpEvent(keyCode, event)

  // // Uncomment this if you want the default keyboard behavior
  // return super.onKeyUp(keyCode, event)

  // // The default keyboard behaviour wll be overridden
  // // This is similar to what e.preventDefault() does in a browser
  // // comment this if uncommenting the above
  super.onKeyUp(keyCode, event)
  return true
}

override fun onKeyMultiple(keyCode: Int, repeatCount: Int, event: KeyEvent): Boolean {
    KeyEventModule.getInstance().onKeyMultipleEvent(keyCode, repeatCount, event)
    return super.onKeyMultiple(keyCode, repeatCount, event)
}
// @generated end react-native-keyevent-body
  override fun onCreate(savedInstanceState: Bundle?) {
    // Set the theme to AppTheme BEFORE onCreate to support
    // coloring the background, status bar, and navigation bar.
    // This is required for expo-splash-screen.
    setTheme(R.style.AppTheme);
    super.onCreate(null)
  }

  /**
   * Returns the name of the main component registered from JavaScript. This is used to schedule
   * rendering of the component.
   */
  override fun getMainComponentName(): String = "main"

  /**
   * Returns the instance of the [ReactActivityDelegate]. We use [DefaultReactActivityDelegate]
   * which allows you to enable New Architecture with a single boolean flags [fabricEnabled]
   */
  override fun createReactActivityDelegate(): ReactActivityDelegate {
    return ReactActivityDelegateWrapper(
          this,
          BuildConfig.IS_NEW_ARCHITECTURE_ENABLED,
          object : DefaultReactActivityDelegate(
              this,
              mainComponentName,
              fabricEnabled
          ){})
  }

  /**
    * Align the back button behavior with Android S
    * where moving root activities to background instead of finishing activities.
    * @see <a href="https://developer.android.com/reference/android/app/Activity#onBackPressed()">onBackPressed</a>
    */
  override fun invokeDefaultOnBackPressed() {
      if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.R) {
          if (!moveTaskToBack(false)) {
              // For non-root activities, use the default implementation to finish them.
              super.invokeDefaultOnBackPressed()
          }
          return
      }

      // Use the default back button implementation on Android S
      // because it's doing more than [Activity.moveTaskToBack] in fact.
      super.invokeDefaultOnBackPressed()
  }
}
