import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/api_client.dart';

void main() {
  test('ApiClient normalizes server URLs', () {
    expect(
      ApiClient(serverUrl: 'gullify.example.com/').serverUrl(),
      'https://gullify.example.com',
    );
    expect(
      ApiClient(serverUrl: 'http://192.168.1.10:8080').serverUrl(),
      'http://192.168.1.10:8080',
    );
  });

  test('ApiException flags unauthenticated', () {
    expect(ApiException('unauthenticated', 'x').isUnauthenticated, isTrue);
    expect(
      ApiException('other', 'x', statusCode: 401).isUnauthenticated,
      isTrue,
    );
    expect(ApiException('legacy_error', 'x').isUnauthenticated, isFalse);
  });
}
