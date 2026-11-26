import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/app_state.dart';
import '../../core/config.dart';
import '../../core/realtime.dart';
import '../../core/theme.dart';
import 'help.dart';
import 'interests.dart';
import 'matches.dart';
import 'messages.dart';
import 'my_profile.dart';

/// Member home: four tabs like the web nav, badges for new interests and unread messages,
/// and the floating help button on every tab.
class MemberShell extends StatefulWidget {
  const MemberShell({super.key});
  @override
  State<MemberShell> createState() => _MemberShellState();
}

class _MemberShellState extends State<MemberShell> with WidgetsBindingObserver {
  int tab = 0;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    appState.refreshCounts();
    refreshSupport();
    _sub = Realtime.instance.events.listen((e) {
      if (e['type'] == 'support') {
        refreshSupport();
      } else {
        appState.refreshCounts();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      appState.refreshCounts();
      refreshSupport();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }

  Widget _badge(IconData icon, int n) => Badge(isLabelVisible: n > 0, label: Text('$n'), backgroundColor: C.brand600, child: Icon(icon));

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          final received = (appState.counts['received_pending'] as int?) ?? 0;
          final unread = (appState.counts['unread_messages'] as int?) ?? 0;
          return Scaffold(
            appBar: AppBar(
              titleSpacing: 16,
              title: Row(children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(gradient: C.buttonGradient, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Flexible(child: Text(Config.appName, style: display(19), overflow: TextOverflow.ellipsis)),
              ]),
            ),
            body: IndexedStack(index: tab, children: const [MatchesTab(), InterestsTab(), MessagesTab(), MyProfileTab()]),
            floatingActionButton: const HelpFab(),
            bottomNavigationBar: NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (i) {
                setState(() => tab = i);
                appState.refreshCounts();
              },
              destinations: [
                const NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome_rounded), label: 'Matches'),
                NavigationDestination(icon: _badge(Icons.favorite_border_rounded, received), selectedIcon: _badge(Icons.favorite_rounded, received), label: 'Interests'),
                NavigationDestination(icon: _badge(Icons.chat_bubble_outline_rounded, unread), selectedIcon: _badge(Icons.chat_bubble_rounded, unread), label: 'Messages'),
                const NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Profile'),
              ],
            ),
          );
        },
      );
}
