import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:shimmer/shimmer.dart';

/// The shared loading treatment for content whose final shape is predictable.
///
/// Keep indeterminate progress indicators for actions such as saving, sending,
/// uploading, or signing in. A shimmer is reserved for data-backed surfaces so
/// it can preview the structure that will replace it.
class SpazaShimmer extends StatelessWidget {
  const SpazaShimmer({
    super.key,
    required this.child,
    required this.semanticsLabel,
  });

  final Widget child;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: semanticsLabel,
      child: _SpazaShimmerMask(child: child),
    );
  }
}

class _SpazaShimmerMask extends StatelessWidget {
  const _SpazaShimmerMask({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final skeleton = ExcludeSemantics(child: child);
    return MediaQuery.maybeOf(context)?.disableAnimations == true
        ? skeleton
        : Shimmer.fromColors(
            baseColor: SpazaColors.subtle,
            highlightColor: SpazaColors.surface,
            child: skeleton,
          );
  }
}

/// A neutral shape used inside [SpazaShimmer].
class SpazaSkeletonBox extends StatelessWidget {
  const SpazaSkeletonBox({
    super.key,
    required this.height,
    this.width,
    this.radius = SpazaRadius.small,
    this.shape = BoxShape.rectangle,
  });

  final double height;
  final double? width;
  final double radius;
  final BoxShape shape;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: SpazaColors.subtle,
          shape: shape,
          borderRadius: shape == BoxShape.rectangle
              ? BorderRadius.circular(radius)
              : null,
        ),
      );
}

/// A text-line placeholder that sizes itself as a fraction of its parent.
class SpazaSkeletonLine extends StatelessWidget {
  const SpazaSkeletonLine({
    super.key,
    this.widthFactor = 1,
    this.height = 12,
    this.alignment = Alignment.centerLeft,
  }) : assert(widthFactor > 0 && widthFactor <= 1);

  final double widthFactor;
  final double height;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => Align(
        alignment: alignment,
        child: FractionallySizedBox(
          widthFactor: widthFactor,
          child: SpazaSkeletonBox(height: height),
        ),
      );
}

/// A compact list placeholder for tabs and pages backed by remote data.
class SpazaListSkeleton extends StatelessWidget {
  const SpazaListSkeleton({
    super.key,
    required this.semanticsLabel,
    this.itemCount = 5,
    this.padding = const EdgeInsets.all(16),
    this.showLeading = true,
    this.showTrailing = true,
    this.shrinkWrap = false,
    this.physics,
  });

  final String semanticsLabel;
  final int itemCount;
  final EdgeInsetsGeometry padding;
  final bool showLeading;
  final bool showTrailing;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: semanticsLabel,
      child: ListView.separated(
        key: const ValueKey('spaza-list-loading-shimmer'),
        padding: padding,
        shrinkWrap: shrinkWrap,
        physics: physics,
        itemCount: itemCount,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, __) => Container(
          key: const ValueKey('spaza-list-skeleton-card'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: SpazaColors.surface,
            border: Border.all(color: SpazaColors.border),
            borderRadius: BorderRadius.circular(SpazaRadius.control),
          ),
          child: _SpazaShimmerMask(
            child: Row(
              children: [
                if (showLeading) ...[
                  const SpazaSkeletonBox(
                    height: 40,
                    width: 40,
                    radius: SpazaRadius.control,
                  ),
                  const SizedBox(width: 12),
                ],
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SpazaSkeletonLine(widthFactor: .62, height: 14),
                      SizedBox(height: 9),
                      SpazaSkeletonLine(widthFactor: .38, height: 10),
                    ],
                  ),
                ),
                if (showTrailing) ...[
                  const SizedBox(width: 16),
                  const SpazaSkeletonBox(height: 14, width: 64),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A receipt-like placeholder for transaction, order, and campaign details.
class SpazaDetailSkeleton extends StatelessWidget {
  const SpazaDetailSkeleton({
    super.key,
    required this.semanticsLabel,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 24),
  });

  final String semanticsLabel;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: semanticsLabel,
      child: ListView(
        key: const ValueKey('spaza-detail-loading-shimmer'),
        padding: padding,
        children: [
          Container(
            key: const ValueKey('spaza-detail-skeleton-card'),
            height: 132,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: SpazaColors.surface,
              border: Border.all(color: SpazaColors.border),
              borderRadius: BorderRadius.circular(SpazaRadius.surface),
            ),
            child: const _SpazaShimmerMask(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SpazaSkeletonLine(widthFactor: .28, height: 11),
                  SizedBox(height: 14),
                  SpazaSkeletonLine(widthFactor: .58, height: 28),
                  SizedBox(height: 14),
                  SpazaSkeletonLine(widthFactor: .42, height: 11),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < 3; index++) ...[
            Container(
              key: const ValueKey('spaza-detail-skeleton-card'),
              height: 72,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: SpazaColors.surface,
                border: Border.all(color: SpazaColors.border),
                borderRadius: BorderRadius.circular(SpazaRadius.surface),
              ),
              child: const _SpazaShimmerMask(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SpazaSkeletonLine(widthFactor: .32, height: 10),
                    SizedBox(height: 9),
                    SpazaSkeletonLine(widthFactor: .68, height: 14),
                  ],
                ),
              ),
            ),
            if (index < 2) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}
