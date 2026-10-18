import 'package:flutter_test/flutter_test.dart';
import 'package:minierp_app/core/utils/idempotency_key.dart';

void main() {
  test('retry keys can be minted on native and web platforms', () {
    final cache = IdempotencyKeyCache(prefix: 'ucash');
    final body = <String, dynamic>{'amount': 500.25};
    final key = cache.keyFor(body);
    expect(key, startsWith('ucash-'));
    expect(cache.keyFor(body), key);
    final stable = cache.stableKeyFor(body);
    expect(cache.stableKeyFor(body), stable);
    cache.reset();
    expect(cache.keyFor(body), isNot(key));
  });
}
