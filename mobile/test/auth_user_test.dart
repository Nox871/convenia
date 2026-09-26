import 'package:convenia_mobile/models/auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthUser', () {
    test('firstName usa el primer nombre cuando la cuenta tiene nombre', () {
      const user = AuthUser(id: 1, email: 'andrespdr17@gmail.com', name: 'Andrés Pascual Díaz Riera');
      expect(user.firstName, 'Andrés');
      expect(user.displayName, 'Andrés Pascual Díaz Riera');
    });

    test('sin nombre cae al correo, pero nunca deja el saludo vacío', () {
      const user = AuthUser(id: 1, email: 'ana@example.com');
      expect(user.hasName, isFalse);
      expect(user.firstName, 'Ana');
    });

    test('un nombre con solo espacios se trata como ausente', () {
      const user = AuthUser(id: 1, email: 'ana@example.com', name: '   ');
      expect(user.hasName, isFalse);
    });

    test('fromJson lee el nombre y tolera su ausencia', () {
      expect(AuthUser.fromJson({'id': 1, 'email': 'a@b.co', 'name': 'Luis'}).name, 'Luis');
      expect(AuthUser.fromJson({'id': 1, 'email': 'a@b.co'}).name, isNull);
    });
  });
}
