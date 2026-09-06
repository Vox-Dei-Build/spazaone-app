import 'package:flutter/foundation.dart';
import 'package:pasella/models/sales/sales_model.dart';

typedef RecordedSalesQuery = Future<List<Sale>> Function(
  DateTime start,
  DateTime endExclusive,
);

/// Tracks the truth of one selected sales period independently of its totals.
/// A failed read never replaces a successful snapshot with an empty result.
class RecordedSalesReader extends ChangeNotifier {
  RecordedSalesReader({
    required RecordedSalesQuery query,
    this.onLoaded,
    this.onError,
  }) : _query = query;

  final RecordedSalesQuery _query;
  final ValueChanged<List<Sale>>? onLoaded;
  final void Function(Object error, StackTrace stack)? onError;

  List<Sale> _sales = const [];
  (DateTime, DateTime)? _requestedRange;
  (DateTime, DateTime)? _loadedRange;
  bool _loading = false;
  bool _failed = false;
  int _generation = 0;
  bool _disposed = false;

  List<Sale> get sales => _sales;
  bool get isLoading => _loading;
  bool get hasError => _failed;
  bool get hasCurrentData =>
      _loadedRange != null && _loadedRange == _requestedRange;

  Future<void> load(DateTime start, DateTime endExclusive) async {
    if (_disposed) return;
    final generation = ++_generation;
    final range = (start, endExclusive);
    _requestedRange = range;
    _loading = true;
    _failed = false;
    notifyListeners();

    try {
      final result = await _query(start, endExclusive);
      if (_disposed || generation != _generation) return;
      _sales = List.unmodifiable(result);
      _loadedRange = range;
      _loading = false;
      onLoaded?.call(_sales);
    } catch (error, stack) {
      if (_disposed || generation != _generation) return;
      _failed = true;
      _loading = false;
      onError?.call(error, stack);
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> retry() async {
    final range = _requestedRange;
    if (range == null || _loading || _disposed) return;
    await load(range.$1, range.$2);
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
