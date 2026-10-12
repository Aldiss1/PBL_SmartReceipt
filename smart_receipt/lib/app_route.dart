import 'package:flutter/material.dart';

/// A [MaterialPageRoute] that appears instantly when pushed but keeps the
/// platform's animated transition when popped.
///
/// The push is made instant by giving the route a zero [transitionDuration].
/// The pop still animates because the underlying [AnimationController] keeps a
/// normal [AnimationController.reverseDuration], which is what the "back"
/// gesture and the revealed route's transition use.
class InstantPushPageRoute<T> extends MaterialPageRoute<T> {
  InstantPushPageRoute({required super.builder, super.settings});

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  AnimationController createAnimationController() {
    final AnimationController controller = super.createAnimationController();
    controller.reverseDuration = super.transitionDuration;
    return controller;
  }
}

/// Builds an app page route: instant when pushed, animated when popped.
Route<T> appRoute<T>(Widget page, {RouteSettings? settings}) =>
    InstantPushPageRoute<T>(
      settings: settings,
      builder: (BuildContext context) => page,
    );
