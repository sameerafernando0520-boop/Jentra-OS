import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_platform/jentra_expense_evidence_platform.dart';

void main() {
  test('bounded evidence reader copies the exact selected bytes', () async {
    final first = <int>[1, 2];
    final bytes = await readExpenseEvidenceBytes(
      Stream.fromIterable([
        first,
        <int>[3],
      ]),
      3,
    );
    first[0] = 99;
    expect(bytes, [1, 2, 3]);
  });
  test(
    'file growth cancels before later chunks or excess bytes are retained',
    () async {
      var readLater = false, cancelled = false;
      Stream<List<int>> changedFile() async* {
        try {
          yield [1, 2];
          yield [3];
          readLater = true;
          yield List.filled(100, 4);
        } finally {
          cancelled = true;
        }
      }

      await expectLater(
        readExpenseEvidenceBytes(changedFile(), 2),
        throwsFormatException,
      );
      expect(cancelled, true);
      expect(readLater, false);
    },
  );
  test('file shrinkage rejects an incomplete selected byte snapshot', () async {
    await expectLater(
      readExpenseEvidenceBytes(Stream.value([1]), 2),
      throwsFormatException,
    );
  });
  test(
    'oversize metadata rejects before subscribing to private content',
    () async {
      var read = false;
      Stream<List<int>> file() async* {
        read = true;
        yield [1];
      }

      await expectLater(
        readExpenseEvidenceBytes(file(), 10485761),
        throwsFormatException,
      );
      expect(read, false);
    },
  );
}
