package dev.sparkison.tv

import android.view.KeyEvent
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.JUnit4

@RunWith(JUnit4::class)
class ModifierScanCodeTest {

    @Test
    fun okSentWithRightCtrlScanCodeIsNormalized() {
        assertTrue(carriesForeignModifierScanCode(97, KeyEvent.KEYCODE_DPAD_CENTER, keyIsModifier = false))
    }

    @Test
    fun realModifierKeysKeepTheirScanCode() {
        assertFalse(carriesForeignModifierScanCode(97, KeyEvent.KEYCODE_CTRL_RIGHT, keyIsModifier = true))
    }

    @Test
    fun ordinaryScanCodesAreLeftAlone() {
        assertFalse(carriesForeignModifierScanCode(28, KeyEvent.KEYCODE_ENTER, keyIsModifier = false))
    }

    @Test
    fun alreadyNormalizedEventsAreLeftAlone() {
        assertFalse(carriesForeignModifierScanCode(0, KeyEvent.KEYCODE_DPAD_CENTER, keyIsModifier = false))
    }

    @Test
    fun keysWithoutAKeyCodeKeepTheirOnlyIdentity() {
        assertFalse(carriesForeignModifierScanCode(97, KeyEvent.KEYCODE_UNKNOWN, keyIsModifier = false))
    }
}
