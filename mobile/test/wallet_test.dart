import 'package:flutter_test/flutter_test.dart';
import 'package:trevix/core/catalog.dart';
import 'package:trevix/core/i18n.dart';
import 'package:trevix/models/models.dart';

void main() {
  tearDown(() => Lang.instance.code = 'es');

  test('importes en USD como los acepta y muestra el servidor', () {
    expect(Money.parseCents('12'), 1200);
    expect(Money.parseCents('12.5'), 1250);
    expect(Money.parseCents(' 12,05 '), 1205);
    expect(Money.parseCents('12.505'), isNull);
    expect(Money.parseCents('-3'), isNull);
    expect(Money.parseCents('abc'), isNull);
    expect(Money.local(400).formatted, 'US\$ 4,00');
    expect(Money.local(123456).formatted, 'US\$ 1.234,56');
    Lang.instance.code = 'en';
    expect(Money.local(123456).formatted, 'US\$1,234.56');
    expect(const Money(1250, '').plain, '12.50');
    expect(const Money(500, '').plain, '5');
  });

  test('comisión del 20 % con el redondeo del servidor', () {
    expect(Money.commission(500, 20), 100);
    expect(Money.commission(999, 20), 200);
    expect(Money.commission(1, 20), 0);
    expect(500 - Money.commission(500, 20), 400);
  });

  test('campo collaborator del perfil', () {
    final future = DateTime.now().add(const Duration(days: 3)).toUtc().toIso8601String();
    final offer = CollaboratorOffer.fromJson({
      'accepting': true,
      'price': {'cents': 500, 'formatted': 'US\$ 5,00'},
      'days': 30,
      'exclusive_posts': 2,
      'access_until': future,
      'is_owner': false,
    });
    expect(offer.price!.cents, 500);
    expect(offer.hasAccess, isTrue);
    final expired = CollaboratorOffer.fromJson({'accepting': false, 'access_until': '2020-01-01T00:00:00Z'});
    expect(expired.hasAccess, isFalse);
    expect(expired.price, isNull);
    final profile = Profile.fromJson({'id': 1, 'username': 'ana', 'collaborator': {'accepting': true}});
    expect(profile.collaborator?.accepting, isTrue);
    expect(Profile.fromJson({'id': 1, 'username': 'ana'}).collaborator, isNull);
    expect(Me.fromJson({'id': 1, 'username': 'ana', 'collaborator_active': true}).collaboratorActive, isTrue);
  });

  test('«Suscriptores» solo con plan activo o al editar una exclusiva', () {
    expect(visibilitiesFor(collaborator: false).containsKey('subscribers'), isFalse);
    expect(visibilitiesFor(collaborator: true).containsKey('subscribers'), isTrue);
    expect(visibilitiesFor(collaborator: false, current: 'subscribers').containsKey('subscribers'), isTrue);
  });
}
