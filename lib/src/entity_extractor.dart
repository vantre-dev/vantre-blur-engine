import 'protection.dart';

/// Regex-based classification of OCR text lines into sensitive entity types.
abstract final class EntityExtractor {
  // ML Kit's OCR routinely emits a space either side of '@'
  // ("john.doe @gmail.com"), so every @-based pattern has to tolerate it.
  static final _email = RegExp(
    r'[a-zA-Z0-9._%+-]+\s*@\s*[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}',
  );
  // Anchored on the scheme keyword rather than on "://", because OCR mangles
  // the separator: a real invoice line came back as "https:/lexample.compay",
  // with one slash read as an l and another dropped, and the old pattern
  // missed it completely. "http:" followed by non-space is a URL regardless
  // of how many slashes survived.
  static final _url = RegExp(
    r'\bhttps?:\S{4,}|\bwww\.\S{4,}'
    r'|\b[a-z0-9-]+\.(?:com|org|net|io|in|co|dev|app)\b',
    caseSensitive: false,
  );
  static final _phone = RegExp(
    r'(?:\+?\d{1,3}[\s-]?)?(?:\(\d{2,4}\)[\s-]?)?\d{3,5}[\s-]?\d{3,5}(?:[\s-]?\d{2,4})?'
    // French numbers are written in pairs ("06 12 34 56 78",
    // "+33 6 12 34 56 78"), which the grouping above never matched.
    r'|(?:\+33[\s.-]?|\b0)\d(?:[\s.-]?\d{2}){4}\b',
  );

  /// Wording that marks the digits on the line as a phone number. Kept
  /// narrow: these are labels, not any word that can precede a number.
  static final _phoneKeyword = RegExp(
    r'\b(?:tele)?phone\b|\b(?:mobile|cell|contact|tel|fax|whatsapp|'
    r'telefono|teléfono|telefone|celular|movil|móvil|'
    r'telefon|handy|mobil(?:nummer|telefon)?|'
    r't[ée]l[ée]phone|portable|t[ée]l)\b'
    // Devanagari has no ASCII word boundary, so no \b around these.
    r'|मोबाइल|फ़ोन|फोन',
    caseSensitive: false,
  );
  static final _creditCard = RegExp(r'\b(?:\d[ -]?){13,19}\b');
  static final _aadhaar = RegExp(r'\b\d{4}\s?\d{4}\s?\d{4}\b');
  static final _pan = RegExp(r'\b[A-Z]{5}\d{4}[A-Z]\b');
  static final _upi = RegExp(r'\b[\w.-]{2,}\s*@\s*[a-z]{2,}\b');
  static final _otp = RegExp(
    r'(?:\b(?:otp|one[- ]?time (?:password|code|pin)|login code|'
    r'verification code|security code|passcode|access code|auth code|'
    r'2fa code|'
    // es / pt / de / fr. German compounds the word, so each compound is
    // listed; "senha", "clave" and "TAN" are how banks and apps there
    // actually phrase it.
    r'c[óo]digo|senha|clave|'
    r'best[äa]tigungscode|sicherheitscode|zugangscode|anmeldecode|'
    r'einmalcode|m?tan|'
    // A bare "code" is a login code only when nothing says otherwise:
    // postal, zip, area, promo and bank codes all print the same way.
    r'(?<!(?:zip|area|postal|post|country|dial|promo|coupon|discount|'
    r'sort|swift|bank|branch|pin|product|item|order|tracking)\s)code'
    r')\b(?!\s*(?:postal|postale|iban|swift|bic))'
    // Hindi: no \b, Devanagari has no ASCII word boundary.
    r'|ओटीपी|सत्यापन कोड)'
    // Up to 25 characters between the word and the code: Spanish and French
    // put a whole phrase there ("código de verificación es").
    r'[^\d]{0,25}\d[\d\s-]{3,10}\d',
    caseSensitive: false,
  );
  static final _ssn = RegExp(r'\b\d{3}-\d{2}-\d{4}\b');
  // The two characters after the country code are check DIGITS, but OCR
  // routinely reads them as the letters they resemble (GB00 -> GBOO). That
  // dropped a real IBAN through to the phone rule in the accuracy harness,
  // and a line with fewer digits would have fallen through to nothing at all.
  // Accepting the homoglyphs costs little: the country code and the 15+
  // character alphanumeric run still carry the match.
  static final _iban = RegExp(
    r'\b[A-Za-z]{2}[0-9OoIlSsBb]{2}[A-Za-z0-9]{11,30}\b',
  );
  static final _passport = RegExp(
    '${r'\b(?:passport|pasaporte|passaporte|reisepass|passeport)\b'}'
    '$_numberLabel${r'[^\w]{0,15}[A-Za-z0-9]{6,9}\b'}',
    caseSensitive: false,
  );

  /// "No.", "Nr.", "n.º", "nº", "n°", "número", "Nummer" -- the number label
  /// that sits between a document's name and its value. Optional, and the
  /// punctuation in it is optional too (OCR drops it).
  static const _numberLabel =
      r'(?:[\s-]*(?:no\.?|nr\.?|n\.?\s?[º°o]\.?|n[úu]m(?:ero)?\.?|'
      r'num[ée]ro|number|nummer|#))?';
  static final _driversLicense = RegExp(
    // "Driving licence" is the UK and Indian wording and was missed entirely
    // by the driver'?s form, so the number stayed visible on an ID card in
    // two of the app's stated markets.
    r"\b(?:driv(?:er'?s?|ing)\s*licen[sc]e|dl\s*(?:no\.?|#)|"
    r"licen[sc]e\s*(?:no\.?|#)|"
    r"(?:permiso|carn[ée]t?)\s*de\s*conducir|"
    r"carteira\s*de\s*(?:motorista|habilita[çc][ãa]o)|cnh|"
    r"f[üu]hrerschein|permis\s*de\s*conduire)\b"
    // The identifier may carry a state prefix separated by a space or
    // hyphen ("TX 41928815", "CA-D1234567"), so allow single separators
    // inside the run rather than requiring 5+ consecutive alphanumerics.
    '$_numberLabel${r'[^\w]{0,15}[A-Za-z0-9](?:[A-Za-z0-9]|[\s-][A-Za-z0-9]){4,19}'}',
    caseSensitive: false,
  );
  static final _dob = RegExp(
    r'(?:\b(?:dob|date\s*of\s*birth|geburtstag|geboren(?:\s*am)?|'
    r'geb\.(?:\s*am)?|'
    r'fecha\s*de\s*nacimiento|data\s*de\s*nascimento|'
    r'date\s*de\s*naissance|nacimiento|nascimento|n[ée]e?\s*le)\b'
    r'|जन्म\s*तिथि)'
    r'[^\w]{0,5}\d{1,4}[/\-.]\d{1,2}[/\-.]\d{1,4}',
    caseSensitive: false,
  );

  /// A bare date with no label. ID cards put the caption and the value on
  /// separate OCR lines ("Geburtstag/Date of birth" then "12.08.1964"), so
  /// the keyed pattern above can never see them together.
  static final _bareDate = RegExp(
    r'^\D{0,3}(\d{1,4})[/\-.](\d{1,2})[/\-.](\d{1,4})\b',
  );
  static final _bankAccount = RegExp(
    r'\b(?:account\s*(?:no\.?|number)|routing\s*(?:no\.?|number))\b'
    r'[^\w]{0,15}\d{4,17}'
    // Statements also write it unlabelled ("Paid to account 000123456789"),
    // which the keyed form above never saw. Six digits minimum so that money
    // amounts on the surrounding rows cannot arm it.
    r'|\baccount\b[^\w]{0,15}\d{6,17}'
    // es / pt / de / fr labels. Account numbers there are printed in groups
    // ("0049 1500 05 1234567892", "56789-0"), so separators are allowed.
    r'|\b(?:n[úu]mero\s*de\s*cuenta|n\.?\s?[º°o]\.?\s*de\s*cuenta|'
    r'ag[êe]ncia|kontonummer|konto-?nr\.?|'
    r'num[ée]ro\s*de\s*compte|n\s?°\s*de\s*compte)'
    r'[^\w]{0,15}\d(?:[\s.-]?\d){3,24}'
    // The bare word needs a longer number, like the English one above:
    // "Compte 2024" and "cuenta 3" are not accounts.
    r'|\b(?:cuenta|conta(?:\s*corrente|\s*poupan[çc]a)?|compte|konto)\b'
    r'[^\w]{0,15}\d(?:[\s.-]?\d){4,24}',
    caseSensitive: false,
  );

  /// A person's name, found only where the document names the field.
  ///
  /// There is no bare "two capitalised words" rule here, deliberately. That
  /// shape is everywhere in the documents this app scans -- "Closing
  /// Balance", "Recent Transactions", "Card Payment", every heading on every
  /// statement -- and the accuracy harness counts an EXTRA as a usability
  /// failure for good reason: a detector that covers half a statement teaches
  /// the user to ignore it. Labelled fields and honorifics are the two places
  /// a name can be identified without understanding the sentence, so they are
  /// the two rules.
  ///
  /// No anchor on the colon (house rule: OCR mangles punctuation). The
  /// separator is optional and any non-word run is accepted, the same shape
  /// the bank-account rule uses.
  static final _nameKeyed = RegExp(
    r'\b(?:'
    r'(?:full|first|last|given|middle|legal|maiden|preferred)\s*names?'
    r'|surname|name'
    r'|(?:card|account|policy|licence|license)\s*holder'
    r'|holder|passenger|beneficiary|payee|patient|recipient|bearer'
    r'|(?:issued|signed|prepared|billed|sold)\s*to'
    r'|attn\.?|attention'
    // es / pt / de / fr
    r'|nombres?(?:\s*completo)?|apellidos?|titular'
    r'|nome(?:\s*completo)?|sobrenome'
    r'|vornamen?|nachname|familienname|geburtsname|(?:konto)?inhaber(?:in)?'
    // Indian cards (PAN, Aadhaar letters) name the parent or spouse too.
    r"|(?:father|mother|spouse|husband)'?s?\s*name"
    r'|nom(?:\s*de\s*famille)?|pr[ée]noms?|titulaire'
    r')'
    // The value: one to four name-ish words. Letters only, plus the marks
    // real names carry -- apostrophes, hyphens and initials' full stops --
    // so a labelled NUMBER (an account holder's account number) cannot be
    // mistaken for the holder.
    r"[^\w]{0,15}([A-Z][\p{L}'’.-]*(?:\s+[\p{L}'’.-]*[\p{L}][\p{L}'’.-]*){0,3})",
    caseSensitive: false,
    unicode: true,
  );

  /// A name introduced by an honorific, with no field label at all.
  ///
  /// "Dear Mr Smith" carries a real name whether or not the line names a
  /// field, and the honorific is specific enough to stand on its own.
  static final _nameHonorific = RegExp(
    r"\b(?:mr|mrs|ms|miss|mx|dr|prof|sir|dame|rev|"
    r"sr|sra|srta|herr|frau|mme|mlle)\.?\s+"
    r"([A-Z][\p{L}'’.-]*(?:\s+[\p{L}'’.-]*[\p{L}][\p{L}'’.-]*){0,3})",
    caseSensitive: false,
    unicode: true,
  );

  /// Words that follow a name label but are not a name.
  ///
  /// The label is often its own line on a form ("Name" above an empty box),
  /// or introduces something that is emphatically not a person: "Account
  /// holder: SAVINGS", "Name of bank". Without this the label alone would
  /// arm the rule and every form heading would be covered.
  static final _notAName = RegExp(
    r'^(?:of|is|as|on|the|and|or|to|for|not|n/?a|none|unknown|'
    r'bank|branch|company|business|firm|account|card|type|status|'
    r'address|number|no|date|city|state|country|code|amount|balance|'
    // Other fields' labels. In a two-column form these sit right where a
    // name value would, and a stray one must not be read as a name.
    r'email|e-?mail|phone|mobile|telephone|tel|fax|dob|ssn|nino|sin|tfn|'
    r'passport|licence|license|iban|upi|otp|pan|aadhaar|medicare|'
    r'savings|checking|current|credit|debit|joint|primary|secondary|'
    // The same fillers in es / pt / de / fr: "Nombre del banco",
    // "Nom de la banque", "Name der Bank" are headings, not people.
    r'del?|la|le|les|los|las|du|des|do|da|dos|das|der|die|den|y|e|et|und|'
    r'banco|banque|agencia|ag[êe]ncia|cuenta|conta|compte|konto|'
    r'n[úu]mero|num[ée]ro|nummer|fecha|data|datum|'
    r'direcci[óo]n|endere[çc]o|adresse|anschrift|correo|'
    r'tel[ée]fono|telefone|telefon|t[ée]l[ée]phone|'
    r'documento|document|dokument|completo|complet|famille|familia)$',
    caseSensitive: false,
  );

  /// Words that cannot appear anywhere in a person's name.
  ///
  /// Separate from [_notAName] because they disqualify the whole value
  /// rather than just themselves: "Cardholder Not Present" is a payment
  /// status, and every word of it passing the filler test individually is
  /// exactly how it slipped through.
  static final _neverInName = RegExp(
    r'^(?:present|absent|required|applicable|available|verified|'
    r'provided|blank|empty|pending|expired|declined|approved|'
    r'total|subtotal|balance|payment|transfer|credit|debit|invoice)$',
    caseSensitive: false,
  );

  /// A line that is nothing but a name label, with the value somewhere else.
  ///
  /// Forms and statements lay names out as a heading over a value --
  /// "ACCOUNT HOLDER" on one line, "John Doe" on the next -- and OCR returns
  /// those as two separate lines, so the same-line rule cannot see the pair.
  /// This half identifies the heading; [looksLikeNameValue] identifies the
  /// value; only together do they flag anything.
  static final _bareNameLabel = RegExp(
    // Indian cards print every label twice, "नाम / Name". The OCR reads
    // Latin script only, so the Hindi half comes back as a few stray
    // letters ("ATA / Name"); anything short before a slash is allowed.
    r'^(?:[^/]{0,24}/)?[^\w]*(?:'
    r'(?:full|first|last|given|middle|legal|maiden|preferred)\s*names?'
    r'|surname|name'
    r'|(?:card|account|policy|licence|license)\s*holder'
    r'|holder|passenger|beneficiary|payee|patient|recipient|bearer'
    r'|(?:issued|signed|prepared|billed|sold)\s*to'
    r'|attn\.?|attention'
    // es / pt / de / fr
    r'|nombres?(?:\s*completo)?|apellidos?|titular'
    r'|nome(?:\s*completo)?|sobrenome'
    r'|vornamen?|nachname|familienname|geburtsname|(?:konto)?inhaber(?:in)?'
    // Indian cards (PAN, Aadhaar letters) name the parent or spouse too.
    r"|(?:father|mother|spouse|husband)'?s?\s*name"
    r'|nom(?:\s*de\s*famille)?|pr[ée]noms?|titulaire'
    r')[^\w]*$',
    caseSensitive: false,
  );

  /// Whether [t] is a line that only names the field.
  static bool isBareNameLabel(String t) => _bareNameLabel.hasMatch(t.trim());

  /// Whether [t] could be the value under a [isBareNameLabel] heading.
  ///
  /// Only ever consulted when the previous line already established that a
  /// name is expected here, which is what makes it safe to accept a plain
  /// capitalised phrase -- the thing that must never be a rule on its own.
  static bool looksLikeNameValue(String t) {
    final v = t.trim();
    if (v.length < 2 || v.length > 60) return false;
    if (!RegExp(r"^[\p{L}][\p{L}\s'’.,/-]*$", unicode: true).hasMatch(v)) {
      return false;
    }
    final words = v.split(RegExp(r'[\s/]+')).where((w) => w.isNotEmpty);
    if (words.isEmpty || words.length > 4) return false;
    if (words.every((w) => _notAName.hasMatch(w))) return false;
    if (words.any(_neverInName.hasMatch)) return false;
    // At least one word carrying a capital: a name is a proper noun, and
    // this is what keeps a lowercase sentence fragment out.
    return words.any((w) => w != w.toLowerCase());
  }

  /// The honorific and name inside [t], when that is all that makes it a
  /// name line, or null.
  ///
  /// Only the honorific rule returns a span. A labelled field is redacted
  /// whole, like every other detection -- "Name: Marcus Ellery" has nothing
  /// on it worth preserving. An honorific appears mid-SENTENCE, so covering
  /// the line hides the sentence to hide the name.
  ///
  /// The honorific is included in the span, not just the name: "Dear Mrs
  /// ___" still discloses a title, and it reads as a slip rather than a
  /// choice.
  static String? honorificSpan(String t) {
    final m = _nameHonorific.firstMatch(t);
    if (m == null || _nameValue(m) == null) return null;
    // Only worth narrowing if the line is more than the span itself.
    final span = t.substring(m.start, m.end).trim();
    return span.length < t.trim().length ? span : null;
  }

  /// Whether [t] carries a person's name, by label or by honorific.
  static bool hasPersonName(String t) =>
      _nameValue(_nameKeyed.firstMatch(t)) != null ||
      _nameValue(_nameHonorific.firstMatch(t)) != null;

  /// The captured value of a name match, or null if it is not name-shaped.
  static String? _nameValue(RegExpMatch? m) {
    if (m == null) return null;
    final value = m.group(1)?.trim() ?? '';
    if (value.length < 2) return null;
    // A single word that is one of the form-filler words is the label
    // running into the next field, not a name.
    final words = value.split(RegExp(r'\s+'));
    if (words.every((w) => _notAName.hasMatch(w))) return null;
    if (words.any(_neverInName.hasMatch)) return null;
    // "Name" alone, then a digit-led value: that is some other field.
    if (RegExp(r'\d').hasMatch(value)) return null;
    return value;
  }

  static final _btcAddress = RegExp(
    r'\b(?:bc1[a-z0-9]{25,39}|[13][a-km-zA-HJ-NP-Z1-9]{25,34})\b',
  );
  static final _ethAddress = RegExp(r'\b0x[a-fA-F0-9]{40}\b');
  static final _ipAddress = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b');
  static final _sin = RegExp(
    r'\b(?:sin|social insurance (?:number|no\.?))\b'
    r'[^\d]{0,10}\d{3}[\s-]?\d{3}[\s-]?\d{3}\b',
    caseSensitive: false,
  );
  static final _nino = RegExp(
    r'\b[A-Za-z]{2}\s?\d{2}\s?\d{2}\s?\d{2}\s?[A-Za-z]\b',
  );
  static final _tfn = RegExp(
    r'\b(?:tfn|tax file number)\b[^\d]{0,10}\d[\d\s]{6,9}\d\b',
    caseSensitive: false,
  );
  static final _medicare = RegExp(
    r'\bmedicare\b[^\d]{0,15}\d{4}[\s-]?\d{5}[\s-]?\d{1,2}\b',
    caseSensitive: false,
  );

  /// Real boarding passes almost never print "booking reference" in full —
  /// "Booking Ref", "Conf #", "Reservation code" are what actually appear,
  /// and requiring the full phrase missed every one of them.
  static final _pnr = RegExp(
    r'\b(?:booking\s*ref(?:erence)?|booking\s*code|'
    r'(?:statement|account|order|payment)?\s*ref(?:erence)?\.?\s*(?:no\.?|number|#)?|'
    r'conf(?:irmation)?\s*(?:code|no\.?|number|#)?|'
    r'reservation\s*(?:code|no\.?|number)?|pnr|record\s*locator|'
    r'e-?ticket(?:\s*number)?)\b[^\w]{0,10}'
    r'(?=[A-Za-z0-9-]*\d)[A-Za-z0-9](?:[A-Za-z0-9-]{3,10})[A-Za-z0-9]\b',
    caseSensitive: false,
  );

  /// IATA flight designator: a two-character airline code (letter+letter,
  /// letter+digit or digit+letter — AI, EK, AC, 6E, U2) followed by 1-4
  /// digits. Matched by PATTERN, not against a list of airlines, so every
  /// carrier is covered.
  static final _flightKeyed = RegExp(
    r'\b(?:flight|flt|vuelo|voo|vol)\b[^A-Za-z0-9]{0,10}'
    r'(?:[A-Z][A-Z0-9]|[0-9][A-Z])\s?\d{1,4}[A-Z]?\b',
    caseSensitive: false,
  );

  /// Standalone designator with no keyword, e.g. a bare "MU219" on a pass.
  /// Case-SENSITIVE on purpose: lowercase would match ordinary words such
  /// as "in 2024". Two to four digits only, which also keeps US state+ZIP
  /// pairs ("CA 90210", five digits) out.
  static final _flightBare = RegExp(
    r'\b(?:[A-Z][A-Z0-9]|[0-9][A-Z])\s?\d{2,4}\b',
  );

  /// An IBAN printed in blocks of four ("ES91 2100 0418 4502 0005 1332"),
  /// the way every statement prints it. Only accepted when it passes the
  /// ISO 13616 mod-97 check, so a run of digit groups that merely starts
  /// with two letters is not taken for one.
  static final _ibanGrouped = RegExp(
    r'\b([A-Za-z]{2}[0-9OoIl]{2}(?:\s?[A-Za-z0-9]{4}){2,7}(?:\s?[A-Za-z0-9]{1,3})?)\b',
  );

  static bool _isGroupedIban(String t) {
    for (final m in _ibanGrouped.allMatches(t)) {
      // Undo the homoglyphs OCR puts in the check digits (see _iban).
      final raw = m.group(1)!.replaceAll(RegExp(r'\s'), '').toUpperCase();
      final check = raw.substring(2, 4).replaceAll('O', '0').replaceAll(RegExp('[IL]'), '1');
      final s = raw.substring(4) + raw.substring(0, 2) + check;
      var rem = 0;
      for (final c in s.codeUnits) {
        final v = c >= 65 ? c - 55 : c - 48;
        if (v < 0 || v > 35) return false;
        rem = (v > 9 ? rem * 100 + v : rem * 10 + v) % 97;
      }
      if (rem == 1) return true;
    }
    return false;
  }

  // ---- National ID numbers -------------------------------------------------
  //
  // Where a country's number carries a check digit or letter, it is matched
  // BARE and the checksum does the work of a keyword: a random digit run
  // passes a mod-23 or mod-11 check only a few percent of the time, and the
  // format narrows it further. Everything else needs a label.

  /// Spanish DNI (8 digits + check letter) and NIE (X/Y/Z + 7 digits + letter).
  static final _dni = RegExp(r'\b([XYZxyz]?)(\d{7,8})[\s-]?([A-Za-z])\b');
  static const _dniLetters = 'TRWAGMYFPDXBNJZSQVHLCKE';

  static bool _validDni(RegExpMatch m) {
    final prefix = m.group(1)!.toUpperCase();
    final digits = m.group(2)!;
    // DNI is exactly 8 digits with no prefix; NIE is a prefix + 7 digits.
    if (prefix.isEmpty != (digits.length == 8)) return false;
    final n = int.parse('${prefix.isEmpty ? '' : 'XYZ'.indexOf(prefix)}$digits');
    return _dniLetters[n % 23] == m.group(3)!.toUpperCase();
  }

  /// Brazilian CPF: 000.000.000-00. Bare, it must carry its separators, which
  /// is what keeps an 11-digit Brazilian mobile number out; with a "CPF"
  /// label the digits may run together.
  static final _cpf = RegExp(
    r'\b(\d{3})([.,\s]?)(\d{3})[.,\s]?(\d{3})([\s.-]?)(\d{2})\b',
  );
  static final _cpfLabel = RegExp(r'\bcpf\b', caseSensitive: false);

  static bool _validCpf(String digits) {
    if (digits.length != 11 || RegExp(r'^(\d)\1{10}$').hasMatch(digits)) {
      return false; // 111.111.111-11 passes the sums but is never issued
    }
    final d = digits.split('').map(int.parse).toList();
    int check(int len) {
      var sum = 0;
      for (var i = 0; i < len; i++) {
        sum += d[i] * (len + 1 - i);
      }
      return (sum * 10) % 11 % 10;
    }
    return check(9) == d[9] && check(10) == d[10];
  }

  /// French social security number (NIR): 15 digits in 7 groups, the last
  /// two a mod-97 key. Corsica writes 2A / 2B in the department field.
  static final _nir = RegExp(
    r'\b([12])\s?(\d{2})\s?(\d{2})\s?(\d{2}|2[ABab])\s?(\d{3})\s?(\d{3})\s?(\d{2})\b',
  );

  static bool _validNir(RegExpMatch m) {
    final dept = m.group(4)!.toUpperCase().replaceAll('2A', '19').replaceAll('2B', '18');
    final body = '${m.group(1)}${m.group(2)}${m.group(3)}$dept${m.group(5)}${m.group(6)}';
    return 97 - int.parse(body) % 97 == int.parse(m.group(7)!);
  }

  /// A document number introduced by its label: German Ausweis, French CNI,
  /// Brazilian RG, and the generic "document number" in each language.
  static final _idDocKeyed = RegExp(
    r'\b(?:dokumentennummer|ausweis(?:nummer|-?nr\.?)|personalausweis(?:nummer)?|'
    r'n[úu]mero\s*de\s*documento|n[úu]mero\s*de\s*soporte|'
    r'n[úu]mero\s*do\s*documento|'
    r'num[ée]ro\s*du\s*document|n\s?°\s*du\s*document|'
    r'n\.?\s?[º°o]\.?\s*(?:de|do)\s*documento|'
    r"carte\s*nationale\s*d.identit[ée]|"
    r'rg|registro\s*geral|identidade)\b'
    r'[^\w]{0,15}(?=[A-Za-z0-9.\s-]*\d)[A-Za-z0-9](?:[A-Za-z0-9]|[.\s-][A-Za-z0-9]){5,13}',
    caseSensitive: false,
  );

  /// The German ID card number printed alone in the card's corner: nine
  /// characters from the restricted alphabet the Bundesdruckerei uses (no
  /// vowels, no B/D/Q/S), and only when it is the WHOLE line.
  static final _ausweisBare = RegExp(
    r'^[CFGHJKLMNPRTVWXYZ][CFGHJKLMNPRTVWXYZ0-9]{8}$',
  );

  /// Pakistani CNIC / NICOP: 5-digit region, 7-digit family, 1-digit
  /// gender. With its dashes the shape is specific enough to match bare (the
  /// region code starts 1-7); written without them it is 13 digits, the same
  /// length as some card numbers, so the plain form needs the label.
  static final _cnic = RegExp(r'\b[1-7]\d{4}-\d{7}-\d\b');
  static final _cnicKeyed = RegExp(
    r'\b(?:cnic|nicop)\b(?:\s*no\.?)?[^\d]{0,10}\d{5}[\s-]?\d{7}[\s-]?\d\b',
    caseSensitive: false,
  );

  static bool _isNationalId(String t) {
    if (_cnic.hasMatch(t) || _cnicKeyed.hasMatch(t)) return true;
    for (final m in _dni.allMatches(t)) {
      if (_validDni(m)) return true;
    }
    for (final m in _cpf.allMatches(t)) {
      final digits = '${m.group(1)}${m.group(3)}${m.group(4)}${m.group(6)}';
      final separated = m.group(2)!.isNotEmpty || m.group(5)!.isNotEmpty;
      if ((separated || _cpfLabel.hasMatch(t)) && _validCpf(digits)) {
        return true;
      }
    }
    for (final m in _nir.allMatches(t)) {
      if (_validNir(m)) return true;
    }
    if (_idDocKeyed.hasMatch(t)) return true;
    final bare = t.trim();
    return _ausweisBare.hasMatch(bare) &&
        RegExp(r'\d').allMatches(bare).length >= 4;
  }

  /// Brazil's random Pix key (a v4 UUID), only when the line names it: a bare
  /// UUID is just as likely an order or session ID.
  static final _pixKey = RegExp(
    r'\b(?:chave\s*pix|pix)\b[^\w]{0,15}'
    r'[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b',
    caseSensitive: false,
  );

  /// Returns the sensitive entity type for a line of OCR text, or null.
  /// Pro-only types are still detected; gating happens in the UI layer.
  /// [minPhoneDigits] tunes phone-number strictness (sensitivity setting).
  /// A bare date that is plausibly a date of BIRTH.
  ///
  /// Deliberately narrow, because flagging every date would light up every
  /// transaction row on a bank statement. Two constraints do the work: the
  /// line must be essentially just the date (a caption line like
  /// "04 Jun Rent transfer" is rejected), and the year must be at least ten
  /// years in the past — which also excludes document EXPIRY dates, the
  /// other bare date printed on an ID card.
  static bool _looksLikeBirthDate(String t) {
    final m = _bareDate.firstMatch(t);
    if (m == null) return false;
    if (t.length > 24) return false;
    final a = int.tryParse(m.group(1)!) ?? 0;
    final c = int.tryParse(m.group(3)!) ?? 0;
    // Year is whichever end is four digits (12.08.1964 or 1964-08-12).
    final year = c > 31 ? c : (a > 31 ? a : 0);
    if (year < 1900) return false;
    return year <= DateTime.now().year - 10;
  }

  static DetectionType? classify(String text, {int minPhoneDigits = 8}) {
    final t = text.trim();
    if (t.length < 5) return null;
    if (_email.hasMatch(t)) return DetectionType.email;
    if (_pan.hasMatch(t)) return DetectionType.pan;
    if (_ssn.hasMatch(t)) return DetectionType.ssn;
    if (_sin.hasMatch(t)) return DetectionType.sin;
    // Keyword-anchored rules outrank bare numeric ones. "Account number:
    // 000123456789" is twelve digits, so the bare Aadhaar pattern used to
    // claim it and bankAccount never fired at all; the line naming itself is
    // far stronger evidence than digit count. Same reasoning that already
    // puts the card check ahead of Aadhaar below. All three types are Pro, so
    // this only ever changed the label, never whether the line was covered.
    if (_bankAccount.hasMatch(t)) return DetectionType.bankAccount;
    // Checksum-validated or labelled, so it outranks the bare card and
    // Aadhaar digit counts below: a French NIR is 15 digits and the card
    // rule would otherwise take it.
    if (_isNationalId(t)) return DetectionType.nationalId;
    // Before the card rule, which would take the digit groups otherwise.
    if (_isGroupedIban(t)) return DetectionType.iban;
    // Card before Aadhaar: a 16-digit card contains a 4-4-4 substring
    // that would otherwise match the Aadhaar pattern.
    if (_creditCard.hasMatch(t) && _digitCount(t) >= 13) {
      return DetectionType.creditCard;
    }
    if (_otp.hasMatch(t)) return DetectionType.otp;
    if (_dob.hasMatch(t) || _looksLikeBirthDate(t)) return DetectionType.dob;
    if (_passport.hasMatch(t)) return DetectionType.passport;
    if (_driversLicense.hasMatch(t)) return DetectionType.driversLicense;
    // Bare Aadhaar (12 digits, no label) sits below every LABELLED ID rule,
    // and yields to a phone label: a German mobile ("Handy 0151 23456789")
    // and a French licence ("Permis de conduire n° 123456789012") are both
    // 12 digits and were being taken for Aadhaar numbers.
    if (_aadhaar.hasMatch(t) &&
        _digitCount(t) == 12 &&
        !_phoneKeyword.hasMatch(t)) {
      return DetectionType.aadhaar;
    }
    if (_tfn.hasMatch(t)) return DetectionType.tfn;
    if (_medicare.hasMatch(t)) return DetectionType.medicare;
    if (_pnr.hasMatch(t)) return DetectionType.pnr;
    if (_flightKeyed.hasMatch(t) || _flightBare.hasMatch(t)) {
      return DetectionType.flightNumber;
    }
    if (_nino.hasMatch(t)) return DetectionType.nino;
    if (_iban.hasMatch(t)) return DetectionType.iban;
    if (_url.hasMatch(t)) return DetectionType.url;
    if (_ethAddress.hasMatch(t) || _btcAddress.hasMatch(t)) {
      return DetectionType.crypto;
    }
    if (_pixKey.hasMatch(t)) return DetectionType.pixKey;
    if (_upi.hasMatch(t)) return DetectionType.upi;
    // Below every rule whose value is a number or an address. A labelled
    // name is strong evidence, but "Cardholder: 4539 8712 3344 9021" is a
    // card first and "Account holder number 000123456789" is an account
    // first -- the more specific answer wins, exactly as it does for the
    // numeric rules above each other.
    if (hasPersonName(t)) return DetectionType.personName;
    // The ratio guard exists to stop prose that happens to contain numbers
    // from becoming a phone number, but a label is itself made of letters:
    // "Telephone: +1 555 0100" scores 0.36 and was thrown away. An explicit
    // label is stronger evidence than the ratio it dilutes, so it waives the
    // guard. This one is free-tier, so the miss was unredacted for everyone.
    //
    // Ratio is measured on the MATCH itself, not the whole line, for the
    // same reason: a chat bubble like "You can reach (415) 555-0192. My
    // account number is" is mostly prose, so the line-wide ratio was ~0.26
    // and the number went unblurred even though it's an obvious phone
    // number sitting right there. The pattern itself already requires the
    // digits to sit close together in a phone-like shape, so this doesn't
    // meaningfully loosen what counts as a match -- it just stops
    // surrounding prose from diluting a real one away.
    final phoneMatch = _phone.firstMatch(t);
    if (phoneMatch != null && _digitCount(t) >= minPhoneDigits) {
      if (_digitRatio(phoneMatch.group(0)!) > 0.5 ||
          _phoneKeyword.hasMatch(t)) {
        return DetectionType.phone;
      }
    }
    if (_ipAddress.hasMatch(t)) return DetectionType.ipAddress;
    return null;
  }

  static int _digitCount(String t) =>
      t.runes.where((r) => r >= 0x30 && r <= 0x39).length;

  static double _digitRatio(String t) {
    final clean = t.replaceAll(RegExp(r'\s'), '');
    if (clean.isEmpty) return 0;
    return _digitCount(clean) / clean.length;
  }
}
