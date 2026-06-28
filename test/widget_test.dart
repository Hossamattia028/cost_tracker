import 'package:flutter_test/flutter_test.dart';
import 'package:cost_tracker/core/app_strings.dart';

void main() {
  test('app name is Arabic', () {
    expect(AppStrings.appName, 'متتبع التكاليف');
  });
}
