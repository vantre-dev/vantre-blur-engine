# Vantre Blur Engine

[![Vantre_Blur v1.1.27](https://img.shields.io/badge/Vantre_Blur-v1.1.27-111315)](https://play.google.com/store/apps/details?id=com.getvantre.blur)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://www.apache.org/licenses/LICENSE-2.0)
[![Android](https://img.shields.io/badge/Android-API_26+-green.svg)](https://developer.android.com)

The detection rules and redaction code behind [Vantre Blur](https://getvantre.com/products/screenshot-blur/) for Android, which hides faces, names, card numbers and other private details in screenshots and photos before you share them.

Everything runs on the device. This package has no network code.

## What it does

- `EntityExtractor` classifies text found in an image into types such as email, phone number, card number, IBAN, national ID, address, flight number and name. Where a format has a check digit (IBAN mod-97, some national IDs), it is verified so random digit runs are not flagged.
- `ProtectionRegion` and `ProtectionStyle` describe what to hide and how: black box, blur or pixelate, as a rectangle or an oval.
- `RedactionRenderer.render()` draws the protected image. The result is a new image with the regions rendered into the pixels, not a layer over the original.

## Verify it yourself

`test/redaction_renderer_test.dart` renders regions over known pixels and checks the output, including golden images for each style. `test/entity_extractor_test.dart` covers the detection rules with sample values.

## What is not in here

Finding text, faces and barcodes in an image uses Google ML Kit in the app. ML Kit is not open source and is not part of this repository. The engine takes the text it finds as input.

## Build and test

```
flutter pub get
flutter test
```

## Contributing

Bug reports are welcome, especially a private detail the rules miss or a redaction that looks recoverable. Pull requests are reviewed on a best-effort basis.

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

Made by [Vantre](https://getvantre.com).
