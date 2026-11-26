import 'package:flutter_test/flutter_test.dart';
import 'package:ghargharmatrimony/core/app_state.dart';
import 'package:ghargharmatrimony/core/labels.dart';
import 'package:ghargharmatrimony/core/translate.dart';
import 'package:ghargharmatrimony/main.dart';

void main() {
  group('navigation rules', () {
    test('while starting up everything waits on the splash', () {
      expect(redirectFor(Auth.unknown, false, '/'), '/splash');
      expect(redirectFor(Auth.unknown, false, '/splash'), isNull);
    });

    test('signed-out users only see the login pages', () {
      expect(redirectFor(Auth.loggedOut, false, '/'), '/login');
      expect(redirectFor(Auth.loggedOut, false, '/splash'), '/login');
      expect(redirectFor(Auth.loggedOut, false, '/admin'), '/admin/login');
      expect(redirectFor(Auth.loggedOut, false, '/login'), isNull);
      expect(redirectFor(Auth.loggedOut, false, '/admin/login'), isNull);
    });

    test('members without a profile must register first', () {
      expect(redirectFor(Auth.member, false, '/'), '/register');
      expect(redirectFor(Auth.member, false, '/login'), '/register');
      expect(redirectFor(Auth.member, false, '/register'), isNull);
      expect(redirectFor(Auth.member, false, '/help'), isNull);
    });

    test('members with a profile cannot enter the staff area', () {
      expect(redirectFor(Auth.member, true, '/'), isNull);
      expect(redirectFor(Auth.member, true, '/p/GG123'), isNull);
      expect(redirectFor(Auth.member, true, '/register'), '/');
      expect(redirectFor(Auth.member, true, '/admin'), '/');
      expect(redirectFor(Auth.member, true, '/admin/login'), '/');
    });

    test('staff stay inside the admin panel', () {
      expect(redirectFor(Auth.staff, false, '/admin'), isNull);
      expect(redirectFor(Auth.staff, false, '/admin/login'), '/admin');
      expect(redirectFor(Auth.staff, false, '/'), '/admin');
      expect(redirectFor(Auth.staff, false, '/chat/x'), '/admin');
    });
  });

  group('labels', () {
    test('height label', () {
      expect(heightLabel(170), contains("5'"));
      expect(heightLabel(null), isNull);
    });
  });

  group('translation', () {
    test('plain English needs no translation into English', () {
      expect(needsTranslation('Hello, how are you?', 'en'), isFalse);
      expect(needsTranslation('नमस्ते', 'en'), isTrue);
      expect(needsTranslation('Hello', 'hi'), isTrue);
    });
  });
}
