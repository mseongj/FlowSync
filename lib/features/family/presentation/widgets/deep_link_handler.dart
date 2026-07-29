import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:flow_sync/features/family/presentation/bloc/family_bloc.dart';

/// Listens for incoming `flowsync://invite?id=xxx` deep links and
/// automatically dispatches [FamilyInviteAccepted] to [FamilyBloc].
///
/// Wrap this around the app's root widget or place it as an invisible
/// child inside [MaterialApp.router].
class DeepLinkHandler extends StatefulWidget {
  final Widget child;

  const DeepLinkHandler({super.key, required this.child});

  @override
  State<DeepLinkHandler> createState() => _DeepLinkHandlerState();
}

class _DeepLinkHandlerState extends State<DeepLinkHandler> {
  late final AppLinks _appLinks;

  @override
  void initState() {
    super.initState();
    _appLinks = AppLinks();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    // Handle cold-start link (app was closed when link tapped)
    try {
      final initialLink = await _appLinks.getInitialLink();
      if (initialLink != null) {
        _handleUri(initialLink);
      }
    } catch (_) {}

    // Handle warm-start links (app already running)
    _appLinks.uriLinkStream.listen(
      _handleUri,
      onError: (_) {},
    );
  }

  void _handleUri(Uri uri) {
    if (!mounted) return;

    // Only handle flowsync://invite scheme
    if (uri.scheme != 'flowsync' || uri.host != 'invite') return;

    final inviteId = uri.queryParameters['id'];
    if (inviteId == null || inviteId.isEmpty) return;

    // If the user is not on the family screen, navigate there first
    context.go('/family');

    // Dispatch event to FamilyBloc
    context.read<FamilyBloc>().add(FamilyInviteAccepted(inviteId));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
