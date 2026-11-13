import 'dart:ui';


enum DetectionType {
  face('Face'),
  qrCode('QR Code'),
  barcode('Barcode'),
  phone('Phone Number'),
  email('Email Address'),
  url('URL'),
  creditCard('Card Number'),
  aadhaar('Aadhaar Number'),
  pan('PAN Number'),
  upi('UPI ID'),
  otp('Login Code'),
  ssn('SSN'),
  iban('IBAN'),
  passport('Passport Number'),
  driversLicense("Driver's License"),
  dob('Date of Birth'),
  ipAddress('IP Address'),
  crypto('Crypto Wallet'),
  bankAccount('Bank Account'),
  sin('SIN'),
  nino('National Insurance Number'),
  tfn('Tax File Number'),
  medicare('Medicare Number'),
  pnr('Booking Reference'),
  // Country ID numbers that carry their own check digit or letter (Spanish
  // DNI/NIE, Brazilian CPF, French NIR) or a document-number label (German
  // Ausweis, French CNI, Brazilian RG). One type rather than one per country:
  // the user's decision is "hide my ID number", whichever country issued it.
  nationalId('National ID Number'),
  // Brazil's instant-payment key (the random EVP form; email and phone keys
  // are already caught as email and phone).
  pixKey('Pix Key'),
  // Found by the ML Kit entity model rather than a regex: these are
  // free-form enough that no pattern catches them reliably.
  address('Postal Address'),
  trackingNumber('Tracking Number'),
  flightNumber('Flight Number'),
  personal('My info'),
  personName('Name'),
  manual('Manual');

  const DetectionType(this.label);
  final String label;


  bool get isPro => switch (this) {
    creditCard ||
    aadhaar ||
    pan ||
    upi ||
    barcode ||
    ssn ||
    iban ||
    passport ||
    driversLicense ||
    dob ||
    crypto ||
    bankAccount ||
    sin ||
    nino ||
    tfn ||
    medicare ||
    pnr ||
    nationalId ||
    pixKey ||
    address ||
    trackingNumber ||
    flightNumber ||
    personal ||
    personName => true,
    _ => false,
  };

  /// Grouping used to organize the type picker in the profile editor.
  DetectionCategory get category => switch (this) {
    face || qrCode || barcode => DetectionCategory.visual,
    phone || email || url || address => DetectionCategory.contact,
    aadhaar ||
    pan ||
    ssn ||
    passport ||
    driversLicense ||
    dob ||
    sin ||
    nino ||
    tfn ||
    medicare ||
    nationalId ||
    // A person's name is the label on every other identity field here.
    personName => DetectionCategory.identity,
    creditCard ||
    upi ||
    pixKey ||
    iban ||
    bankAccount ||
    crypto => DetectionCategory.financial,
    otp => DetectionCategory.security,
    pnr || flightNumber => DetectionCategory.travel,
    ipAddress ||
    trackingNumber ||
    personal ||
    manual => DetectionCategory.other,
  };
}

enum DetectionCategory {
  visual('Visual'),
  contact('Contact Info'),
  identity('Government ID'),
  financial('Financial'),
  security('Security Codes'),
  travel('Travel'),
  other('Other');

  const DetectionCategory(this.label);
  final String label;

}

/// Mosaic was removed in 1.0.0+5 and folded into Pixelate. It was the same
/// downscale with grid lines drawn on top, so it read as a second option
/// that was really a skin — and it was measurably the WEAKEST style: the
/// grid lines were the only thing in the app that ever left OCR-recoverable
/// artefacts (see tool/verify_redaction.dart). A stale `"mosaic"` in prefs
/// falls back to blur via `asNameMap()[...] ?? blur`, so no migration is
/// needed.
enum ProtectionStyle {
  blur('Blur'),
  pixelate('Pixelate'),
  blackBox('Black Box');

  const ProtectionStyle(this.label);
  final String label;

}

enum RegionShape { rectangle, oval }

/// A region of the image to protect, in image-pixel coordinates.
///
/// [brushPoints] (with [brushWidth]) marks a freeform brush stroke; the
/// region covers the union of circles along the stroke and [rect] is its
/// bounding box (used for hit testing).
class ProtectionRegion {
  ProtectionRegion({
    required this.id,
    required this.rect,
    required this.type,
    this.shape = RegionShape.rectangle,
    this.style = ProtectionStyle.blur,
    this.enabled = true,
    this.confidence,
    this.detectedText,
    this.brushPoints,
    this.brushWidth = 0,
  });

  final int id;
  final Rect rect;
  final DetectionType type;
  final RegionShape shape;
  final ProtectionStyle style;
  final bool enabled;
  final double? confidence; // 0..1, null for manual regions
  final String? detectedText;
  final List<Offset>? brushPoints;
  final double brushWidth;

  bool get isManual => type == DetectionType.manual;
  bool get isBrush => brushPoints != null;

  /// Whether [point] (image coordinates) falls inside this region. Ovals
  /// use their ellipse rather than the bounding box, so the corners of a
  /// face oval no longer swallow drags meant for the canvas underneath.
  bool hitTest(Offset point) {
    if (!rect.contains(point)) return false;
    if (shape != RegionShape.oval || isBrush) return true;
    final dx = (point.dx - rect.center.dx) / (rect.width / 2);
    final dy = (point.dy - rect.center.dy) / (rect.height / 2);
    return dx * dx + dy * dy <= 1.0;
  }

  /// Clip path for a brush stroke: union of circles along the points.
  Path brushPath() {
    final path = Path();
    for (final p in brushPoints!) {
      path.addOval(Rect.fromCircle(center: p, radius: brushWidth / 2));
    }
    return path;
  }

  static Rect brushBounds(List<Offset> points, double width) {
    var r = Rect.fromCircle(center: points.first, radius: width / 2);
    for (final p in points.skip(1)) {
      r = r.expandToInclude(Rect.fromCircle(center: p, radius: width / 2));
    }
    return r;
  }

  /// Returns a copy translated by [delta] (brush strokes move their points).
  ProtectionRegion translated(Offset delta) => ProtectionRegion(
    id: id,
    rect: rect.shift(delta),
    type: type,
    shape: shape,
    style: style,
    enabled: enabled,
    confidence: confidence,
    detectedText: detectedText,
    brushPoints: brushPoints?.map((p) => p + delta).toList(),
    brushWidth: brushWidth,
  );

  /// Returns a copy in the coordinates of an image scaled by [factor].
  ///
  /// Every geometric field has to move together: the rect, the brush points
  /// AND the brush width. Scaling the rect alone would leave a stroke drawn
  /// at its original thickness over a smaller photo, so a brush redaction
  /// would cover the wrong pixels -- which on this app means uncovering
  /// something. Used to render a thumbnail from a small decode instead of
  /// decoding at full resolution; see ExportService.thumbnail.
  ProtectionRegion scaled(double factor) => ProtectionRegion(
    id: id,
    rect: Rect.fromLTRB(
      rect.left * factor,
      rect.top * factor,
      rect.right * factor,
      rect.bottom * factor,
    ),
    type: type,
    shape: shape,
    style: style,
    enabled: enabled,
    confidence: confidence,
    detectedText: detectedText,
    brushPoints: brushPoints?.map((p) => p * factor).toList(),
    brushWidth: brushWidth * factor,
  );

  ProtectionRegion copyWith({
    Rect? rect,
    ProtectionStyle? style,
    bool? enabled,
    RegionShape? shape,
  }) => ProtectionRegion(
    id: id,
    rect: rect ?? this.rect,
    type: type,
    shape: shape ?? this.shape,
    style: style ?? this.style,
    enabled: enabled ?? this.enabled,
    confidence: confidence,
    detectedText: detectedText,
    brushPoints: brushPoints,
    brushWidth: brushWidth,
  );
}
