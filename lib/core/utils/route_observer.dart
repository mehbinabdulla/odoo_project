import 'package:flutter/material.dart';

// Global RouteObserver to track navigations
final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();

/// A mixin that makes it easy to refetch data when a screen comes back into focus
/// (e.g. when a pushed route is popped, revealing this screen again).
mixin RouteAwareRefetchMixin<T extends StatefulWidget> on State<T> implements RouteAware {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      // Unsubscribe first: didChangeDependencies can run multiple times for
      // the same State (e.g. when an InheritedWidget updates), and
      // subscribing twice throws.
      routeObserver.unsubscribe(this);
      routeObserver.subscribe(this, route as ModalRoute<void>);
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    // Called when the top route has been popped off, and the current route shows up.
    refetch();
  }

  @override
  void didPush() {}

  @override
  void didPop() {}

  @override
  void didPushNext() {}

  /// Override this method to implement the refetch logic
  void refetch();
}
