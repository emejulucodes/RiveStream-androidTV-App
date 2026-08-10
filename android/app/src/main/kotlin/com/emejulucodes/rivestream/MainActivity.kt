package com.emejulucodes.rivestream

import android.content.Context
import android.os.Bundle
import android.os.SystemClock
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.inputmethod.InputMethodManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Intercepts Android TV remote D-pad events at the Activity level and hands
 * them to Dart.
 *
 * This is deliberately NOT done with a JavaScript `keydown` listener inside
 * the page, nor with a Flutter `Focus` widget. The WebView is embedded as a
 * platform view, so Android delivers key events to whichever native view
 * holds focus -- in practice the WebView itself. That means the Flutter
 * widget tree never sees the D-pad, and the page's own key listeners only
 * fire if the WebView happens to have focus AND the page has a focused
 * element, which a non-TV-optimized site generally does not.
 *
 * `dispatchKeyEvent` runs before the event reaches the view hierarchy at
 * all, so it works regardless of who holds focus. Dart drives the page
 * from there (moving a virtual cursor, or stepping focus).
 *
 * KEYCODE_BACK is intentionally NOT intercepted: it is left to the normal
 * dispatch path so Flutter's PopScope/back handling keeps working.
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.emejulucodes.rivestream/remote"
    }

    private var channel: MethodChannel? = null

    /**
     * When false, key events are passed through untouched so Flutter's own
     * focus traversal drives dialogs and full-screen Flutter routes.
     * Dart flips this whenever an overlay is shown or dismissed.
     */
    private var intercepting = true

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.decorView.isFocusableInTouchMode = true
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "setInterceptEnabled" -> {
                        intercepting = call.arguments as? Boolean ?: true
                        result.success(null)
                    }
                    "tapAt" -> {
                        val fx = (call.argument<Double>("fx")) ?: 0.0
                        val fy = (call.argument<Double>("fy")) ?: 0.0
                        result.success(dispatchTap(fx, fy))
                    }
                    "hoverAt" -> {
                        val fx = (call.argument<Double>("fx")) ?: 0.0
                        val fy = (call.argument<Double>("fy")) ?: 0.0
                        result.success(dispatchHover(fx, fy))
                    }
                    "showKeyboard" -> result.success(setKeyboardVisible(true))
                    "hideKeyboard" -> result.success(setKeyboardVisible(false))
                    else -> result.notImplemented()
                }
            }
        }
    }

    /**
     * Injects a real touch DOWN/UP pair into this window at a point given as
     * a fraction of the window size.
     *
     * Pointer mode originally "clicked" by dispatching synthetic MouseEvents
     * from JavaScript, which cannot work over an embedded player: the site's
     * Embed Mode puts the player in a cross-origin <iframe>, so
     * document.elementFromPoint() in the top document returns the <iframe>
     * element itself and the parent page has no access to what is inside it.
     * The play button never saw the event.
     *
     * A real MotionEvent goes through the compositor and hits whatever is
     * actually under the point, iframe or not -- exactly like a mouse would.
     *
     * Fractions (not pixels) are used so Dart never has to know the display
     * density; the window's own pixel size is the authority.
     */
    private fun dispatchTap(fx: Double, fy: Double): Boolean {
        val root = window?.decorView ?: return false
        if (root.width <= 0 || root.height <= 0) return false
        val x = (fx * root.width).toFloat()
        val y = (fy * root.height).toFloat()
        val downTime = SystemClock.uptimeMillis()
        return try {
            MotionEvent.obtain(downTime, downTime, MotionEvent.ACTION_DOWN, x, y, 0).let {
                it.source = InputDevice.SOURCE_TOUCHSCREEN
                dispatchTouchEvent(it)
                it.recycle()
            }
            MotionEvent.obtain(downTime, downTime + 50, MotionEvent.ACTION_UP, x, y, 0).let {
                it.source = InputDevice.SOURCE_TOUCHSCREEN
                dispatchTouchEvent(it)
                it.recycle()
            }
            true
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Moves a real mouse cursor over the page, so hover-only UI (player
     * chrome, dropdown menus) reveals itself inside embedded frames too.
     */
    private fun dispatchHover(fx: Double, fy: Double): Boolean {
        val root = window?.decorView ?: return false
        if (root.width <= 0 || root.height <= 0) return false
        val x = (fx * root.width).toFloat()
        val y = (fy * root.height).toFloat()
        val now = SystemClock.uptimeMillis()
        return try {
            MotionEvent.obtain(now, now, MotionEvent.ACTION_HOVER_MOVE, x, y, 0).let {
                it.source = InputDevice.SOURCE_MOUSE
                dispatchGenericMotionEvent(it)
                it.recycle()
            }
            true
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Explicitly asks for (or dismisses) the on-screen keyboard.
     *
     * A real tap on a text field normally makes WebView raise the IME by
     * itself, and that is the primary mechanism. This exists because the
     * WebView here is a Flutter platform view: which native view actually
     * holds focus is not fully under our control, and on Android TV the
     * leanback IME is easy to miss entirely. Asking directly costs nothing
     * when the keyboard is already up.
     */
    private fun setKeyboardVisible(visible: Boolean): Boolean {
        return try {
            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
            if (visible) {
                // Only ever show the keyboard for a view that actually has
                // focus. Falling back to the decor view raises an IME with
                // no InputConnection: it appears, swallows the D-pad, and
                // types into nothing -- worse than showing no keyboard.
                val target = window.decorView.findFocus() ?: return false
                imm.showSoftInput(target, InputMethodManager.SHOW_IMPLICIT)
            } else {
                imm.hideSoftInputFromWindow(window.decorView.windowToken, 0)
            }
        } catch (e: Exception) {
            false
        }
    }

    private fun keyName(keyCode: Int): String? = when (keyCode) {
        KeyEvent.KEYCODE_DPAD_UP -> "up"
        KeyEvent.KEYCODE_DPAD_DOWN -> "down"
        KeyEvent.KEYCODE_DPAD_LEFT -> "left"
        KeyEvent.KEYCODE_DPAD_RIGHT -> "right"
        KeyEvent.KEYCODE_DPAD_CENTER,
        KeyEvent.KEYCODE_ENTER,
        KeyEvent.KEYCODE_NUMPAD_ENTER,
        KeyEvent.KEYCODE_BUTTON_A -> "center"
        else -> null
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val name = keyName(event.keyCode)
        if (intercepting && name != null) {
            if (event.action == KeyEvent.ACTION_DOWN) {
                channel?.invokeMethod(
                    "onKey",
                    mapOf("key" to name, "repeat" to event.repeatCount)
                )
            }
            // Consume both DOWN and UP so the WebView never also reacts to
            // the same press (which would scroll the page underneath us).
            return true
        }
        return super.dispatchKeyEvent(event)
    }
}
