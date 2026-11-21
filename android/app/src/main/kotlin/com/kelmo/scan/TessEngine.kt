// Kelmo Scan - document scanner
// Copyright (C) 2026 Kelmo
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 of the License.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

package com.kelmo.scan

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
import com.googlecode.tesseract.android.TessBaseAPI
import java.io.File
import kotlin.math.sqrt

/**
 * Offline OCR (Tesseract 5, Apache-2.0).
 * Language packs (*.traineddata) live in  android/app/src/main/assets/tessdata/  and are copied to
 * filesDir/tesseract/tessdata/ once per app start (Tesseract needs real files).
 * TessBaseAPI is NOT thread-safe -> cached instances, every public call is @Synchronized.
 */
object TessEngine {
    private val apis = HashMap<String, TessBaseAPI>()
    private var prepared = false

    private fun prepareData(ctx: Context): File {
        val base = File(ctx.filesDir, "tesseract")
        val dir = File(base, "tessdata").apply { mkdirs() }
        if (!prepared) {
            ctx.assets.list("tessdata")?.forEach { name ->
                ctx.assets.open("tessdata/$name").use { i -> File(dir, name).outputStream().use { o -> i.copyTo(o) } }
            }
            prepared = true
        }
        return base
    }

    private fun engine(base: File, langs: String): TessBaseAPI {
        apis[langs]?.let { return it }
        for (l in langs.split("+")) {
            if (!File(base, "tessdata/$l.traineddata").exists())
                throw IllegalStateException("Language data '$l.traineddata' is missing (assets/tessdata)")
        }
        val t = TessBaseAPI()
        if (!t.init(base.absolutePath, langs)) {
            t.recycle()
            throw IllegalStateException("Tesseract could not load '$langs'")
        }
        // A bitmap has no DPI info; without this Tesseract assumes ~70 dpi.
        t.setVariable("user_defined_dpi", "300")
        t.setVariable("preserve_interword_spaces", "1")
        apis[langs] = t
        return t
    }

    /** Whole page in one go (good for English / Latin text). */
    @Synchronized
    fun recognize(ctx: Context, bmp: Bitmap, langs: String): String {
        val t = engine(prepareData(ctx), langs)
        t.setPageSegMode(TessBaseAPI.PageSegMode.PSM_AUTO)
        t.setImage(bmp)
        val text = t.getUTF8Text() ?: ""
        t.clear()
        return text
    }

    /**
     * One image per text line (see DocumentProcessor.segmentLines). Each requested language runs as its
     * OWN single-language engine and the result with the higher mean confidence wins per line, so Urdu
     * lines are not polluted by Latin garbage and English lines stay English.
     */
    @Synchronized
    fun recognizeLines(ctx: Context, lines: List<Bitmap>, langs: String): String {
        val base = prepareData(ctx)
        val engines = langs.split("+").map { engine(base, it) }
        val out = StringBuilder()
        for (bmp in lines) {
            var best = ""
            var bestConf = -1
            for (t in engines) {
                t.setPageSegMode(TessBaseAPI.PageSegMode.PSM_SINGLE_LINE)
                t.setImage(bmp)
                val txt = (t.getUTF8Text() ?: "").trim()
                val conf = t.meanConfidence()
                t.clear()
                if (txt.isNotEmpty() && conf > bestConf) { best = txt; bestConf = conf }
            }
            if (best.isNotEmpty()) out.append(best.replace('\n', ' ')).append('\n')
        }
        return out.toString()
    }

    /** Auto language: reads a small copy with English and with Urdu, keeps the one Tesseract is surer of. */
    @Synchronized
    fun detectLang(ctx: Context, bmp: Bitmap): String {
        val base = prepareData(ctx)
        fun conf(lang: String): Int {
            val t = engine(base, lang)
            t.setPageSegMode(TessBaseAPI.PageSegMode.PSM_AUTO)
            t.setImage(bmp)
            t.getUTF8Text()
            val c = t.meanConfidence()
            t.clear()
            return c
        }
        val en = conf("eng")
        val ur = conf("urd")
        return if (ur > en) "urd" else "eng"
    }

    /** Which rotation (0/90/180/270 clockwise) makes the text readable? Probe on a small copy. */
    @Synchronized
    fun bestRotation(ctx: Context, bmp: Bitmap, lang: String = "eng"): Int {
        val t = engine(prepareData(ctx), lang)
        t.setPageSegMode(TessBaseAPI.PageSegMode.PSM_AUTO)
        var best = 0
        var bestScore = -1.0
        var score0 = 0.0
        for (rot in intArrayOf(0, 90, 180, 270)) {
            val b = if (rot == 0) bmp
                    else Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, Matrix().apply { postRotate(rot.toFloat()) }, true)
            t.setImage(b)
            val txt = t.getUTF8Text() ?: ""
            val conf = t.meanConfidence()
            t.clear()
            if (rot != 0) b.recycle()
            val score = conf * sqrt(txt.count { it.isLetterOrDigit() }.toDouble())
            if (rot == 0) score0 = score
            if (score > bestScore) { bestScore = score; best = rot }
        }
        return if (best != 0 && bestScore > score0 * 1.3 + 5) best else 0
    }

    /** Passport MRZ: restricted alphabet (A-Z 0-9 <) and one text block. */
    @Synchronized
    fun recognizeMrz(ctx: Context, bmp: Bitmap): String {
        val t = engine(prepareData(ctx), "eng")
        t.setPageSegMode(TessBaseAPI.PageSegMode.PSM_SINGLE_BLOCK)
        t.setVariable("tessedit_char_whitelist", "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789<")
        t.setImage(bmp)
        val text = t.getUTF8Text() ?: ""
        t.clear()
        t.setVariable("tessedit_char_whitelist", "")
        return text
    }
}
