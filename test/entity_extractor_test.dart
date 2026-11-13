import 'package:flutter_test/flutter_test.dart';
import 'package:vantre_blur_engine/src/protection.dart';
import 'package:vantre_blur_engine/src/entity_extractor.dart';

void main() {
  test('OCR-realistic spacing around @ and in licence numbers', () {
    const cases = {
      'A rohan.mehta @okaxis': DetectionType.upi,
      'B johndoe @paytm': DetectionType.upi,
      'C UPI ID: johndoe @oksbi': DetectionType.upi,
      'D john.doe @gmail.com': DetectionType.email,
      'E john.doe@gmail.com': DetectionType.email,
      'F jean.dupont @orange.fr': DetectionType.email,
      "G Driver's License: TX 41928815": DetectionType.driversLicense,
      "H Driver's License: TX41928815": DetectionType.driversLicense,
      'I DL No. CA-D1234567': DetectionType.driversLicense,
    };
    cases.forEach((text, want) {
      expect(EntityExtractor.classify(text), want, reason: text);
    });
    // guard against the looser licence run swallowing ordinary prose
    expect(EntityExtractor.classify('the'), isNull);
  });

  void expectAll(Map<String, DetectionType?> cases) {
    cases.forEach((text, want) {
      expect(EntityExtractor.classify(text), want, reason: text);
    });
  }

  test(
    'booking references, including the abbreviations passes actually use',
    () {
      expectAll({
        'Booking Ref: X4KJ9P': DetectionType.pnr,
        'Booking Reference: X4KJ9P': DetectionType.pnr,
        'Booking Code X4KJ9P': DetectionType.pnr,
        'Conf #: ABC123': DetectionType.pnr,
        'Confirmation code: ABC123': DetectionType.pnr,
        'Reservation code QWE456': DetectionType.pnr,
        'Record Locator: ZZ12PQ': DetectionType.pnr,
        'PNR: X4KJ9P': DetectionType.pnr,
        'E-Ticket Number 0012278449': DetectionType.pnr,
      });
    },
  );

  test(
    'flight designators are matched by IATA pattern, not an airline list',
    () {
      expectAll({
        'Flight: AA 1847': DetectionType.flightNumber,
        'Flight AI 101': DetectionType.flightNumber,
        'MU219': DetectionType.flightNumber,
        'MU 219': DetectionType.flightNumber,
        'EK512 Dubai': DetectionType.flightNumber,
        'AC 856': DetectionType.flightNumber,
        '6E 2341': DetectionType.flightNumber,
        'U2 8001': DetectionType.flightNumber,
      });
    },
  );

  test('flight pattern does not swallow ZIP codes or ordinary prose', () {
    // "CA 90210" is a state + five-digit ZIP, not a flight.
    expect(
      EntityExtractor.classify('Austin, TX 78704'),
      isNot(DetectionType.flightNumber),
    );
    expect(
      EntityExtractor.classify('Los Angeles, CA 90210'),
      isNot(DetectionType.flightNumber),
    );
    // lowercase must not match: the bare pattern is case-sensitive
    expect(EntityExtractor.classify('arrived in 2024 by train'), isNull);
    expect(EntityExtractor.classify('we had 12 people'), isNull);
  });

  test('dates of birth, labelled and bare', () {
    expectAll({
      'DOB: 03/14/1991': DetectionType.dob,
      'Date of birth: 12.08.1964': DetectionType.dob,
      'Geburtstag 12.08.1964': DetectionType.dob,
      'Fecha de nacimiento: 12/08/1964': DetectionType.dob,
      // bare, as printed on an ID card where the caption is its own line
      '12.08.1964': DetectionType.dob,
      '1964-08-12': DetectionType.dob,
    });
  });

  test('bare-date rule ignores expiry dates and statement rows', () {
    // expiry: too recent to be a birth year
    expect(EntityExtractor.classify('31.10.2020'), isNull);
    // transaction rows must not all become detections
    expect(EntityExtractor.classify('04 Jun Rent transfer'), isNull);
    expect(EntityExtractor.classify('11 Jun Salary credit'), isNull);
    expect(
      EntityExtractor.classify('12.08.1964 was a long time ago in Berlin'),
      isNull,
      reason: 'prose around the date should not count as a bare date',
    );
  });

  // The three below were all found by tool/verify_pro.dart on a real device,
  // not by reading the rules. Each one is the exact line the harness fed in.

  test('licence is matched in the UK and Indian wording too', () {
    expectAll({
      'Driving licence: RAMAN911104PR9AB': DetectionType.driversLicense,
      'Driving License: RAMAN911104PR9AB': DetectionType.driversLicense,
      // the forms that already worked must keep working
      "Driver's License: TX 41928815": DetectionType.driversLicense,
      'DL No. CA-D1234567': DetectionType.driversLicense,
    });
    // "driving" alone is ordinary prose and must not arm the rule
    expect(EntityExtractor.classify('Driving to the office tomorrow'), isNull);
  });

  test('a labelled account number is a bank account, not an Aadhaar', () {
    expectAll({
      'Account number: 000123456789': DetectionType.bankAccount,
      'Paid to account 000123456789': DetectionType.bankAccount,
      'Routing number: 021000021': DetectionType.bankAccount,
    });
    // money on the neighbouring statement rows must not arm the bare form
    expect(EntityExtractor.classify('Account balance 1,204.55'), isNull);
    expect(EntityExtractor.classify('Closing balance 1,142.45'), isNull);
    // the bare 12-digit pattern still owns an actual Aadhaar line
    expectAll({
      'Aadhaar Number: 0000 0000 0000': DetectionType.aadhaar,
      '0000 0000 0000': DetectionType.aadhaar,
    });
    // and a card must not be captured by the account keyword ahead of it
    expect(
      EntityExtractor.classify('Card ending: 4111 1111 1111 1111'),
      DetectionType.creditCard,
    );
  });

  test('a labelled phone number is not diluted below the ratio guard', () {
    expectAll({
      'Telephone: +1 555 0100': DetectionType.phone,
      'Contact: +1 555 0175': DetectionType.phone,
      'Mobile: +91 90000 00000': DetectionType.phone,
      // unlabelled still relies on the ratio, as before
      '+1 555 0100': DetectionType.phone,
    });
    // the label alone must not make ordinary numbers into phone numbers
    expect(EntityExtractor.classify('Contact us about your order'), isNull);
    expect(
      EntityExtractor.classify('Phone support is open until 6'),
      isNull,
      reason: 'too few digits to be a number, label or not',
    );
  });

  test('a URL is matched even when OCR mangles the slashes', () {
    expectAll({
      'Pay online: https://example.com/pay/2026-0042': DetectionType.url,
      // exactly what ML Kit returned for that line
      'Pay online: https:/lexample.compay/2026-0042': DetectionType.url,
      'Visit www.example.com/offers': DetectionType.url,
    });
    expect(EntityExtractor.classify('Questions? Ask the team'), isNull);
  });

  test('IBAN survives the O-for-zero misread OCR actually produces', () {
    expectAll({
      'IBAN: GB00NWBK00000000000000': DetectionType.iban,
      // what ML Kit really returned for that same line on device
      'IBAN: GBOONWBK00000000000000': DetectionType.iban,
    });
    // the loosened check pair must not turn prose into an IBAN
    expect(EntityExtractor.classify('Please confirm the transfer'), isNull);
  });

  group('person name', () {
    test('labelled name fields', () {
      expectAll({
        'Name: John Doe': DetectionType.personName,
        'Full Name  Priya Sharma': DetectionType.personName,
        'Surname: OCONNOR': DetectionType.personName,
        "Surname: O'Connor": DetectionType.personName,
        'Cardholder JANE R. SMITH': DetectionType.personName,
        'Account holder: Maria de la Cruz': DetectionType.personName,
        'Passenger name: DOE/JOHN': DetectionType.personName,
        'Issued to: Ana Beatriz Souza': DetectionType.personName,
        'Attn: Dr Helen Park': DetectionType.personName,
      });
    });

    test('an honorific carries a name with no field label', () {
      expectAll({
        'Dear Mr Smith,': DetectionType.personName,
        'Prof. Amara Okafor': DetectionType.personName,
      });
    });

    test('a labelled NUMBER is not a name', () {
      // The value shape is letters only, so the holder of an account does
      // not become the account. The more specific rule must still win.
      // Not asserting WHICH numeric type wins here -- "account holder
      // number" defeats the bank-account keyword and the bare 12-digit
      // Aadhaar rule claims it, which is pre-existing behaviour. What
      // matters for this rule is that the holder's NUMBER never becomes
      // the holder's NAME.
      expect(
        EntityExtractor.classify('Account holder number 000123456789'),
        isNot(DetectionType.personName),
      );
      expect(
        EntityExtractor.classify('Cardholder: 4539 8712 3344 9021'),
        DetectionType.creditCard,
      );
      expect(
        EntityExtractor.classify('Name: john.doe@gmail.com'),
        DetectionType.email,
      );
    });

    test('a bare label or a non-person value stays unflagged', () {
      // The single biggest false-positive risk: a form heading with the
      // value in the next OCR line, or a field that names a thing.
      for (final line in [
        'Name',
        'Full name',
        'Name of bank',
        'Account holder type',
        'Cardholder Not Present',
        'Name: N/A',
      ]) {
        expect(EntityExtractor.classify(line), isNull, reason: line);
      }
    });

    test('ordinary statement headings are not names', () {
      // Two capitalised words is the shape of half a bank statement, which
      // is why there is no bare capitalised-pair rule.
      for (final line in [
        'Closing Balance',
        'Recent Transactions',
        'Card Payment',
        'Salary Credit',
        'Rent transfer',
      ]) {
        expect(EntityExtractor.classify(line), isNull, reason: line);
      }
    });

    test('a heading over its value: the two halves of the cross-line rule', () {
      // "ACCOUNT HOLDER" / "John Doe" on separate OCR lines, which is how
      // every form lays a name out and what the same-line rule cannot see.
      for (final label in [
        'ACCOUNT HOLDER',
        'Account holder',
        'Name',
        'Full Name',
        'PASSENGER',
        'Cardholder:',
      ]) {
        expect(EntityExtractor.isBareNameLabel(label), isTrue, reason: label);
      }
      for (final notLabel in [
        'Name: John Doe',
        'Account number',
        'Closing Balance',
        'Email',
      ]) {
        expect(
          EntityExtractor.isBareNameLabel(notLabel),
          isFalse,
          reason: notLabel,
        );
      }

      for (final value in ['John Doe', 'PRIYA RAMAN', 'DOE/JOHN', "Ana O'Neil"]) {
        expect(EntityExtractor.looksLikeNameValue(value), isTrue, reason: value);
      }
      for (final notValue in [
        '000123456789',
        'jane@test.org',
        '+1 415 555 0134',
        'Not Present',
        'n/a',
        'a rather long sentence of ordinary lowercase prose here',
      ]) {
        expect(
          EntityExtractor.looksLikeNameValue(notValue),
          isFalse,
          reason: notValue,
        );
      }
    });
  });

  group('booking / reference codes (adversarial)', () {
    test('hyphenated codes and bare "reference" keyword now match', () {
      expectAll({
        'Confirmation: SA-7QK9F2-01': DetectionType.pnr,
        'Statement reference: NB-4471-2296': DetectionType.pnr,
        'Booking Ref: 4X9K2Q': DetectionType.pnr,
        'Account reference no. AC-9981-22': DetectionType.pnr,
        'e-ticket number: 1234567890': DetectionType.pnr,
      });
    });

    test('bare "reference" without a code does not false-positive', () {
      expectAll({
        'Reference guide available online': null,
        'This is just a reference to something else': null,
        'Please reference the attached document': null,
      });
    });
  });

  group('multi-line name continuation (adversarial)', () {
    // The actual failure: a DC sample driver's licence prints the surname
    // as "SAMPLECARD", then the given/middle name as two more OCR lines
    // ("SAMUEL" then "DANIEL, JR") with no label on the wrapped line.
    // Continuation lines carry no label and no honorific of their own, so
    // classify() correctly returns null for them — it's looksLikeNameValue
    // that the scanner's continuation pass (pass 1c) actually consults.
    test('a comma-suffixed continuation line still reads as a name value', () {
      for (final continuation in ['DANIEL, JR', 'SMITH-JONES']) {
        expect(
          EntityExtractor.looksLikeNameValue(continuation),
          isTrue,
          reason: continuation,
        );
      }
    });

    test('isBareNameLabel does not falsely accept a continuation line', () {
      for (final continuation in ['DANIEL, JR', 'SMITH-JONES', 'DE LA CRUZ']) {
        expect(
          EntityExtractor.isBareNameLabel(continuation),
          isFalse,
          reason: continuation,
        );
      }
    });

    test('a continuation line must still look name-shaped, not numeric', () {
      for (final notAName in ['DOB 03/14/1991', 'DL TX 41928815']) {
        expect(
          EntityExtractor.looksLikeNameValue(notAName),
          isFalse,
          reason: notAName,
        );
      }
    });
  });

  group('phone number embedded in prose (adversarial)', () {
    test('a phone number mid-sentence is still caught', () {
      // A chat-bubble line like this scores well below the old whole-line
      // digit-ratio guard (~0.26), which is exactly why it went unblurred.
      expect(
        EntityExtractor.classify('You can reach (415) 555-0192. My account'),
        DetectionType.phone,
      );
      expect(
        EntityExtractor.classify('Sure! Here\'s a draft: (415) 555-0192.'),
        DetectionType.phone,
      );
    });

    test('scattered unrelated digits in prose do not false-positive', () {
      expect(
        EntityExtractor.classify(
          'We shipped 12 boxes on the 3rd to unit 204 for order 88',
        ),
        isNot(DetectionType.phone),
      );
    });
  });

  // The listing is localized for es, pt, de, fr and hi, but every keyword
  // below used to be English-only: a Brazilian's CPF, a Spaniard's "código"
  // and a German "Kontonummer" all went unredacted. Each case is the wording
  // those documents actually print.
  group('national ID numbers', () {
    test('Spanish DNI / NIE, validated by the check letter', () {
      expectAll({
        'DNI 12345678Z': DetectionType.nationalId,
        '12345678-Z': DetectionType.nationalId,
        '87654321X': DetectionType.nationalId,
        'NIE: X1234567L': DetectionType.nationalId,
      });
    });

    test('Brazilian CPF, validated by its check digits, and RG', () {
      expectAll({
        'CPF: 529.982.247-25': DetectionType.nationalId,
        '529.982.247-25': DetectionType.nationalId,
        'CPF 39053344705': DetectionType.nationalId,
        'RG 12.345.678-9': DetectionType.nationalId,
      });
    });

    test('French social security number (NIR), validated by its key', () {
      expectAll({
        '1 85 05 78 006 084 91': DetectionType.nationalId,
        'N° de sécurité sociale 1 85 05 78 006 084 91':
            DetectionType.nationalId,
      });
    });

    test('ID card document numbers, labelled or alone on their line', () {
      expectAll({
        // German Personalausweis: printed alone in the top corner.
        'T22000129': DetectionType.nationalId,
        'Ausweisnummer: T22000129': DetectionType.nationalId,
        'Dokumentennummer L01X00T47': DetectionType.nationalId,
        // French CNI (2021 format).
        'N° du document : X4RTBPFW4': DetectionType.nationalId,
        'Número de documento: CAA123456': DetectionType.nationalId,
      });
    });

    test('Pakistani CNIC / NICOP: 5-7-1 with dashes, or labelled', () {
      expectAll({
        '35202-1234567-1': DetectionType.nationalId,
        'Identity Number 35202-1234567-1': DetectionType.nationalId,
        'CNIC: 3520212345671': DetectionType.nationalId,
        'CNIC No. 35202 1234567 1': DetectionType.nationalId,
      });
      // Unlabelled 13 digits is also a card length, so it stays a card, and
      // a Pakistani mobile (0300-1234567) is a phone, not an ID.
      expect(
        EntityExtractor.classify('3520212345671'),
        isNot(DetectionType.nationalId),
      );
      expect(EntityExtractor.classify('0300-1234567'), DetectionType.phone);
    });

    test('checksum failures and look-alikes are not ID numbers', () {
      for (final t in [
        '12345678A', // wrong DNI letter
        '529.982.247-26', // wrong CPF check digit
        '1 85 05 78 006 084 90', // wrong NIR key
        '111.111.111-11', // passes the CPF sum, but is a known invalid
        'Order ABC123XYZ',
        'WELCOME12',
      ]) {
        expect(
          EntityExtractor.classify(t),
          isNot(DetectionType.nationalId),
          reason: t,
        );
      }
    });

    test('a bare 11-digit Brazilian mobile is not read as a CPF', () {
      expect(
        EntityExtractor.classify('11987654321'),
        isNot(DetectionType.nationalId),
      );
    });
  });

  group('IBANs printed in groups', () {
    // Every European statement prints the IBAN in blocks of four. The
    // unbroken-run rule missed that, and the card rule claimed the digits.
    test('grouped IBANs, validated by the mod-97 check', () {
      expectAll({
        'IBAN ES91 2100 0418 4502 0005 1332': DetectionType.iban,
        'ES91 2100 0418 4502 0005 1332': DetectionType.iban,
        'IBAN: DE89 3704 0044 0532 0130 00': DetectionType.iban,
        'FR14 2004 1010 0505 0001 3M02 606': DetectionType.iban,
      });
    });

    test('a grouped look-alike that fails the check is not an IBAN', () {
      expect(
        EntityExtractor.classify('ES91 2100 0418 4502 0005 1333'),
        isNot(DetectionType.iban),
      );
    });
  });

  group('Pix keys', () {
    test('a random (EVP) Pix key, when the line names it', () {
      expectAll({
        'Chave Pix: 123e4567-e89b-42d3-a456-426614174000': DetectionType.pixKey,
        'Pix 123e4567-e89b-42d3-a456-426614174000': DetectionType.pixKey,
      });
    });

    test('a bare UUID is not a Pix key', () {
      expect(
        EntityExtractor.classify('123e4567-e89b-42d3-a456-426614174000'),
        isNot(DetectionType.pixKey),
      );
    });
  });

  group('login codes in every listing language', () {
    test('the wording each language actually sends', () {
      expectAll({
        'Your code is 482913': DetectionType.otp,
        'Tu código de verificación es 482913': DetectionType.otp,
        'Tu código es 482913': DetectionType.otp,
        'Clave: 482913': DetectionType.otp,
        'Seu código de acesso: 482913': DetectionType.otp,
        'Sua senha temporária é 482913': DetectionType.otp,
        'Ihr Bestätigungscode lautet 482913': DetectionType.otp,
        'Ihre TAN: 482913': DetectionType.otp,
        'Votre code de vérification est 482913': DetectionType.otp,
        'Votre code : 482 913': DetectionType.otp,
        'आपका ओटीपी 482913 है': DetectionType.otp,
      });
    });

    test('postal, area and promo codes are not login codes', () {
      for (final t in [
        'Código postal 28013',
        'Code postal 75001',
        'Zip code 90210',
        'Area code 415 555 0132',
        'Promo code SAVE20',
        'PIN code 110001', // an Indian postal code
      ]) {
        expect(EntityExtractor.classify(t), isNot(DetectionType.otp),
            reason: t);
      }
    });
  });

  group('bank accounts in every listing language', () {
    test('labelled account numbers', () {
      expectAll({
        'Número de cuenta: 0049 1500 05 1234567892': DetectionType.bankAccount,
        'Agência 1234 Conta 56789-0': DetectionType.bankAccount,
        'Conta corrente: 12345-6': DetectionType.bankAccount,
        'Kontonummer 1234567890': DetectionType.bankAccount,
        'Numéro de compte : 12345678901': DetectionType.bankAccount,
        'N° de compte 00012345678': DetectionType.bankAccount,
      });
    });

    test('the bare word with a short number is not an account', () {
      for (final t in ['Compte 2024', 'Cuenta 3 artículos', 'Konto']) {
        expect(EntityExtractor.classify(t), isNot(DetectionType.bankAccount),
            reason: t);
      }
    });
  });

  group('names, phones, passports, licences, birth dates (localized)', () {
    test('labelled names and honorifics', () {
      expectAll({
        'Nombre: María García': DetectionType.personName,
        'Titular: Juan Pérez López': DetectionType.personName,
        'Nome: João da Silva': DetectionType.personName,
        'Vorname: Erika': DetectionType.personName,
        'Nachname Mustermann': DetectionType.personName,
        'Nom : Dupont': DetectionType.personName,
        'Prénom : Jean': DetectionType.personName,
        'Sra. Lucía Fernández': DetectionType.personName,
        'Herr Thomas Müller': DetectionType.personName,
        'Mme Claire Martin': DetectionType.personName,
      });
    });

    test('a name label followed by what is not a name', () {
      for (final t in ['Nombre del banco', 'Nom de la banque', 'Name der Bank']) {
        expect(EntityExtractor.classify(t), isNot(DetectionType.personName),
            reason: t);
      }
    });

    test('a slash does not make an ordinary line a name heading', () {
      for (final t in ['Date / Time', 'Name / Account number 1234']) {
        expect(EntityExtractor.isBareNameLabel(t), isFalse, reason: t);
      }
    });

    test('bare name headings in each language', () {
      for (final t in [
        'TITULAR',
        'Nome completo',
        'Vorname',
        'Vornamen', // the plural a German ID card prints
        'Prénom',
        'Apellidos',
        "/ Father's Name", // PAN card, after OCR drops the Hindi half
        'ATA / Name', // ...or misreads it as stray Latin letters
        "fuar r ATH / Father's Name",
      ]) {
        expect(EntityExtractor.isBareNameLabel(t), isTrue, reason: t);
      }
    });

    test('phones labelled in German, French and Hindi', () {
      expectAll({
        'Telefon: +49 30 123456': DetectionType.phone,
        'Handy 0151 23456789': DetectionType.phone,
        'Portable : 06 12 34 56 78': DetectionType.phone,
        'Tél. 01 23 45 67 89': DetectionType.phone,
        'मोबाइल: 98765 43210': DetectionType.phone,
      });
    });

    test('passports and driving licences', () {
      expectAll({
        'Pasaporte n.º PAA123456': DetectionType.passport,
        'Passaporte nº FT123456': DetectionType.passport,
        'Reisepass-Nr. C01X00T47': DetectionType.passport,
        'Passeport n° 18AB12345': DetectionType.passport,
        'Führerschein-Nr. B072RRE2I55': DetectionType.driversLicense,
        'Permis de conduire n° 123456789012': DetectionType.driversLicense,
        'CNH 01234567890': DetectionType.driversLicense,
        'Carteira de motorista nº 01234567890': DetectionType.driversLicense,
      });
    });

    test('birth dates labelled in French, German and Hindi', () {
      expectAll({
        'Né le 12/08/1964': DetectionType.dob,
        'Geb. am 12.08.1964': DetectionType.dob,
        'जन्म तिथि: 12/08/1964': DetectionType.dob,
      });
    });
  });
}
