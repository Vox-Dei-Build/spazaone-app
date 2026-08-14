import 'package:flutter/material.dart';

/// Phone landscape has desktop-like width but very little vertical room.
/// Shared workspaces use this signal to move chrome sideways and preserve the
/// content viewport. Tablets and ordinary portrait phones keep their normal
/// hierarchy.
bool usesCompactLandscapeLayout(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return size.width > size.height && size.height < 600;
}

/// Places the global app row and store controls beside each other when there
/// is enough landscape width. At narrow widths it safely retains the stacked
/// layout instead of squeezing either action cluster.
class ResponsiveWorkspaceHeaderLayout extends StatelessWidget {
  const ResponsiveWorkspaceHeaderLayout({
    super.key,
    required this.appHeader,
    required this.storeHeader,
  });

  final Widget appHeader;
  final Widget storeHeader;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide =
            usesCompactLandscapeLayout(context) && constraints.maxWidth >= 520;
        if (!sideBySide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              appHeader,
              const SizedBox(height: 8),
              storeHeader,
            ],
          );
        }

        return Row(
          key: const ValueKey('landscape-workspace-header'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 55, child: appHeader),
            const SizedBox(width: 8),
            Expanded(flex: 45, child: storeHeader),
          ],
        );
      },
    );
  }
}

/// Keeps the active sign-in flow above the fold on short phone landscapes.
/// Portrait keeps the familiar vertical hierarchy while landscape uses the
/// otherwise-wasted horizontal room for the brand.
class ResponsiveAuthLayout extends StatelessWidget {
  const ResponsiveAuthLayout({
    super.key,
    required this.branding,
    required this.form,
  });

  final Widget branding;
  final Widget form;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide =
            usesCompactLandscapeLayout(context) && constraints.maxWidth >= 520;
        if (!sideBySide) {
          return Column(
            children: [
              branding,
              const SizedBox(height: 32),
              form,
            ],
          );
        }

        return Row(
          key: const ValueKey('landscape-auth-layout'),
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: Center(child: branding)),
            const SizedBox(width: 32),
            Expanded(child: form),
          ],
        );
      },
    );
  }
}

/// A centered state that becomes scrollable when landscape, the keyboard, or
/// accessibility text leaves less height than its content requires.
class ScrollableCenteredContent extends StatelessWidget {
  const ScrollableCenteredContent({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
