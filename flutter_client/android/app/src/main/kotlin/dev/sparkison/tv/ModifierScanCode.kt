package dev.sparkison.tv

import android.view.KeyEvent

// Linux scan codes that Flutter's Android embedder maps to the modifiers it
// reconciles against metaState on every event: KEY_LEFTCTRL, KEY_RIGHTCTRL,
// KEY_LEFTSHIFT, KEY_RIGHTSHIFT, KEY_LEFTALT, KEY_RIGHTALT.
private val MODIFIER_SCAN_CODES = intArrayOf(29, 97, 42, 54, 56, 100)

internal fun carriesForeignModifierScanCode(scanCode: Int, keyCode: Int, keyIsModifier: Boolean): Boolean =
    scanCode in MODIFIER_SCAN_CODES && keyCode != KeyEvent.KEYCODE_UNKNOWN && !keyIsModifier

/**
 * This event without its scan code when a non-modifier key carries a
 * modifier's scan code, else this same event.
 *
 * The Mi Box 3 IR keypad sends OK as KEYCODE_DPAD_CENTER with scan code 97
 * (KEY_RIGHTCTRL). Flutter derives the physical key from the scan code, so it
 * records Select as pressed under ControlRight; on release it reconciles
 * modifiers from metaState (no Ctrl held), synthesizes a ControlRight up, and
 * drops the real Select up as unpaired. Every press then looks held until the
 * long-press timer fires. Without a scan code Flutter keys the physical key
 * off the key code. Ported from Plezy ff2a02b79.
 *
 * Returning the same instance when nothing changes matters: Flutter recognizes
 * a key it redispatches through the view hierarchy by identity, so a fresh
 * copy of an already-normalized event would loop back into the framework.
 */
internal fun KeyEvent.withoutModifierScanCode(): KeyEvent {
    if (!carriesForeignModifierScanCode(scanCode, keyCode, KeyEvent.isModifierKey(keyCode))) return this
    return KeyEvent(downTime, eventTime, action, keyCode, repeatCount, metaState, deviceId, 0, flags, source)
}
