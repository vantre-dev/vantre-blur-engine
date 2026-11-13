import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:vantre_blur_engine/src/protection.dart';
import 'package:vantre_blur_engine/src/redaction_renderer.dart';

/// Renderer tests.
///
/// These assert the PROPERTY that matters rather than a reference image: the
/// pixels under a region must no longer resemble the pixels that were there.
/// A pixel golden can pass while still leaking (that is exactly what
/// tool/verify_redaction.dart caught with the old mosaic style, whose grid
/// lines left OCR-recoverable artefacts), and it fails for reasons that have
/// nothing to do with privacy, like a font or a platform blur difference.

/// A source image of per-pixel pseudo-random noise, seeded so every run is
/// identical.
///
/// Deliberately not a checkerboard. A 6px checkerboard is FLAT almost
/// everywhere, so a detail metric barely separates it from a redacted
/// version, and a pixelation whose blocks align with the squares reproduces
/// it exactly. Noise has detail at every pixel, which is the property a
/// redaction has to destroy, and it cannot resonate with a block size.
/// Built with a PictureRecorder rather than `decodeImageFromPixels`: that
/// one's completion callback is never pumped inside a plain `test()`, so it
/// hangs the run forever instead of failing.
Future<ui.Image> _source({int size = 120}) async {
  final rng = Random(20260731);
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final paint = ui.Paint();
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final v = rng.nextInt(256);
      paint.color = ui.Color.fromARGB(255, v, v, v);
      canvas.drawRect(
        ui.Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
        paint,
      );
    }
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  picture.dispose();
  return image;
}

/// Hard-edged vertical bars, roughly the width of a glyph stroke.
///
/// The noise fixture above is the EASIEST possible thing to redact: it is
/// pure high-frequency, so even a crippled blur flattens it. Verified by
/// mutation -- cutting blur sigma to 2% of its real value still passed every
/// noise test. Structure at glyph scale is what actually survives a weak
/// blur, and legible text is the leak this app exists to prevent
/// (tool/verify_redaction.dart once pulled a passport MRZ back out of a
/// redaction that looked fine).
Future<ui.Image> _bars({int size = 120, double barWidth = 5}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  final ink = ui.Paint()..color = const ui.Color(0xFF000000);
  for (var x = 0.0; x < size; x += barWidth * 2) {
    canvas.drawRect(ui.Rect.fromLTWH(x, 0, barWidth, size.toDouble()), ink);
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  picture.dispose();
  return image;
}

ProtectionRegion _region(
  ui.Rect rect, {
  ProtectionStyle style = ProtectionStyle.blur,
  RegionShape shape = RegionShape.rectangle,
  bool enabled = true,
}) => ProtectionRegion(
  id: 1,
  rect: rect,
  type: DetectionType.manual,
  shape: shape,
  style: style,
  enabled: enabled,
);

Future<Uint8List> _rgba(ui.Image image) async =>
    (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer
        .asUint8List();

int _pixel(Uint8List rgba, int width, int x, int y) {
  final i = (y * width + x) * 4;
  return (rgba[i] << 16) | (rgba[i + 1] << 8) | rgba[i + 2];
}

/// Mean absolute difference between horizontally adjacent pixels over
/// [rect]: how much fine detail survives.
///
/// Deliberately NOT the standard deviation of the region. That measures
/// global contrast, and a working pixelation scored IDENTICALLY to the
/// untouched original under it, because 15px blocks of black and white have
/// the same spread as 6px ones. It would have passed a region that was never
/// redacted at all. Detail is a local property, so it has to be measured
/// locally.
double _detail(Uint8List rgba, int width, ui.Rect rect) {
  var total = 0.0;
  var n = 0;
  for (var y = rect.top.toInt(); y < rect.bottom.toInt(); y++) {
    for (var x = rect.left.toInt(); x < rect.right.toInt() - 1; x++) {
      total += (_luma(rgba, width, x, y) - _luma(rgba, width, x + 1, y)).abs();
      n++;
    }
  }
  return n == 0 ? 0 : total / n;
}

double _luma(Uint8List rgba, int width, int x, int y) {
  final p = _pixel(rgba, width, x, y);
  return 0.299 * ((p >> 16) & 0xFF) +
      0.587 * ((p >> 8) & 0xFF) +
      0.114 * (p & 0xFF);
}

void main() {
  const target = ui.Rect.fromLTWH(30, 30, 60, 60);
  // Sampled well inside the region so a blur's soft edge is not counted.
  const inner = ui.Rect.fromLTWH(45, 45, 30, 30);
  // Outside every region: must come back untouched.
  const outside = ui.Rect.fromLTWH(0, 0, 24, 24);

  late ui.Image src;
  late Uint8List srcRgba;
  late double srcDetail;

  setUp(() async {
    src = await _source();
    srcRgba = await _rgba(src);
    srcDetail = _detail(srcRgba, src.width, inner);
  });

  tearDown(() => src.dispose());

  test('the noise fixture really is full of detail', () {
    // Guards the tests below: if the fixture were flat they would all pass
    // vacuously, which is the classic way a privacy test rots.
    expect(srcDetail, greaterThan(40));
  });

  for (final style in ProtectionStyle.values) {
    test('$style destroys detail inside the region', () async {
      final out = await RedactionRenderer.render(src, [
        _region(target, style: style),
      ]);
      final rgba = await _rgba(out);
      expect(
        _detail(rgba, out.width, inner),
        lessThan(srcDetail * 0.1),
        reason: '$style left recoverable structure',
      );
      out.dispose();
    });

    test('$style leaves pixels outside the region untouched', () async {
      final out = await RedactionRenderer.render(src, [
        _region(target, style: style),
      ]);
      final rgba = await _rgba(out);
      for (var y = 0; y < outside.height.toInt(); y++) {
        for (var x = 0; x < outside.width.toInt(); x++) {
          expect(
            _pixel(rgba, out.width, x, y),
            _pixel(srcRgba, src.width, x, y),
            reason: '$style modified ($x,$y), which is outside every region',
          );
        }
      }
      out.dispose();
    });
  }

  test('a disabled region is not rendered', () async {
    final out = await RedactionRenderer.render(src, [
      _region(target, enabled: false),
    ]);
    final rgba = await _rgba(out);
    expect(_detail(rgba, out.width, inner), closeTo(srcDetail, 0.001));
    out.dispose();
  });

  test('an oval region still obscures its centre', () async {
    final out = await RedactionRenderer.render(src, [
      _region(target, shape: RegionShape.oval),
    ]);
    final rgba = await _rgba(out);
    expect(_detail(rgba, out.width, inner), lessThan(srcDetail * 0.1));
    out.dispose();
  });

  test('the weakest allowed intensity still obscures', () async {
    // The intensity slider bottoms out at 0.5. A floor that is too low is a
    // leak the user can reach with one drag, which is exactly the class of
    // bug tool/verify_redaction.dart was written to catch.
    final out = await RedactionRenderer.render(src, [
      _region(target),
    ], intensity: 0.5);
    final rgba = await _rgba(out);
    expect(
      _detail(rgba, out.width, inner),
      lessThan(srcDetail * 0.15),
      reason: 'minimum intensity leaves recoverable structure',
    );
    out.dispose();
  });

  test('a region larger than the image does not throw', () async {
    final out = await RedactionRenderer.render(src, [
      _region(const ui.Rect.fromLTWH(-500, -500, 2000, 2000)),
    ]);
    expect(out.width, src.width);
    out.dispose();
  });

  test('export renders at full resolution regardless of preview scale',
      () async {
    final preview = await RedactionRenderer.render(src, [
      _region(target),
    ], outputScale: 0.5);
    expect(preview.width, src.width ~/ 2);
    preview.dispose();

    final export = await RedactionRenderer.render(src, [_region(target)]);
    expect(export.width, src.width);
    export.dispose();
  });

  test('previewScale never upscales', () {
    expect(RedactionRenderer.previewScale(src, 10000), 1.0);
    expect(RedactionRenderer.previewScale(src, 60), closeTo(0.5, 0.001));
  });

  group('glyph-scale structure', () {
    // The test that actually has teeth. Each style must destroy bars at text
    // stroke width, not merely smooth out noise.
    late ui.Image bars;
    late double barsDetail;

    setUp(() async {
      bars = await _bars();
      barsDetail = _detail(await _rgba(bars), bars.width, inner);
    });
    tearDown(() => bars.dispose());

    test('the bars fixture really is structured', () {
      expect(barsDetail, greaterThan(20));
    });

    for (final style in ProtectionStyle.values) {
      test('$style destroys glyph-scale bars', () async {
        final out = await RedactionRenderer.render(bars, [
          _region(target, style: style),
        ]);
        final rgba = await _rgba(out);
        // 0.25, not 0.1, and the difference is measured rather than
        // guessed. Source detail is 44.0. Working styles score: blur 1.1-2.2,
        // blackBox 0.0, pixelate 8.8 -- and pixelate's 8.8 is entirely BLOCK
        // EDGES, which carry no information about what was underneath. A
        // real leak (the sigma floor removed) scores 44.7, above the source
        // itself, so the gap this has to separate is 8.8 vs 44.7.
        expect(
          _detail(rgba, out.width, inner),
          lessThan(barsDetail * 0.25),
          reason: '$style left text-scale structure intact',
        );
        out.dispose();
      });
    }

    test('the weakest allowed intensity still destroys bars', () async {
      final out = await RedactionRenderer.render(bars, [
        _region(target),
      ], intensity: 0.5);
      final rgba = await _rgba(out);
      expect(
        _detail(rgba, out.width, inner),
        lessThan(barsDetail * 0.25),
        reason: 'minimum intensity left text-scale structure intact',
      );
      out.dispose();
    });
  });

  group('small regions', () {
    // On a 60px region sigma is 20 and the sigma FLOOR never engages, so
    // every test above passes whether the floor is present or not. These
    // cover the small-region path instead.
    //
    // Honest limitation, established by mutation: dropping the floor to 0.4
    // does NOT fail these either, because sigma 3 still destroys 2px bars.
    // The floor's justification is empirical, from running detectors back
    // over real output (tool/verify_redaction.dart), and that evidence has
    // not been reduced to a unit test. What IS pinned here is that all three
    // styles obscure a small region at minimum intensity.
    const small = ui.Rect.fromLTWH(40, 40, 18, 18);
    const smallInner = ui.Rect.fromLTWH(44, 44, 10, 10);

    for (final style in ProtectionStyle.values) {
      test('$style destroys an 18px region', () async {
        final bars = await _bars(barWidth: 2);
        final before = _detail(await _rgba(bars), bars.width, smallInner);
        expect(before, greaterThan(20), reason: 'fixture must have detail');

        final out = await RedactionRenderer.render(bars, [
          _region(small, style: style),
        ], intensity: 0.5);
        final rgba = await _rgba(out);
        expect(
          _detail(rgba, out.width, smallInner),
          lessThan(before * 0.25),
          reason: '$style leaks on a small region at minimum intensity',
        );
        out.dispose();
        bars.dispose();
      });
    }
  });

  group('goldens', () {
    // Visual regressions only. The privacy property is asserted above; these
    // catch a style silently changing shape or alignment.
    for (final style in ProtectionStyle.values) {
      testWidgets('$style looks the same as last time', (tester) async {
        final src = await _source();
        final out = await RedactionRenderer.render(src, [
          _region(target, style: style),
        ]);
        await expectLater(
          out,
          matchesGoldenFile('goldens/style_${style.name}.png'),
        );
        src.dispose();
        out.dispose();
      });
    }
  });
}
