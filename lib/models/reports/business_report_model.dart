class Report {
  final int totalNumberofNPAs;
  final List<dynamic> customersWithNPAs;
  final double nplRatio;
  final double cashflowImpact;

  Report({
    required this.totalNumberofNPAs,
    required this.customersWithNPAs,
    required this.nplRatio,
    required this.cashflowImpact,
  });
}
