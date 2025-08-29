import 'package:intl/intl.dart';

final _fmt = NumberFormat.currency(locale: 'en_ZA', symbol: 'R');
String zar(num v) => _fmt.format(v);
