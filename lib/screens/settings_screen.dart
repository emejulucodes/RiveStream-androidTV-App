import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/nav_mode.dart';
import '../widgets/tv_button.dart';

/// Settings/about: app version, remote-navigation mode, and clear cache.
///
/// Reachable from the exit-confirmation dialog (Back with no page history)
/// and from the offline screen. The WebView otherwise owns the whole D-pad
/// input surface, so there is nowhere to put a persistent settings control.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.navMode,
    required this.onNavModeChanged,
    required this.onClearSiteStorage,
    required this.adBlockEnabled,
    required this.onAdBlockChanged,
    required this.perfMode,
    required this.onPerfModeChanged,
  });

  final NavMode navMode;
  final ValueChanged<NavMode> onNavModeChanged;

  /// Drops the page's service worker and cache storage (see
  /// kResetSiteStorageScript); owned by HomeShell since it needs the
  /// WebView controller.
  final Future<void> Function() onClearSiteStorage;

  final bool adBlockEnabled;
  final ValueChanged<bool> onAdBlockChanged;

  final bool perfMode;
  final ValueChanged<bool> onPerfModeChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '';
  String _status = '';
  late NavMode _mode = widget.navMode;
  late bool _adBlock = widget.adBlockEnabled;
  late bool _perf = widget.perfMode;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() => _version = '${info.version} (${info.buildNumber})');
    });
  }

  Future<void> _clearCache() async {
    await InAppWebViewController.clearAllCache();
    // Also drop the site's service worker and cache storage: those survive
    // clearAllCache, and a wedged worker is what leaves the app on a blank
    // screen, so "clear cache" has to be able to fix it.
    await widget.onClearSiteStorage();
    if (!mounted) return;
    setState(() => _status = 'Cache cleared. Reopen the app to reload.');
  }

  void _toggleMode() {
    final next = _mode.toggled;
    setState(() {
      _mode = next;
      _status = '${next.label} mode enabled.';
    });
    widget.onNavModeChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14121A),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Settings',
                style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'RiveStream v$_version',
                style: const TextStyle(color: Colors.white54, fontSize: 16),
              ),
              const SizedBox(height: 32),
              const Text(
                'Remote navigation',
                style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                _mode.description,
                style: const TextStyle(color: Colors.white38, fontSize: 14),
              ),
              const SizedBox(height: 10),
              TvButton(
                autofocus: true,
                alignment: Alignment.centerLeft,
                icon: _mode == NavMode.cursor
                    ? Icons.mouse_rounded
                    : Icons.keyboard_tab_rounded,
                label: 'Mode: ${_mode.label}',
                onPressed: _toggleMode,
              ),
              const SizedBox(height: 24),
              const Text(
                'Performance mode',
                style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text(
                'Removes blur, shadows and animations so the TV keeps up',
                style: TextStyle(color: Colors.white38, fontSize: 14),
              ),
              const SizedBox(height: 10),
              TvButton(
                alignment: Alignment.centerLeft,
                icon: _perf ? Icons.speed_rounded : Icons.auto_awesome_rounded,
                label: 'Performance: ${_perf ? 'On' : 'Off'}',
                onPressed: () {
                  final next = !_perf;
                  setState(() {
                    _perf = next;
                    _status = next
                        ? 'Performance mode on. Reloading...'
                        : 'Full visuals restored. Reloading...';
                  });
                  widget.onPerfModeChanged(next);
                },
              ),
              const SizedBox(height: 24),
              const Text(
                'Ad blocker',
                style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text(
                'Turn off if a video will not load, then try again',
                style: TextStyle(color: Colors.white38, fontSize: 14),
              ),
              const SizedBox(height: 10),
              TvButton(
                alignment: Alignment.centerLeft,
                icon: _adBlock ? Icons.shield_rounded : Icons.shield_outlined,
                label: 'Ad blocker: ${_adBlock ? 'On' : 'Off'}',
                onPressed: () {
                  final next = !_adBlock;
                  setState(() {
                    _adBlock = next;
                    _status = next
                        ? 'Ad blocker on. Reloading...'
                        : 'Ad blocker off. Reloading...';
                  });
                  widget.onAdBlockChanged(next);
                },
              ),
              const SizedBox(height: 24),
              TvButton(
                alignment: Alignment.centerLeft,
                label: 'Clear cache',
                icon: Icons.cleaning_services_rounded,
                onPressed: _clearCache,
              ),
              const SizedBox(height: 12),
              TvButton(
                alignment: Alignment.centerLeft,
                label: 'Close',
                icon: Icons.arrow_back_rounded,
                onPressed: () => Navigator.of(context).pop(),
              ),
              if (_status.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(_status, style: const TextStyle(color: Color(0xFFFF2E92), fontSize: 15)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
