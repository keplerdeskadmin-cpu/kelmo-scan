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

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.exifinterface.media.ExifInterface
import org.opencv.android.Utils
import org.opencv.core.*
import org.opencv.imgproc.Imgproc
import java.io.FileOutputStream
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.sqrt

/**
 * All OpenCV work lives here.
 *
 * MEMORY MODEL
 * ------------
 * org.opencv.core.Mat owns NATIVE (C++) memory that the JVM garbage collector
 * cannot see. A forgotten Mat = a leak that survives GC. Every function below
 * therefore allocates through [Scope.track]; the Scope releases every tracked
 * Mat in `finally`, even if an exception is thrown.
 *
 * Conversions (each copies exactly once):
 *   file  → Bitmap (EXIF-rotated, optionally down-sampled with inSampleSize)
 *   Bitmap → Mat  (Utils.bitmapToMat, RGBA 8U)  → Bitmap recycled immediately
 *   camera Y bytes → Mat (Mat.put, 8U1)          → submat() shares memory (no copy)
 */
object DocumentProcessor {

    /** Tracks native Mats and frees them deterministically. */
    class Scope : AutoCloseable {
        private val mats = ArrayList<Mat>()
        fun <T : Mat> track(m: T): T { mats.add(m); return m }
        override fun close() { mats.forEach { it.release() }; mats.clear() }
    }

    // ───────────────────────── I/O helpers ─────────────────────────

    private fun loadBitmap(path: String, maxSide: Int): Bitmap {
        val opts = BitmapFactory.Options()
        if (maxSide > 0) {
            opts.inJustDecodeBounds = true
            BitmapFactory.decodeFile(path, opts)
            var sample = 1
            while (max(opts.outWidth, opts.outHeight) / (sample * 2) >= maxSide) sample *= 2
            opts.inJustDecodeBounds = false
            opts.inSampleSize = sample
        }
        var bmp = BitmapFactory.decodeFile(path, opts) ?: error("Cannot decode $path")
        val deg = when (ExifInterface(path).getAttributeInt(ExifInterface.TAG_ORIENTATION, 1)) {
            ExifInterface.ORIENTATION_ROTATE_90 -> 90
            ExifInterface.ORIENTATION_ROTATE_180 -> 180
            ExifInterface.ORIENTATION_ROTATE_270 -> 270
            else -> 0
        }
        if (deg != 0) {
            val r = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, Matrix().apply { postRotate(deg.toFloat()) }, true)
            bmp.recycle(); bmp = r
        }
        return bmp
    }

    private fun loadMat(path: String, maxSide: Int, s: Scope): Mat {
        val bmp = loadBitmap(path, maxSide)
        val m = s.track(Mat())
        Utils.bitmapToMat(bmp, m)       // RGBA
        bmp.recycle()                   // free the Java copy at once
        return m
    }

    private fun save(m: Mat, path: String, s: Scope, quality: Int = 92) {
        val rgba = when (m.channels()) {
            4 -> m
            1 -> s.track(Mat()).also { Imgproc.cvtColor(m, it, Imgproc.COLOR_GRAY2RGBA) }
            else -> s.track(Mat()).also { Imgproc.cvtColor(m, it, Imgproc.COLOR_RGB2RGBA) }
        }
        val bmp = Bitmap.createBitmap(rgba.cols(), rgba.rows(), Bitmap.Config.ARGB_8888)
        Utils.matToBitmap(rgba, bmp)
        FileOutputStream(path).use { bmp.compress(Bitmap.CompressFormat.JPEG, quality, it) }
        bmp.recycle()
    }

    // ───────────────────── A. Document detection ─────────────────────

    /** Accepted long/short side ratio of the quad (A4 = 1.41, Letter = 1.29, ID = 1.59). */
    private const val MAX_ASPECT = 2.2
    private const val MIN_AREA_FRACTION = 0.15

    /**
     * Gray → Gaussian blur → Canny → dilate → findContours → approxPolyDP →
     * keep the largest convex 4-gon with a document-like aspect ratio.
     * Returns 8 normalised doubles (TL,TR,BR,BL) or null.
     */
    private fun findQuad(gray: Mat, s: Scope): DoubleArray? {
        val scale = 500.0 / max(gray.rows(), gray.cols())
        val small = s.track(Mat()); Imgproc.resize(gray, small, Size(), scale, scale, Imgproc.INTER_AREA)
        val blur = s.track(Mat());  Imgproc.GaussianBlur(small, blur, Size(5.0, 5.0), 0.0)
        val edges = s.track(Mat()); Imgproc.Canny(blur, edges, 50.0, 150.0)
        val k = s.track(Imgproc.getStructuringElement(Imgproc.MORPH_RECT, Size(3.0, 3.0)))
        Imgproc.dilate(edges, edges, k)                       // close small gaps in the border

        val contours = ArrayList<MatOfPoint>()
        val hier = s.track(Mat())
        Imgproc.findContours(edges, contours, hier, Imgproc.RETR_LIST, Imgproc.CHAIN_APPROX_SIMPLE)

        val imgArea = small.rows().toDouble() * small.cols()
        var best: Array<Point>? = null
        var bestArea = 0.0
        for (c in contours) {
            val c2f = MatOfPoint2f(*c.toArray())
            val approx = MatOfPoint2f()
            Imgproc.approxPolyDP(c2f, approx, 0.02 * Imgproc.arcLength(c2f, true), true)
            val pts = approx.toArray()
            if (pts.size == 4) {
                val mp = MatOfPoint(*pts)
                val area = abs(Imgproc.contourArea(approx))
                if (Imgproc.isContourConvex(mp) && area > imgArea * MIN_AREA_FRACTION && area > bestArea) {
                    val o = order(pts)
                    if (aspect(o) <= MAX_ASPECT) { best = o; bestArea = area }
                }
                mp.release()
            }
            c2f.release(); approx.release(); c.release()
        }
        return best?.let { q ->
            DoubleArray(8) { i -> if (i % 2 == 0) q[i / 2].x / small.cols() else q[i / 2].y / small.rows() }
        }
    }

    private fun order(p: Array<Point>): Array<Point> {
        val tl = p.minByOrNull { it.x + it.y }!!
        val br = p.maxByOrNull { it.x + it.y }!!
        val tr = p.minByOrNull { it.y - it.x }!!
        val bl = p.maxByOrNull { it.y - it.x }!!
        return arrayOf(tl, tr, br, bl)
    }

    private fun dist(a: Point, b: Point) = sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y))

    private fun aspect(o: Array<Point>): Double {
        val w = (dist(o[0], o[1]) + dist(o[3], o[2])) / 2
        val h = (dist(o[0], o[3]) + dist(o[1], o[2])) / 2
        return max(w, h) / kotlin.math.min(w, h).coerceAtLeast(1.0)
    }

    /** Camera frame: [bytes] is the Y plane (already grayscale). */
    fun detectFrame(bytes: ByteArray, w: Int, h: Int, rowStride: Int, rotation: Int): DoubleArray? =
        Scope().use { s ->
            val raw = s.track(Mat(h, rowStride, CvType.CV_8UC1))
            raw.put(0, 0, bytes)                               // one copy: Java → native
            val gray = s.track(raw.submat(0, h, 0, w))         // crop row padding, zero-copy
            val rot = s.track(Mat())
            when (rotation) {
                90 -> Core.rotate(gray, rot, Core.ROTATE_90_CLOCKWISE)
                180 -> Core.rotate(gray, rot, Core.ROTATE_180)
                270 -> Core.rotate(gray, rot, Core.ROTATE_90_COUNTERCLOCKWISE)
                else -> gray.copyTo(rot)
            }
            findQuad(rot, s)
        }

    fun detectCorners(path: String): DoubleArray? = Scope().use { s ->
        val rgba = loadMat(path, 1200, s)
        val gray = s.track(Mat()); Imgproc.cvtColor(rgba, gray, Imgproc.COLOR_RGBA2GRAY)
        findQuad(gray, s)
    }

    // ───────────────────── B. Perspective transform ─────────────────────

    private val STANDARD_RATIOS = doubleArrayOf(1.4142 /*A4*/, 1.2941 /*Letter*/)

    fun warp(path: String, norm: DoubleArray, outPath: String) = Scope().use { s ->
        val src = loadMat(path, 3200, s)
        val pts = order(Array(4) { Point(norm[it * 2] * src.cols(), norm[it * 2 + 1] * src.rows()) })
        var w = max(dist(pts[0], pts[1]), dist(pts[3], pts[2]))
        var h = max(dist(pts[0], pts[3]), dist(pts[1], pts[2]))

        // Snap to A4 / Letter when within 8 % (portrait or landscape).
        val portrait = h >= w
        val r = if (portrait) h / w else w / h
        STANDARD_RATIOS.minByOrNull { abs(it - r) }?.let { std ->
            if (abs(std - r) / std < 0.08) { if (portrait) h = w * std else w = h * std }
        }

        val from = s.track(MatOfPoint2f(*pts))
        val to = s.track(MatOfPoint2f(Point(0.0, 0.0), Point(w, 0.0), Point(w, h), Point(0.0, h)))
        val m = s.track(Imgproc.getPerspectiveTransform(from, to))
        val dst = s.track(Mat())
        Imgproc.warpPerspective(src, dst, m, Size(w, h), Imgproc.INTER_CUBIC, Core.BORDER_REPLICATE)
        save(dst, outPath, s)
    }

    fun rotate(path: String, outPath: String) = Scope().use { s ->
        val src = loadMat(path, 0, s)
        val dst = s.track(Mat()); Core.rotate(src, dst, Core.ROTATE_90_CLOCKWISE)
        save(dst, outPath, s)
    }

    /** Re-encodes an image for sharing: long side <= maxSide, JPEG [quality]. */
    fun shrink(path: String, maxSide: Int, quality: Int, outPath: String) = Scope().use { s ->
        val img = loadMat(path, 0, s)
        val longSide = max(img.cols(), img.rows())
        val out = if (longSide > maxSide) {
            val f = maxSide.toDouble() / longSide
            s.track(Mat()).also { Imgproc.resize(img, it, Size(), f, f, Imgproc.INTER_AREA) }
        } else img
        save(out, outPath, s, quality)
    }

    // ───────────────────── Redaction (permanent) ─────────────────────

    /**
     * Bakes marks into the pixels. [marks] = repeated groups of 5 numbers:
     * type (0 redact = solid black, 1 blur = coarse pixelation, 2 highlight = yellow), then x0,y0,x1,y1 normalised 0..1.
     * Redact/blur destroy the information; the Dart side also replaces the stored original so nothing can be recovered.
     */
    fun applyMarks(path: String, marks: DoubleArray, outPath: String) = Scope().use { s ->
        val img = loadMat(path, 0, s)                       // RGBA
        var i = 0
        while (i + 4 < marks.size) {
            val type = marks[i].toInt()
            val x0 = (minOf(marks[i + 1], marks[i + 3]) * img.cols()).toInt().coerceIn(0, img.cols() - 1)
            val x1 = (max(marks[i + 1], marks[i + 3]) * img.cols()).toInt().coerceIn(x0, img.cols())
            val y0 = (minOf(marks[i + 2], marks[i + 4]) * img.rows()).toInt().coerceIn(0, img.rows() - 1)
            val y1 = (max(marks[i + 2], marks[i + 4]) * img.rows()).toInt().coerceIn(y0, img.rows())
            val w = x1 - x0
            val h = y1 - y0
            if (w >= 2 && h >= 2) {
                val roi = s.track(img.submat(y0, y1, x0, x1))
                when (type) {
                    0 -> roi.setTo(Scalar(0.0, 0.0, 0.0, 255.0))
                    3 -> roi.setTo(Scalar(255.0, 255.0, 255.0, 255.0))   // whiteout (eraser)
                    1 -> {
                        val cell = max(14, h / 2)
                        val small = Mat()
                        Imgproc.resize(roi, small, Size(max(1, w / cell).toDouble(), max(1, h / cell).toDouble()), 0.0, 0.0, Imgproc.INTER_AREA)
                        Imgproc.resize(small, roi, roi.size(), 0.0, 0.0, Imgproc.INTER_NEAREST)
                        small.release()
                    }
                    else -> Core.multiply(roi, Scalar(255.0, 235.0, 59.0, 255.0), roi, 1.0 / 255.0)
                }
            }
            i += 5
        }
        save(img, outPath, s)
    }

    // ───────────────────── ID-card page composer ─────────────────────

    /** White A4 page @300 dpi (2480×3508) with front on the upper and back on the lower half. */
    fun composeId(frontPath: String, backPath: String, outPath: String) = Scope().use { s ->
        val pageW = 2480
        val pageH = 3508
        val page = s.track(Mat(pageH, pageW, CvType.CV_8UC4, Scalar(255.0, 255.0, 255.0, 255.0)))
        val cardW = (pageW * 0.62).toInt()
        val x = (pageW - cardW) / 2

        fun place(path: String, topY: Int) {
            val src = loadMat(path, 0, s)
            val h = (src.rows() * cardW.toDouble() / src.cols()).toInt()
            val resized = s.track(Mat())
            Imgproc.resize(src, resized, Size(cardW.toDouble(), h.toDouble()), 0.0, 0.0, Imgproc.INTER_AREA)
            val hh = minOf(h, pageH - topY)                         // never draw outside the page
            val srcRoi = s.track(resized.submat(0, hh, 0, cardW))
            val dstRoi = s.track(page.submat(topY, topY + hh, x, x + cardW))
            srcRoi.copyTo(dstRoi)
            Imgproc.rectangle(page, Point(x.toDouble(), topY.toDouble()),
                Point((x + cardW).toDouble(), (topY + hh).toDouble()), Scalar(190.0, 190.0, 190.0, 255.0), 3)
        }
        place(frontPath, 450)
        place(backPath, 1850)
        save(page, outPath, s)
    }

    private fun rotateMat(m: Mat, deg: Int, s: Scope): Mat {
        if (deg == 0) return m
        val out = s.track(Mat())
        Core.rotate(m, out, when (deg) {
            90 -> Core.ROTATE_90_CLOCKWISE
            180 -> Core.ROTATE_180
            else -> Core.ROTATE_90_COUNTERCLOCKWISE
        })
        return out
    }

    // ───────────────────── OCR pre-processing ─────────────────────

    /** Shadow-free grayscale bitmap (long side <= maxSide) – Tesseract reads this much better than a raw photo. */
    fun prepareForOcr(path: String, maxSide: Int, rotate: Int = 0): Bitmap = Scope().use { s ->
        val rgba = rotateMat(loadMat(path, maxSide, s), rotate, s)
        val gray = flatten(toGray(rgba, s), s)
        val out = s.track(Mat()); Imgproc.cvtColor(gray, out, Imgproc.COLOR_GRAY2RGBA)
        val bmp = Bitmap.createBitmap(out.cols(), out.rows(), Bitmap.Config.ARGB_8888)
        Utils.matToBitmap(out, bmp)
        bmp                                   // caller must recycle()
    }

    // ───────────────────── Line segmentation (Urdu OCR) ─────────────────────

    /** Tilt of the text lines in degrees: the rotation that makes the row-projection of ink most "peaky". */
    private fun estimateSkew(bin: Mat): Double {
        val scale = 900.0 / max(bin.cols(), bin.rows())
        val small = Mat(); Imgproc.resize(bin, small, Size(), scale, scale, Imgproc.INTER_AREA)
        val c = Point(small.cols() / 2.0, small.rows() / 2.0)
        fun score(a: Double): Double {
            val rot = Imgproc.getRotationMatrix2D(c, a, 1.0)
            val r = Mat(); Imgproc.warpAffine(small, r, rot, small.size())
            val proj = Mat(); Core.reduce(r, proj, 1, Core.REDUCE_SUM, CvType.CV_32F)
            val mu = MatOfDouble(); val sd = MatOfDouble(); Core.meanStdDev(proj, mu, sd)
            val v = sd.get(0, 0)[0]
            rot.release(); r.release(); proj.release(); mu.release(); sd.release()
            return v
        }
        var best = 0.0; var bestS = -1.0
        var a = -6.0
        while (a <= 6.0) { val v = score(a); if (v > bestS) { bestS = v; best = a }; a += 0.5 }
        a = best - 0.5
        val end = best + 0.5
        while (a <= end) { val v = score(a); if (v > bestS) { bestS = v; best = a }; a += 0.1 }
        small.release()
        return best
    }

    private fun rotateBy(m: Mat, deg: Double, fill: Double, s: Scope): Mat {
        val rot = s.track(Imgproc.getRotationMatrix2D(Point(m.cols() / 2.0, m.rows() / 2.0), deg, 1.0))
        val out = s.track(Mat())
        Imgproc.warpAffine(m, out, rot, m.size(), Imgproc.INTER_LINEAR, Core.BORDER_CONSTANT, Scalar(fill))
        return out
    }

    /**
     * Splits a page into text-line images (top to bottom): shadow-free gray -> Otsu ink mask ->
     * deskew -> row projection -> runs of ink rows = lines. Each line is cropped, padded, and
     * scaled to a sane height so Tesseract can read it with PSM_SINGLE_LINE.
     * (Tesseract's own layout analysis is weak on Nastaliq; this is what fixes broken/merged lines.)
     * Caller must recycle() the bitmaps.
     */
    fun segmentLines(path: String, maxSide: Int, rotate: Int = 0): List<Bitmap> = Scope().use { s ->
        val rgba = rotateMat(loadMat(path, maxSide, s), rotate, s)
        val gray0 = flatten(toGray(rgba, s), s)
        val bin0 = s.track(Mat())
        Imgproc.threshold(gray0, bin0, 0.0, 255.0, Imgproc.THRESH_BINARY_INV or Imgproc.THRESH_OTSU)

        val ang = estimateSkew(bin0)
        val rotate = abs(ang) > 0.2
        val gray = if (rotate) rotateBy(gray0, ang, 255.0, s) else gray0
        val bin = if (rotate) rotateBy(bin0, ang, 0.0, s) else bin0

        val h = bin.rows(); val w = bin.cols()
        // ignore page edges / shadows / binding
        val mx = w * 3 / 100; val my = h * 2 / 100
        bin.submat(0, h, 0, mx).setTo(Scalar(0.0)); bin.submat(0, h, w - mx, w).setTo(Scalar(0.0))
        bin.submat(0, my, 0, w).setTo(Scalar(0.0)); bin.submat(h - my, h, 0, w).setTo(Scalar(0.0))

        val proj = s.track(Mat()); Core.reduce(bin, proj, 1, Core.REDUCE_SUM, CvType.CV_32F)
        val raw = FloatArray(h); proj.get(0, 0, raw)
        val half = max(1, h / 600)
        val sm = FloatArray(h) { i ->
            var sum = 0f; var n = 0
            for (j in max(0, i - half)..minOf(h - 1, i + half)) { sum += raw[j]; n++ }
            sum / n
        }
        val peak = sm.max()
        if (peak <= 0f) return@use emptyList<Bitmap>()
        val thr = peak * 0.07f

        var runs = ArrayList<IntArray>()
        var start = -1
        for (i in 0 until h) {
            if (sm[i] > thr) { if (start < 0) start = i }
            else if (start >= 0) { runs.add(intArrayOf(start, i - 1)); start = -1 }
        }
        if (start >= 0) runs.add(intArrayOf(start, h - 1))
        if (runs.isEmpty()) return@use emptyList<Bitmap>()

        val med = runs.map { it[1] - it[0] + 1 }.sorted()[runs.size / 2]
        // glue runs split by dots/diacritics, drop specks
        val merged = ArrayList<IntArray>()
        for (r in runs) {
            val last = merged.lastOrNull()
            if (last != null && r[0] - last[1] < med * 0.25) last[1] = r[1] else merged.add(r.copyOf())
        }
        runs = ArrayList(merged.filter { it[1] - it[0] + 1 >= max(14, (med * 0.35).toInt()) })

        val out = ArrayList<Bitmap>()
        for (r in runs) {
            val lh = r[1] - r[0] + 1
            val pad = max(6, lh / 6)
            val ya = max(0, r[0] - pad); val yb = minOf(h - 1, r[1] + pad)
            val band = bin.submat(ya, yb + 1, 0, w)
            val cols = Mat(); Core.reduce(band, cols, 0, Core.REDUCE_SUM, CvType.CV_32F)
            val c = FloatArray(w); cols.get(0, 0, c)
            cols.release(); band.release()
            var x0 = 0; while (x0 < w && c[x0] <= 0f) x0++
            var x1 = w - 1; while (x1 > x0 && c[x1] <= 0f) x1--
            if (x1 - x0 < 20) continue
            x0 = max(0, x0 - 20); x1 = minOf(w - 1, x1 + 20)

            val crop = s.track(gray.submat(ya, yb + 1, x0, x1 + 1))
            val f = if (lh < 48) 48.0 / lh else if (lh > 160) 160.0 / lh else 1.0
            val scaled = s.track(Mat())
            if (f != 1.0) Imgproc.resize(crop, scaled, Size(), f, f, if (f > 1) Imgproc.INTER_CUBIC else Imgproc.INTER_AREA)
            else crop.copyTo(scaled)
            val bordered = s.track(Mat())
            Core.copyMakeBorder(scaled, bordered, 12, 12, 12, 12, Core.BORDER_CONSTANT, Scalar(255.0))
            val rgbaLine = s.track(Mat()); Imgproc.cvtColor(bordered, rgbaLine, Imgproc.COLOR_GRAY2RGBA)
            val bmp = Bitmap.createBitmap(rgbaLine.cols(), rgbaLine.rows(), Bitmap.Config.ARGB_8888)
            Utils.matToBitmap(rgbaLine, bmp)
            out.add(bmp)
        }
        out
    }

    // ───────────────────── C. "Magic Filter" pipeline ─────────────────────

    fun applyFilter(path: String, mode: String, outPath: String, maxSide: Int) = Scope().use { s ->
        val rgba = loadMat(path, maxSide, s)
        val out: Mat = when (mode) {
            "photo" -> photo(rgba, s)
            "auto" -> flattenColor(rgba, s)                       // shadow removal only
            "magic" -> magicColor(rgba, s)                        // + contrast boost
            "bw" -> blackWhite(rgba, s)
            "grayscale" -> toGray(rgba, s)
            else -> rgba                                          // original
        }
        save(out, outPath, s)
    }

    private fun toGray(rgba: Mat, s: Scope) = s.track(Mat()).also { Imgproc.cvtColor(rgba, it, Imgproc.COLOR_RGBA2GRAY) }

    /**
     * Illumination normalisation ("shadow removal").
     * 1. Estimate the paper background of ONE channel: morphological close removes the
     *    dark text strokes, a median blur smooths it. Done at 1/4 resolution for speed.
     * 2. channel / background * 255  → paper becomes ≈255 regardless of shadows/gradients.
     */
    private fun flatten(ch: Mat, s: Scope): Mat {
        val f = 0.25
        val small = s.track(Mat()); Imgproc.resize(ch, small, Size(), f, f, Imgproc.INTER_AREA)
        val k = s.track(Imgproc.getStructuringElement(Imgproc.MORPH_RECT, Size(15.0, 15.0)))
        Imgproc.morphologyEx(small, small, Imgproc.MORPH_CLOSE, k)
        Imgproc.medianBlur(small, small, 21)
        val bg = s.track(Mat()); Imgproc.resize(small, bg, ch.size(), 0.0, 0.0, Imgproc.INTER_LINEAR)
        val out = s.track(Mat()); Core.divide(ch, bg, out, 255.0)
        return out
    }

    private fun flattenColor(rgba: Mat, s: Scope): Mat {
        val rgb = s.track(Mat()); Imgproc.cvtColor(rgba, rgb, Imgproc.COLOR_RGBA2RGB)
        val chans = ArrayList<Mat>(); Core.split(rgb, chans)
        val flat = chans.map { flatten(it, s) }
        chans.forEach { it.release() }
        val merged = s.track(Mat()); Core.merge(flat, merged)
        return merged
    }

    private fun magicColor(rgba: Mat, s: Scope): Mat {
        val flat = flattenColor(rgba, s)
        val out = s.track(Mat())
        flat.convertTo(out, -1, 1.25, -28.0)       // push paper to pure white, text darker
        return out
    }

    private fun photo(rgba: Mat, s: Scope): Mat {
        val rgb = s.track(Mat()); Imgproc.cvtColor(rgba, rgb, Imgproc.COLOR_RGBA2RGB)
        val lab = s.track(Mat()); Imgproc.cvtColor(rgb, lab, Imgproc.COLOR_RGB2Lab)
        val chans = ArrayList<Mat>(); Core.split(lab, chans)
        Imgproc.createCLAHE(2.0, Size(8.0, 8.0)).apply(chans[0], chans[0])  // local contrast on L only
        Core.merge(chans, lab); chans.forEach { it.release() }
        val out = s.track(Mat()); Imgproc.cvtColor(lab, out, Imgproc.COLOR_Lab2RGB)
        return out
    }

    private fun blackWhite(rgba: Mat, s: Scope): Mat {
        val flat = flatten(toGray(rgba, s), s)
        val longSide = max(flat.rows(), flat.cols())
        var win = max(15, longSide / 50)               // 15 px minimum, grows with resolution
        if (win % 2 == 0) win++
        return sauvola(flat, win, 0.2, 128.0, s)
    }

    /**
     * Sauvola local threshold:  T = mean · (1 + k · (std/R − 1))
     * mean/std come from box filters (O(1) per pixel via integral-image style filtering).
     * pixel > T → background → 255 (pure white);  pixel ≤ T → ink → 0.
     */
    private fun sauvola(gray: Mat, win: Int, k: Double, r: Double, s: Scope): Mat {
        val g = s.track(Mat()); gray.convertTo(g, CvType.CV_32F)
        val sz = Size(win.toDouble(), win.toDouble()); val anchor = Point(-1.0, -1.0)
        val mean = s.track(Mat()); Imgproc.boxFilter(g, mean, CvType.CV_32F, sz, anchor, true, Core.BORDER_REPLICATE)
        val sq = s.track(Mat());   Imgproc.sqrBoxFilter(g, sq, CvType.CV_32F, sz, anchor, true, Core.BORDER_REPLICATE)
        val mean2 = s.track(Mat()); Core.multiply(mean, mean, mean2)
        val variance = s.track(Mat()); Core.subtract(sq, mean2, variance)
        Core.max(variance, Scalar.all(0.0), variance)
        val std = s.track(Mat()); Core.sqrt(variance, std)
        val factor = s.track(Mat()); std.convertTo(factor, -1, k / r, 1.0 - k)   // 1 + k(std/R − 1)
        val thr = s.track(Mat()); Core.multiply(mean, factor, thr)
        val mask = s.track(Mat()); Core.compare(g, thr, mask, Core.CMP_GT)       // 8U 0/255
        return mask
    }
}
