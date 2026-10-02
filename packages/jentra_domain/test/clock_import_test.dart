import 'package:jentra_domain/jentra_people.dart';
import 'package:test/test.dart';

void main() {
  test(
    'CSV accepts quoted commas and CRLF without losing exact source identity',
    () {
      final preview = ClockFilePreview.parse(
        '\ufeffsource_key,observed_utc\r\n"SYN,1",2026-09-30T03:30:00Z\r\n'
        '"SYN""2",2026-09-30T11:30:00Z\r\n',
      );
      expect(preview.records.map((r) => r.sourceKey), ['SYN,1', 'SYN"2']);
      expect(preview.records.last.observedUtc, '2026-09-30T11:30:00Z');
    },
  );
  test(
    'malformed or normalized dates, duplicate keys and hidden fields fail',
    () {
      for (final csv in [
        'source_key,observed_utc\nA,2026-02-30T03:30:00Z',
        'source_key,observed_utc\nA,2026-09-30T24:00:00Z',
        'source_key,observed_utc\nA,2026-09-30T03:30:00+00:00',
        'source_key,observed_utc\nA,2026-09-30T03:30:00Z\nA,2026-09-30T04:30:00Z',
        'source_key,observed_utc,salary\nA,2026-09-30T03:30:00Z,100',
        'source_key,observed_utc\n"A,2026-09-30T03:30:00Z',
        'source_key,observed_utc\n A,2026-09-30T03:30:00Z',
      ]) {
        expect(() => ClockFilePreview.parse(csv), throwsFormatException);
      }
    },
  );
  test('file and row bounds reject before creating a command', () {
    expect(() => ClockFilePreview.parse('x' * 65537), throwsFormatException);
    expect(
      () => ClockFilePreview.parse('source_key,observed_utc\n'),
      throwsFormatException,
    );
    final rows = List.generate(201, (i) => 'SYN-$i,2026-09-30T03:30:00Z');
    expect(
      () =>
          ClockFilePreview.parse('source_key,observed_utc\n${rows.join('\n')}'),
      throwsFormatException,
    );
    final preview = ClockFilePreview.parse(
      'source_key,observed_utc\n${rows.take(200).join('\n')}',
    );
    expect(preview.records.length, 200);
    expect(
      () => preview.records.add(preview.records.first),
      throwsUnsupportedError,
    );
  });
}
