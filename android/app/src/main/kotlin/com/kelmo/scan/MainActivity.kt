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

import android.content.ContentValues
import android.content.Intent
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.media.MediaActionSound
import android.graphics.Bitmap
import android.os.Build
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Environment
import android.os.ParcelFileDescriptor
import android.print.PageRange
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.print.PrintDocumentInfo
import android.print.PrintManager
import android.provider.MediaStore
import android.view.WindowManager
import androidx.annotation.RequiresApi
import androidx.core.content.FileProvider
import org.opencv.core.Mat
import org.opencv.imgcodecs.Imgcodecs
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.opencv.android.OpenCVLoader
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.concurrent.Executors

/** Hands an existing PDF file to the Android print system. */
private class PdfPrintAdapter(private val file: File, private val name: String) : PrintDocumentAdapter() {
    override fun onLayout(
        oldAttributes: PrintAttributes?, newAttributes: PrintAttributes,
        cancellationSignal: CancellationSignal?, callback: LayoutResultCallback, extras: Bundle?
    ) {
        if (cancellationSignal?.isCanceled == true) { callback.onLayoutCancelled(); return }
        val info = PrintDocumentInfo.Builder(name).setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT).build()
        callback.onLayoutFinished(info, true)
    }

    override fun onWrite(
        pages: Array<out PageRange>, destination: ParcelFileDescriptor,
        cancellationSignal: CancellationSignal?, callback: WriteResultCallback
    ) {
        try {
            FileInputStream(file).use { input -> FileOutputStream(destination.fileDescriptor).use { input.copyTo(it) } }
            callback.onWriteFinished(arrayOf(PageRange.ALL_PAGES))
        } catch (e: Exception) {
            callback.onWriteFailed(e.message)
        }
    }
}

class MainActivity : FlutterFragmentActivity() {   // BiometricPrompt needs a FragmentActivity
    // Single worker thread: serialises CV work, keeps UI + platform thread free.
    private val worker = Executors.newSingleThreadExecutor()
    // OCR is slow (seconds per page): own thread so live edge-detection never waits for it.
    private val ocrWorker = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        check(OpenCVLoader.initLocal()) { "OpenCV native libs failed to load" }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "doc_scanner/cv")
            .setMethodCallHandler { call, result ->
                // ── security helpers (main thread) ──
                if (call.method == "biometricAvailable") {
                    val auth = BiometricManager.Authenticators.BIOMETRIC_STRONG or BiometricManager.Authenticators.BIOMETRIC_WEAK
                    result.success(BiometricManager.from(this).canAuthenticate(auth) == BiometricManager.BIOMETRIC_SUCCESS)
                    return@setMethodCallHandler
                }
                if (call.method == "biometricAuth") {
                    var replied = false
                    fun reply(ok: Boolean) { if (!replied) { replied = true; result.success(ok) } }
                    val prompt = BiometricPrompt(this, ContextCompat.getMainExecutor(this),
                        object : BiometricPrompt.AuthenticationCallback() {
                            override fun onAuthenticationSucceeded(r: BiometricPrompt.AuthenticationResult) = reply(true)
                            override fun onAuthenticationError(code: Int, msg: CharSequence) = reply(false)
                        })
                    val info = BiometricPrompt.PromptInfo.Builder()
                        .setTitle(call.argument<String>("title") ?: "Unlock")
                        .setNegativeButtonText("Use PIN")
                        .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG or BiometricManager.Authenticators.BIOMETRIC_WEAK)
                        .build()
                    prompt.authenticate(info)
                    return@setMethodCallHandler
                }
                if (call.method == "abi") {
                    result.success(android.os.Build.SUPPORTED_ABIS.firstOrNull() ?: "")
                    return@setMethodCallHandler
                }
                if (call.method == "installApk") {
                    try {
                        if (android.os.Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
                            startActivity(Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                android.net.Uri.parse("package:$packageName")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            result.success("permission")
                            return@setMethodCallHandler
                        }
                        val f = File(call.argument<String>("path")!!)
                        val uri = FileProvider.getUriForFile(this, "$packageName.kelmo.files", f)
                        startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success("ok")
                    } catch (e: Throwable) {
                        result.error("INSTALL", e.message, null)
                    }
                    return@setMethodCallHandler
                }
                if (call.method == "shutter") {
                    try { MediaActionSound().play(MediaActionSound.SHUTTER_CLICK) } catch (_: Throwable) {}
                    result.success(true)
                    return@setMethodCallHandler
                }
                if (call.method == "emailFile") {
                    try {
                        val f = File(call.argument<String>("path")!!)
                        val uri = FileProvider.getUriForFile(this, "$packageName.kelmo.files", f)
                        val to = (call.argument<String>("to") ?: "").split(',', ';').map { it.trim() }.filter { it.isNotEmpty() }
                        val send = Intent(Intent.ACTION_SEND).apply {
                            type = call.argument<String>("mime") ?: "application/pdf"
                            putExtra(Intent.EXTRA_STREAM, uri)
                            if (to.isNotEmpty()) putExtra(Intent.EXTRA_EMAIL, to.toTypedArray())
                            putExtra(Intent.EXTRA_SUBJECT, call.argument<String>("subject") ?: "")
                            putExtra(Intent.EXTRA_TEXT, call.argument<String>("body") ?: "")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        startActivity(Intent.createChooser(send, "Send Email"))
                        result.success(true)
                    } catch (t: Throwable) {
                        result.error("EMAIL_ERROR", t.message, null)
                    }
                    return@setMethodCallHandler
                }
                if (call.method == "printPdf") {
                    try {
                        val name = call.argument<String>("name") ?: "Kelmo Scan"
                        val pm = getSystemService(PRINT_SERVICE) as PrintManager
                        pm.print(name, PdfPrintAdapter(File(call.argument<String>("path")!!), name), null)
                        result.success(true)
                    } catch (t: Throwable) {
                        result.error("PRINT_ERROR", t.message, null)
                    }
                    return@setMethodCallHandler
                }
                if (call.method == "secureScreen") {
                    if (call.argument<Boolean>("on") == true) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(true)
                    return@setMethodCallHandler
                }
                if (call.method == "ocrMrz") {
                    ocrWorker.execute {
                        try {
                            val path = call.argument<String>("path")!!
                            val probe = DocumentProcessor.prepareForOcr(path, 1100)
                            val rot = try { TessEngine.bestRotation(applicationContext, probe) } finally { probe.recycle() }
                            val full = DocumentProcessor.prepareForOcr(path, 3000, rot)
                            val top = (full.height * 0.66).toInt()
                            val crop = Bitmap.createBitmap(full, 0, top, full.width, full.height - top)   // MRZ = bottom third
                            val text = try { TessEngine.recognizeMrz(applicationContext, crop) } finally { crop.recycle(); full.recycle() }
                            runOnUiThread { result.success(text) }
                        } catch (e: IllegalStateException) {
                            runOnUiThread { result.error("OCR_INIT", e.message, null) }
                        } catch (t: Throwable) {
                            runOnUiThread { result.error("OCR_ERROR", t.message, null) }
                        }
                    }
                    return@setMethodCallHandler
                }
                if (call.method == "ocr") {
                    ocrWorker.execute {
                        try {
                            val path = call.argument<String>("path")!!
                            var langs = call.argument<String>("langs") ?: "eng"
                            // auto language + orientation: probe on a small copy (with the page's own language)
                            val probe = DocumentProcessor.prepareForOcr(path, 1100)
                            val rot = try {
                                if (langs == "auto") langs = TessEngine.detectLang(applicationContext, probe)
                                TessEngine.bestRotation(applicationContext, probe, if (langs.startsWith("urd")) "urd" else "eng")
                            } finally { probe.recycle() }
                            val text = if (langs.contains("urd")) {
                                // Urdu: split into lines ourselves, then read line by line
                                val lines = DocumentProcessor.segmentLines(path, 3200, rot)
                                try { TessEngine.recognizeLines(applicationContext, lines, langs) }
                                finally { lines.forEach { it.recycle() } }
                            } else {
                                val bmp = DocumentProcessor.prepareForOcr(path, 3000, rot)
                                try { TessEngine.recognize(applicationContext, bmp, langs) }
                                finally { bmp.recycle() }
                            }
                            runOnUiThread { result.success(text) }
                        } catch (e: IllegalStateException) {
                            runOnUiThread { result.error("OCR_INIT", e.message, null) }   // e.g. traineddata missing
                        } catch (t: Throwable) {
                            runOnUiThread { result.error("OCR_ERROR", t.message, null) }
                        }
                    }
                    return@setMethodCallHandler
                }
                worker.execute {
                    try {
                        val out: Any? = when (call.method) {
                            "detectFrame" -> DocumentProcessor.detectFrame(
                                call.argument<ByteArray>("bytes")!!,
                                call.argument<Int>("width")!!, call.argument<Int>("height")!!,
                                call.argument<Int>("rowStride")!!, call.argument<Int>("rotation")!!)
                            "detectCorners" -> DocumentProcessor.detectCorners(call.argument<String>("path")!!)
                            "warp" -> {
                                val c = call.argument<List<Double>>("corners")!!.toDoubleArray()
                                DocumentProcessor.warp(call.argument<String>("path")!!, c, call.argument<String>("out")!!)
                                true
                            }
                            "applyFilter" -> {
                                DocumentProcessor.applyFilter(
                                    call.argument<String>("path")!!, call.argument<String>("mode")!!,
                                    call.argument<String>("out")!!, call.argument<Int>("maxSide") ?: 0)
                                true
                            }
                            "composeId" -> {
                                DocumentProcessor.composeId(
                                    call.argument<String>("front")!!, call.argument<String>("back")!!, call.argument<String>("out")!!)
                                true
                            }
                            "shrink" -> {
                                DocumentProcessor.shrink(
                                    call.argument<String>("path")!!, call.argument<Int>("maxSide")!!,
                                    call.argument<Int>("quality")!!, call.argument<String>("out")!!)
                                true
                            }
                            "applyMarks" -> {
                                DocumentProcessor.applyMarks(
                                    call.argument<String>("path")!!,
                                    call.argument<List<Double>>("marks")!!.toDoubleArray(),
                                    call.argument<String>("out")!!)
                                true
                            }
                            "saveToGallery", "saveToDownloads" -> {
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                    saveMedia(
                                        call.argument<String>("path")!!, call.argument<String>("name")!!,
                                        call.argument<String>("mime") ?: "image/jpeg", call.method == "saveToGallery")
                                } else {
                                    throw IllegalStateException("Saving needs Android 10 or newer")
                                }
                            }
                            "renderPdf" -> renderPdf(
                                call.argument<String>("path")!!, call.argument<String>("outDir")!!, call.argument<Int>("maxSide") ?: 2200)
                            "blankPage" -> {
                                val w = call.argument<Int>("width") ?: 2480
                                val h = call.argument<Int>("height") ?: 3508
                                val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.RGB_565)
                                bmp.eraseColor(Color.WHITE)
                                FileOutputStream(call.argument<String>("out")!!).use { bmp.compress(Bitmap.CompressFormat.JPEG, 92, it) }
                                bmp.recycle()
                                true
                            }
                            "adjust" -> {
                                val src = Imgcodecs.imread(call.argument<String>("path")!!)
                                val dst = Mat()
                                src.convertTo(dst, -1, call.argument<Double>("contrast") ?: 1.0, call.argument<Double>("brightness") ?: 0.0)
                                Imgcodecs.imwrite(call.argument<String>("out")!!, dst)
                                src.release(); dst.release()
                                true
                            }
                            "rotate" -> {
                                DocumentProcessor.rotate(call.argument<String>("path")!!, call.argument<String>("out")!!)
                                true
                            }
                            else -> { runOnUiThread { result.notImplemented() }; return@execute }
                        }
                        runOnUiThread { result.success(out) }
                    } catch (t: Throwable) {
                        runOnUiThread { result.error("CV_ERROR", t.message, null) }
                    }
                }
            }
    }

    /** Renders every page of a PDF to JPEG files (white background). Returns the file paths. */
    private fun renderPdf(path: String, outDir: String, maxSide: Int): List<String> {
        val out = mutableListOf<String>()
        File(outDir).mkdirs()
        ParcelFileDescriptor.open(File(path), ParcelFileDescriptor.MODE_READ_ONLY).use { fd ->
            PdfRenderer(fd).use { r ->
                for (i in 0 until r.pageCount) {
                    r.openPage(i).use { page ->
                        val scale = maxSide.toFloat() / maxOf(page.width, page.height)
                        val w = maxOf(1, (page.width * scale).toInt())
                        val h = maxOf(1, (page.height * scale).toInt())
                        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                        bmp.eraseColor(Color.WHITE)
                        page.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                        val f = File(outDir, "pdf_${System.currentTimeMillis()}_$i.jpg")
                        FileOutputStream(f).use { bmp.compress(Bitmap.CompressFormat.JPEG, 92, it) }
                        bmp.recycle()
                        out.add(f.absolutePath)
                    }
                }
            }
        }
        return out
    }

    /** Copies a file into Pictures/Kelmo Scan (gallery) or Download/Kelmo Scan. Returns the visible path. */
    @RequiresApi(Build.VERSION_CODES.Q)
    private fun saveMedia(path: String, name: String, mime: String, gallery: Boolean): String {
        val folder = (if (gallery) Environment.DIRECTORY_PICTURES else Environment.DIRECTORY_DOWNLOADS) + "/Kelmo Scan"
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, folder)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val collection = if (gallery) MediaStore.Images.Media.EXTERNAL_CONTENT_URI else MediaStore.Downloads.EXTERNAL_CONTENT_URI
        val uri = contentResolver.insert(collection, values) ?: throw IllegalStateException("Could not create $name")
        contentResolver.openOutputStream(uri)!!.use { out -> File(path).inputStream().use { it.copyTo(out) } }
        values.clear()
        values.put(MediaStore.MediaColumns.IS_PENDING, 0)
        contentResolver.update(uri, values, null, null)
        return "$folder/$name"
    }

    override fun onDestroy() { worker.shutdown(); ocrWorker.shutdown(); super.onDestroy() }
}
