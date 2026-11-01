package com.hy320.keyboard;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.RectF;
import android.inputmethodservice.InputMethodService;
import android.view.KeyEvent;
import android.view.View;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;

/**
 * A keyboard for a device whose only input is a four-way pad and an OK button.
 *
 * Both keyboards that were on this projector fail it, in opposite directions. Android's own
 * gives the pad to its keys, so you can type but can never move the text cursor: a typo in
 * the middle of a word means deleting back to it. HeliBoard gives the pad to the cursor
 * instead -- measured here, left and right really do move it -- but then no key is ever
 * focused, so with a remote you cannot type at all. One pad cannot do two jobs, and neither
 * keyboard was written for a device that has nothing else.
 *
 * So this one puts the arrows *on the keyboard*, as keys like any other. The pad walks the
 * keys, OK presses one, and two of those keys happen to move the cursor.
 *
 * Everything else about it is Android's own keyboard, copied rather than imitated. The
 * colours, the key grid, the text sizes and the three icons were all measured off
 * screenshots of the real thing on this screen -- see the runbook -- so the only thing that
 * should look different is the bottom row, which is where the arrows had to go. The letter
 * layer's bottom row follows the symbol layer's shape to make room for them: comma and full
 * stop move together to the left of the space bar, and the two keys on its right become the
 * arrows. The other two layers were lined up with it, so comma and full stop sit in the
 * same two places whichever layer you are on, and whatever they displaced moved right.
 *
 * It asks for no permissions and has no network: a keyboard sees every password typed on
 * the projector, which is reason enough to keep it small enough to read in one sitting.
 */
public class KeyboardService extends InputMethodService {

    private static final int TEXT = 0;
    private static final int SPACE = 1;
    private static final int SHIFT = 2;
    private static final int BACKSPACE = 3;
    private static final int ENTER = 4;
    private static final int LAYER = 5;     // switches to another layer; `layer` says which
    private static final int LEFT = 6;
    private static final int RIGHT = 7;

    /** The grid is ten cells wide on every layer; a key is one of them unless it says so. */
    private static final float CELLS = 10f;

    /** One key: what it says, how wide it is in cells, and what pressing it does. */
    private static final class Key {
        final String label;
        final float cells;
        final int kind;
        final int layer;

        Key(String label, float cells, int kind, int layer) {
            this.label = label;
            this.cells = cells;
            this.kind = kind;
            this.layer = layer;
        }
    }

    private static Key k(String label) {
        return new Key(label, 1f, TEXT, -1);
    }

    private static Key icon(int kind, float cells) {
        return new Key(null, cells, kind, -1);
    }

    private static Key to(String label, int layer) {
        return new Key(label, 1.5f, LAYER, layer);
    }

    private static final int LETTERS = 0;
    private static final int SYMBOLS = 1;
    private static final int MORE = 2;

    private static final Key[][][] LAYERS = {
            {   // letters
                    {k("q"), k("w"), k("e"), k("r"), k("t"), k("y"), k("u"), k("i"), k("o"), k("p")},
                    {k("a"), k("s"), k("d"), k("f"), k("g"), k("h"), k("j"), k("k"), k("l")},
                    {icon(SHIFT, 1.5f), k("z"), k("x"), k("c"), k("v"), k("b"), k("n"), k("m"),
                            icon(BACKSPACE, 1.5f)},
                    {to("?123", SYMBOLS), k(","), k("."), icon(SPACE, 3f),
                            new Key("←", 1f, LEFT, -1), new Key("→", 1f, RIGHT, -1),
                            icon(ENTER, 1.5f)},
            },
            {   // ?123
                    {k("1"), k("2"), k("3"), k("4"), k("5"), k("6"), k("7"), k("8"), k("9"), k("0")},
                    {k("@"), k("#"), k("$"), k("%"), k("&"), k("-"), k("+"), k("("), k(")")},
                    {to("= \\ <", MORE), k("*"), k("\""), k("'"), k(":"), k(";"), k("!"), k("?"),
                            icon(BACKSPACE, 1.5f)},
                    {to("ABC", LETTERS), k(","), k("."), icon(SPACE, 3f), k("/"), k("_"),
                            icon(ENTER, 1.5f)},
            },
            {   // = \ <
                    {k("~"), k("`"), k("|"), k("•"), k("√"), k("π"), k("÷"), k("×"), k("¶"), k("Δ")},
                    {k("£"), k("¢"), k("€"), k("¥"), k("^"), k("°"), k("="), k("{"), k("}")},
                    {to("?123", SYMBOLS), k("\\"), k("©"), k("®"), k("™"), k("%"), k("["), k("]"),
                            icon(BACKSPACE, 1.5f)},
                    {to("ABC", LETTERS), k(","), k("."), icon(SPACE, 3f), k("<"), k(">"),
                            icon(ENTER, 1.5f)},
            },
    };

    private KeyboardView view;
    private int layer = LETTERS;
    private boolean shifted = false;
    private int row = 0;
    private int column = 0;

    @Override
    public View onCreateInputView() {
        view = new KeyboardView(this);
        return view;
    }

    /**
     * Always draw the keys.
     *
     * Android hides a soft keyboard's view when it believes a hardware keyboard is
     * attached, and this projector's infra-red remote is enough to make it believe that:
     * the keys worked from the first build but nothing was on the screen.
     */
    @Override
    public boolean onEvaluateInputViewShown() {
        return true;
    }

    /**
     * Never take the whole screen.
     *
     * In landscape Android's default is to go fullscreen and put its own copy of the text
     * above the keys, which on a projector would hide the app being typed into.
     */
    @Override
    public boolean onEvaluateFullscreenMode() {
        return false;
    }

    @Override
    public void onStartInputView(EditorInfo info, boolean restarting) {
        super.onStartInputView(info, restarting);
        layer = LETTERS;
        shifted = false;
        row = 0;
        column = 0;
        if (view != null) {
            view.invalidate();
        }
    }

    /**
     * The pad and OK, while this keyboard is up.
     *
     * Everything else is left alone, so the remote's back and home keys still do what they
     * always did -- in particular back still closes the keyboard.
     */
    @Override
    public boolean onKeyDown(int code, KeyEvent event) {
        // Only while the keys are actually on the screen. A bound keyboard is handed every
        // key the focused window sees, whether or not anything is being typed into: taking
        // the pad here as well left the home screen unable to move its own selection, which
        // is how this was found.
        if (!isInputViewShown()) {
            return super.onKeyDown(code, event);
        }
        switch (code) {
            case KeyEvent.KEYCODE_DPAD_LEFT:
                across(-1);
                return true;
            case KeyEvent.KEYCODE_DPAD_RIGHT:
                across(1);
                return true;
            case KeyEvent.KEYCODE_DPAD_UP:
                down(-1);
                return true;
            case KeyEvent.KEYCODE_DPAD_DOWN:
                down(1);
                return true;
            case KeyEvent.KEYCODE_DPAD_CENTER:
            case KeyEvent.KEYCODE_ENTER:
                press(keys()[row][column]);
                return true;
            default:
                return super.onKeyDown(code, event);
        }
    }

    private Key[][] keys() {
        return LAYERS[layer];
    }

    /** Steps along a row, wrapping at both ends so no press does nothing. */
    private void across(int by) {
        int width = keys()[row].length;
        column = (column + by + width) % width;
        view.invalidate();
    }

    /**
     * Steps between rows, landing on whichever key is under the one just left.
     *
     * The rows are not the same shape -- a key can be one cell wide or three -- so this
     * keeps the place across the keyboard rather than the place in the list, which is what
     * the eye follows.
     */
    private void down(int by) {
        float wanted = centreOf(row, column);
        row = (row + by + keys().length) % keys().length;
        column = nearest(row, wanted);
        view.invalidate();
    }

    /** Where a key sits across the grid, in cells, measured at its middle. */
    private float centreOf(int r, int c) {
        Key[] line = keys()[r];
        float x = indent(line);
        for (int i = 0; i < c; i++) {
            x += line[i].cells;
        }
        return x + line[c].cells / 2f;
    }

    private int nearest(int r, float centre) {
        Key[] line = keys()[r];
        float x = indent(line);
        for (int i = 0; i < line.length; i++) {
            if (centre < x + line[i].cells) {
                return i;
            }
            x += line[i].cells;
        }
        return line.length - 1;
    }

    /** A row of fewer than ten cells sits in the middle, as the stock keyboard's does. */
    private static float indent(Key[] line) {
        float total = 0;
        for (Key key : line) {
            total += key.cells;
        }
        return (CELLS - total) / 2f;
    }

    private void press(Key key) {
        InputConnection ic = getCurrentInputConnection();
        if (ic == null) {
            return;
        }
        switch (key.kind) {
            case SHIFT:
                shifted = !shifted;
                break;
            case LAYER:
                layer = key.layer;
                shifted = false;
                row = Math.min(row, keys().length - 1);
                column = Math.min(column, keys()[row].length - 1);
                break;
            case BACKSPACE:
                // A selection is deleted by replacing it; otherwise one character goes.
                if (ic.getSelectedText(0) != null) {
                    ic.commitText("", 1);
                } else {
                    ic.deleteSurroundingText(1, 0);
                }
                break;
            case LEFT:
                sendDownUpKeyEvents(KeyEvent.KEYCODE_DPAD_LEFT);
                break;
            case RIGHT:
                sendDownUpKeyEvents(KeyEvent.KEYCODE_DPAD_RIGHT);
                break;
            case ENTER:
                // Search boxes and "done" buttons want the editor's own action, not a newline.
                if (!sendDefaultEditorAction(true)) {
                    sendDownUpKeyEvents(KeyEvent.KEYCODE_ENTER);
                }
                break;
            case SPACE:
                ic.commitText(" ", 1);
                break;
            default:
                ic.commitText(shifted ? key.label.toUpperCase() : key.label, 1);
                shifted = false;        // one capital, like every other keyboard
        }
        view.invalidate();
    }

    /**
     * Android's own keyboard, redrawn.
     *
     * Every number here was measured off a screenshot of the stock keyboard on this screen
     * rather than chosen, which is why they are the odd sizes they are. At this screen's
     * density of 2 the grid comes out at the same pixels it does there.
     */
    final class KeyboardView extends View {

        private static final int BACKGROUND = 0xFFECEFF1;
        private static final int INK = 0xFF37474F;          // letters, digits, punctuation
        private static final int QUIET_INK = 0xFF5B696F;    // the ?123 / ABC / = \ < keys
        private static final int SPACE_BAR = 0xFFD1D6D9;
        private static final int FOCUS = 0xFF00FF00;

        private static final float PANEL_DP = 243f;         // 486px, the stock panel's height
        private static final float ROW_DP = 62f;            // 124px between row middles
        private static final float KEY_HEIGHT_DP = 51f;     // 102px, from the focus outline
        private static final float KEY_INSET_DP = 4f;       // 8px either side of its cell
        private static final float KEY_LIFT_DP = 1f;        // the outline sits 2px above the text
        private static final float TEXT_DP = 32f;           // 64px: cap height measured 45px
        private static final float QUIET_TEXT_DP = 19.5f;   // the ?123 keys, measured 30px tall
        private static final float TEXT_DROP_DP = 0.6f;     // what the first build was out by
        private static final float BAR_HEIGHT_DP = 23.5f;   // 47px
        private static final float FOCUS_STROKE_DP = 2.5f;  // 5px

        private final Paint fill = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint label = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint outline = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final float density;

        private final Bitmap shiftIcon;
        private final Bitmap backspaceIcon;
        private final Bitmap enterIcon;

        KeyboardView(Context context) {
            super(context);
            density = context.getResources().getDisplayMetrics().density;
            setBackgroundColor(BACKGROUND);
            fill.setStyle(Paint.Style.FILL);
            label.setTextAlign(Paint.Align.CENTER);
            outline.setStyle(Paint.Style.STROKE);
            outline.setColor(FOCUS);
            outline.setStrokeWidth(dp(FOCUS_STROKE_DP));
            outline.setAntiAlias(false);        // the stock outline has hard square corners
            shiftIcon = load(context, "key_shift");
            backspaceIcon = load(context, "key_backspace");
            enterIcon = load(context, "key_enter");
        }

        private Bitmap load(Context context, String name) {
            try {
                return BitmapFactory.decodeStream(context.getAssets().open(name + ".png"));
            } catch (Throwable t) {
                return null;        // the key still works, just without its picture
            }
        }

        private float dp(float v) {
            return v * density;
        }

        @Override
        protected void onMeasure(int widthSpec, int heightSpec) {
            // The stock panel is 486px tall here while its four rows come to 496, so its
            // last row is clipped by ten pixels at the bottom of the screen. Taking the
            // measured height and letting the same thing happen keeps the two identical.
            setMeasuredDimension(MeasureSpec.getSize(widthSpec), (int) dp(PANEL_DP));
        }

        @Override
        protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            Key[][] rows = keys();
            float cell = getWidth() / CELLS;
            float pitch = dp(ROW_DP);
            float keyHeight = dp(KEY_HEIGHT_DP);
            float insetX = dp(KEY_INSET_DP);

            for (int r = 0; r < rows.length; r++) {
                Key[] line = rows[r];
                float middle = r * pitch + pitch / 2f;
                float x = indent(line) * cell;
                for (int c = 0; c < line.length; c++) {
                    Key key = line[c];
                    float boxMiddle = middle - dp(KEY_LIFT_DP);
                    RectF box = new RectF(x + insetX, boxMiddle - keyHeight / 2f,
                            x + key.cells * cell - insetX, boxMiddle + keyHeight / 2f);
                    draw(canvas, key, box, cell, middle);
                    if (r == row && c == column) {
                        // Inside the key, not straddling its edge: a stroke is drawn
                        // centred on the line it is given, and the stock outline is not.
                        float half = outline.getStrokeWidth() / 2f;
                        canvas.drawRect(box.left + half, box.top + half,
                                box.right - half, box.bottom - half, outline);
                    }
                    x += key.cells * cell;
                }
            }
        }

        private void draw(Canvas canvas, Key key, RectF box, float cell, float middle) {
            switch (key.kind) {
                case SPACE:
                    fill.setColor(SPACE_BAR);
                    float bar = dp(BAR_HEIGHT_DP);
                    canvas.drawRoundRect(
                            new RectF(box.left + dp(1), middle - bar / 2f,
                                    box.right - dp(1), middle + bar / 2f),
                            dp(2), dp(2), fill);
                    return;
                case SHIFT:
                    // Measured where the stock one sits: its underline bar hangs below the
                    // arrow, so the picture as a whole is not centred in the key.
                    picture(canvas, shiftIcon, box.centerX() - dp(4.25f), middle + dp(7.25f));
                    return;
                case BACKSPACE:
                    picture(canvas, backspaceIcon, box.centerX() + dp(5), middle);
                    return;
                case ENTER:
                    picture(canvas, enterIcon, box.centerX(), middle);
                    return;
                default:
                    boolean quiet = key.kind == LAYER;
                    label.setTextSize(dp(quiet ? QUIET_TEXT_DP : TEXT_DP));
                    label.setColor(quiet ? QUIET_INK : INK);
                    String text = key.label;
                    if (shifted && key.kind == TEXT && text.length() == 1
                            && Character.isLetter(text.charAt(0))) {
                        text = text.toUpperCase();
                    }
                    Paint.FontMetrics fm = label.getFontMetrics();
                    canvas.drawText(text, box.centerX(),
                            middle + dp(TEXT_DROP_DP) - (fm.ascent + fm.descent) / 2f, label);
            }
        }

        /** Draws an icon at its own size, centred where it was measured to sit. */
        private void picture(Canvas canvas, Bitmap picture, float cx, float cy) {
            if (picture == null) {
                return;
            }
            canvas.drawBitmap(picture, cx - picture.getWidth() / 2f,
                    cy - picture.getHeight() / 2f, null);
        }
    }
}
