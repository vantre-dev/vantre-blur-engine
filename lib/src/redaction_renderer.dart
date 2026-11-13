import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

import 'protection.dart';

enum ExportFormat {
  jpg('JPG', 'Smaller file, best for sharing'),
  png('PNG', 'Lossless, larger file'),
  webp('WebP', 'Modern, small and sharp'),
  heic('HEIC', 'Apple format', isPro: true);

  const ExportFormat(this.label, this.subtitle, {this.isPro = false});
  final String label;
  final String subtitle;
  final bool isPro;
}

/// Renders the original image with all enabled protection regions applied,
/// at full resolution, and encodes it for export.
abstract final class RedactionRenderer {
  /// Largest blur sigma the rendering backend actually honours. Above this
  /// it silently stops strengthening — measured on device, where sigma 240
  /// and sigma 2000 produced identical output. Kept conservative.
  static const _maxEffectiveSigma = 150.0;

  /// Draws the protected image onto a canvas.
  /// [intensity] scales blur sigma / pixel-cell size (0.5–2.0).
  ///
  /// [outputScale] below 1 renders a proportionally smaller image while
  /// keeping every region, sigma and cell size in original-image
  /// coordinates, so an on-screen preview costs a fraction of the pixels
  /// and still looks identical. Exports always render at 1.0 — the saved
  /// file must be full resolution.
  static Future<ui.Image> render(
    ui.Image original,
    List<ProtectionRegion> regions, {
    double intensity = 1.0,
    double outputScale = 1.0,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    // Only filter when actually resampling. At 1:1 a high-quality filter
    // still runs its kernel over every pixel, which measurably altered 40%
    // of the bytes in an export with NO regions at all (max delta 27/255).
    // That is quality loss in areas the user never asked to touch, on a
    // tool that promises the rest of the photo comes back as it was.
    final paint = ui.Paint()
      ..filterQuality = outputScale == 1.0
          ? ui.FilterQuality.none
          : ui.FilterQuality.high;
    if (outputScale != 1.0) canvas.scale(outputScale);
    canvas.drawImage(original, ui.Offset.zero, paint);

    final bounds = ui.Rect.fromLTWH(
      0,
      0,
      original.width.toDouble(),
      original.height.toDouble(),
    );

    for (final region in regions.where((r) => r.enabled)) {
      final rect = region.rect.intersect(bounds);
      if (rect.isEmpty) continue;
      canvas.save();
      if (region.isBrush) {
        canvas.clipPath(region.brushPath());
      } else if (region.shape == RegionShape.oval) {
        canvas.clipPath(ui.Path()..addOval(rect));
      } else {
        canvas.clipRect(rect);
      }
      switch (region.style) {
        case ProtectionStyle.blackBox:
          canvas.drawRect(rect, ui.Paint()..color = const ui.Color(0xFF000000));
        case ProtectionStyle.blur:
          // Two blur implementations, each used only where it is safe.
          //
          // A gaussian is the correct default: it spreads in BOTH axes, so
          // it hides a line of text. A downscale/upscale cannot replace it
          // in general, because its cell is square while a text line is
          // wide and short — sized from the line height, hundreds of
          // horizontal samples survive and an email/SSN/licence stays
          // readable. Verified on device.
          //
          // But the backend CAPS gaussian sigma, so past a certain region
          // size the blur stops strengthening: on a 4096px photo sigma 240
          // and sigma 2000 render identically and a face stays
          // recognisable. Also verified on device.
          //
          // So: gaussian while it is still doing what it is told, and the
          // uncapped downscale only above that. The handover point is well
          // past any plausible line of text (a ~1800px-tall region), so the
          // wide-and-thin case never reaches the downscale path, and a
          // region that big is square enough for a square cell to be
          // right. `/3` in both keeps the strength continuous across it.
          final sigma = (rect.shortestSide / 3) * intensity;
          if (sigma <= _maxEffectiveSigma) {
            canvas.saveLayer(
              rect,
              ui.Paint()
                ..imageFilter = ui.ImageFilter.blur(
                  sigmaX: sigma.clamp(12.0, _maxEffectiveSigma),
                  sigmaY: sigma.clamp(12.0, _maxEffectiveSigma),
                  tileMode: ui.TileMode.clamp,
                ),
            );
            canvas.drawImage(original, ui.Offset.zero, paint);
            canvas.restore();
          } else {
            // Beyond the cap the gaussian would silently under-blur, so
            // destroy the detail by resolution instead — no ceiling.
            final cell = sigma;
            final soft = await _scaledRegion(
              original,
              rect,
              (rect.width / cell).ceil(),
              (rect.height / cell).ceil(),
              quality: ui.FilterQuality.medium,
            );
            // Small extra gaussian purely to smooth the blocks back into
            // something that reads as a blur; the detail is already gone,
            // so the cap is irrelevant to safety here.
            canvas.saveLayer(
              rect,
              ui.Paint()
                ..imageFilter = ui.ImageFilter.blur(
                  sigmaX: _maxEffectiveSigma / 2,
                  sigmaY: _maxEffectiveSigma / 2,
                  tileMode: ui.TileMode.clamp,
                ),
            );
            canvas.drawImageRect(
              soft,
              ui.Rect.fromLTWH(
                0,
                0,
                soft.width.toDouble(),
                soft.height.toDouble(),
              ),
              rect,
              ui.Paint()..filterQuality = ui.FilterQuality.high,
            );
            canvas.restore();
            soft.dispose();
          }
        case ProtectionStyle.pixelate:
          // Downscale the source, then stretch it back over the full image
          // with nearest-neighbor sampling; the clip limits it to the region.
          // `base` is roughly how many cells span the region's short side, so
          // a face lands on ~8-10 blocks rather than the 3 it used to get.
          // Cell count depends on the region's SHAPE, not just its size.
          // A square-ish region (a face) can afford ~8 blocks across and
          // looks better for it. A wide, thin one is a line of text, and 8
          // blocks across its height leaves the glyphs legible — verified
          // on a real ID card, where a pixelated "T22000129" was still
          // perfectly readable. Text needs ~3 blocks across to be
          // destroyed, matching what Blur does with a gaussian.
          // Cells across the region's short side. Both numbers are measured,
          // not chosen: render the redaction, then run the matching detector
          // back over the OUTPUT (tool/verify_faces.dart,
          // tool/verify_redaction.dart).
          //
          // 3 for text: at more than that, OCR pulled passport MRZ, IBAN and
          // Medicare digit runs back out ("...F0902274<<<" -> "...DP02274<<<").
          //
          // 4 for faces: at 8 — which is what this used to be — ML Kit still
          // FOUND 1/12, 1/8 and 16/47 faces in three test photos at default
          // strength. A third of a crowd staying machine-detectable is the
          // app failing at the one thing it is named for. 8 was chosen to
          // make the blocks look less heavy; that was an aesthetic call and
          // it cost real protection, so it loses to the measurement.
          final isTextLike = rect.longestSide / rect.shortestSide > 2.5;
          final base = isTextLike ? 3.0 : 4.0;
          // The strength slider must not be able to make a redaction unsafe.
          // Below 1.0 the cells shrink and detail comes back, so intensity
          // may only ever STRENGTHEN a pixelation — it stays a real control
          // for someone who wants a heavier look, but a user who prefers a
          // lighter one cannot silently lose protection. (Blur is exempt: it
          // measured clean at every intensity down to 0.5.)
          final safeCell = rect.shortestSide / base;
          var cell = safeCell * intensity;
          if (cell < safeCell) cell = safeCell;
          // Upper bound raised for the same reason as the blur sigma: at 160
          // a region on a large photo got far more (and finer) cells than
          // the same region on a small one, weakening the redaction as
          // resolution went up.
          cell = cell.clamp(4.0, 600.0);
          final small = await _scaledRegion(
            original,
            rect,
            (rect.width / cell).ceil(),
            (rect.height / cell).ceil(),
          );
          canvas.drawImageRect(
            small,
            ui.Rect.fromLTWH(
              0,
              0,
              small.width.toDouble(),
              small.height.toDouble(),
            ),
            rect,
            ui.Paint()..filterQuality = ui.FilterQuality.none,
          );
          small.dispose();
      }
      canvas.restore();
    }

    final picture = recorder.endRecording();
    final result = await picture.toImage(
      (original.width * outputScale).round().clamp(1, original.width),
      (original.height * outputScale).round().clamp(1, original.height),
    );
    picture.dispose();
    return result;
  }

  /// Scale that renders [original] no larger than [maxDimension] on its long
  /// edge. Never upscales.
  static double previewScale(ui.Image original, double maxDimension) {
    final longest = original.width > original.height
        ? original.width
        : original.height;
    if (longest <= maxDimension) return 1.0;
    return maxDimension / longest;
  }

  /// Downscales just [src]'s [region] to [w]x[h].
  ///
  /// Scaling the *whole* image by a factor derived from one region was
  /// catastrophic for small regions: a text line gives a small factor, so
  /// each region allocated a near-full-size intermediate, and a page with
  /// eight detections stalled the render entirely. Cost now scales with the
  /// region, not the image.
  static Future<ui.Image> _scaledRegion(
    ui.Image src,
    ui.Rect region,
    int w,
    int h, {
    ui.FilterQuality quality = ui.FilterQuality.low,
  }) async {
    final width = w.clamp(1, 4096);
    final height = h.clamp(1, 4096);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      src,
      region,
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..filterQuality = quality,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    picture.dispose();
    return image;
  }

  /// Encodes a rendered image to the requested format.
  static Future<Uint8List> encode(ui.Image image, ExportFormat format) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final rgba = byteData!.buffer.asUint8List();
    final width = image.width;
    final height = image.height;
    switch (format) {
      case ExportFormat.jpg || ExportFormat.png:
        return compute(_encodeSync, _EncodeJob(rgba, width, height, format));
      case ExportFormat.webp || ExportFormat.heic:
        // Native encoder needs an encoded input; go through JPG first.
        final jpg = await compute(
          _encodeSync,
          _EncodeJob(rgba, width, height, ExportFormat.jpg),
        );
        return FlutterImageCompress.compressWithList(
          jpg,
          quality: 95,
          format: format == ExportFormat.webp
              ? CompressFormat.webp
              : CompressFormat.heic,
          keepExif: false,
        );
    }
  }

  static Uint8List _encodeSync(_EncodeJob job) {
    final im = img.Image.fromBytes(
      width: job.width,
      height: job.height,
      bytes: job.rgba.buffer,
      numChannels: 4,
    );
    return switch (job.format) {
      ExportFormat.jpg => Uint8List.fromList(img.encodeJpg(im, quality: 95)),
      _ => Uint8List.fromList(img.encodePng(im)),
    };
  }
}

class _EncodeJob {
  _EncodeJob(this.rgba, this.width, this.height, this.format);
  final Uint8List rgba;
  final int width;
  final int height;
  final ExportFormat format;
}
