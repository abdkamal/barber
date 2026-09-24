import 'package:flutter/material.dart';
import 'package:saloni_api/saloni_api.dart' as api;
import 'package:saloni_ui/saloni_ui.dart' as ui;

import '../../models/salon_session.dart';
import '../../services/customer_api.dart';
import '../../services/notification_service.dart';
import '../../widgets/notification_warning_banner.dart';
import '../about_salon_screen.dart';
import '../account/account_screen.dart';
import '../booking/book_screen.dart';
import '../history/history_screen.dart';
import '../tracking/cancel_sheet.dart';
import '../tracking/change_time_screen.dart';
import '../tracking/track_screen.dart';

/// الحاوية الرئيسية بعد الدخول — شريط تنقّل سفلي بأربع تبويبات (design.md
/// §10، Main.dc.html `navCustomer`).
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.api,
    required this.salonCode,
    required this.salonName,
    required this.currency,
    required this.savedSalons,
    required this.isDark,
    this.notificationReadiness,
    this.fcmMessages,
    required this.onToggleTheme,
    required this.onSwitchSalon,
    required this.onAddSalon,
    required this.onRemoveSalon,
    required this.onLogout,
  });

  final CustomerApi api;
  final String salonCode;
  final String salonName;
  final String currency;
  final List<SalonSession> savedSalons;
  final bool isDark;
  final NotificationReadiness? notificationReadiness;
  final Stream<void>? fcmMessages;
  final VoidCallback onToggleTheme;
  final ValueChanged<String> onSwitchSalon;
  final VoidCallback onAddSalon;
  final ValueChanged<String> onRemoveSalon;
  final VoidCallback onLogout;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  int _bookingRefreshKey = 0;

  void _refreshBookingTab() => setState(() => _bookingRefreshKey++);

  @override
  Widget build(BuildContext context) {
    final pages = [
      Column(
        children: [
          if (widget.notificationReadiness != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: NotificationWarningBanner(readiness: widget.notificationReadiness),
            ),
          Expanded(
            child: _BookingOrTrackingTab(
              key: ValueKey(_bookingRefreshKey),
              api: widget.api,
              currency: widget.currency,
              fcmMessages: widget.fcmMessages,
              onBookingChanged: _refreshBookingTab,
            ),
          ),
        ],
      ),
      AboutSalonScreen(api: widget.api, salonCode: widget.salonCode, showContinueCta: false),
      HistoryScreen(api: widget.api, currency: widget.currency),
      AccountScreen(
        activeCode: widget.salonCode,
        savedSalons: widget.savedSalons,
        isDark: widget.isDark,
        onToggleTheme: widget.onToggleTheme,
        onSwitchSalon: widget.onSwitchSalon,
        onAddSalon: widget.onAddSalon,
        onRemoveSalon: widget.onRemoveSalon,
        onLogout: widget.onLogout,
      ),
    ];

    return Scaffold(
      body: SafeArea(bottom: false, child: pages[_tab]),
      bottomNavigationBar: ui.SaloniBottomNav(
        active: _tab,
        onTap: (i) => setState(() => _tab = i),
        items: const [
          ui.SaloniNavItem(icon: ui.SaloniIconName.calendarCheck, label: 'حجزي'),
          ui.SaloniNavItem(icon: ui.SaloniIconName.storefront, label: 'الصالون'),
          ui.SaloniNavItem(icon: ui.SaloniIconName.receipt, label: 'السجل'),
          ui.SaloniNavItem(icon: ui.SaloniIconName.user, label: 'حسابي'),
        ],
      ),
    );
  }
}

/// تبويب «حجزي»: يعرض المتابعة إن كان هناك حجز نشط، وإلا شاشة الحجز.
class _BookingOrTrackingTab extends StatefulWidget {
  const _BookingOrTrackingTab({
    super.key,
    required this.api,
    required this.currency,
    required this.fcmMessages,
    required this.onBookingChanged,
  });

  final CustomerApi api;
  final String currency;
  final Stream<void>? fcmMessages;
  final VoidCallback onBookingChanged;

  @override
  State<_BookingOrTrackingTab> createState() => _BookingOrTrackingTabState();
}

class _BookingOrTrackingTabState extends State<_BookingOrTrackingTab> {
  bool _loading = true;
  bool _hasActive = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      await widget.api.getCurrentBooking();
      if (mounted) {
        setState(() {
          _hasActive = true;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _hasActive = false;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (!_hasActive) {
      return BookScreen(
        api: widget.api,
        currency: widget.currency,
        onBooked: (booking) {
          widget.onBookingChanged();
          setState(() {
            _hasActive = true;
          });
        },
      );
    }
    return TrackScreen(
      api: widget.api,
      externalRefresh: widget.fcmMessages,
      onChangeTime: (current) async {
        final booking = await Navigator.of(context).push<api.Booking>(
          MaterialPageRoute(
            builder: (_) => ChangeTimeScreen(
              api: widget.api,
              current: current,
              onChanged: (b) => Navigator.of(context).pop(b),
            ),
          ),
        );
        if (booking != null) widget.onBookingChanged();
      },
      onCancel: (current) => showCancelSheet(
        context: context,
        api: widget.api,
        bookingId: current.booking.id,
        barberName: 'حلاقك',
        eta: current.eta,
        onCancelled: () {
          widget.onBookingChanged();
          setState(() => _hasActive = false);
        },
      ),
    );
  }
}
