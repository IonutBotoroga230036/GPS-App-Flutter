import 'package:intl/intl.dart';

/// The server stores timestamps as the formatted string the phone sends,
/// in the format "yyyy-MM-dd HH:mm:ss.SSS". We send UTC to match the
/// `timestamp_utc` column semantics.
final DateFormat _fmt = DateFormat('yyyy-MM-dd HH:mm:ss.SSS');

String nowUtcTimestamp() => _fmt.format(DateTime.now().toUtc());

String formatUtc(DateTime dt) => _fmt.format(dt.toUtc());
