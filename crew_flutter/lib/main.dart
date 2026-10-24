import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'models.dart';

const navy = Color(0xFF12213D);
const red = Color(0xFFE5103A);
const background = Color(0xFFF5F7FA);
const border = Color(0xFFE3E8EF);

void main() => runApp(const HushitCrewApp());

class HushitCrewApp extends StatelessWidget {
  const HushitCrewApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Hushit Crew',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.fromSeed(seedColor: red),
      fontFamily: 'Arial',
    ),
    home: const CrewDashboard(),
  );
}

class CrewDashboard extends StatefulWidget {
  const CrewDashboard({super.key});
  @override
  State<CrewDashboard> createState() => _CrewDashboardState();
}

class _CrewDashboardState extends State<CrewDashboard> {
  CrewApi api = CrewApi('http://127.0.0.1:8001');
  List<CrewRequest> requests = [];
  String filter = 'All';
  String? selectedId;
  bool connected = false;
  bool loading = false;
  String? error;
  String flightNumber = 'JL 030';
  String flightStatus = 'In flight';
  StreamSubscription<Map<String, dynamic>>? events;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _connectToBackend('http://127.0.0.1:8001', 'CREW-DEMO'),
    );
  }

  CrewRequest? get selected =>
      requests.where((item) => item.id == selectedId).firstOrNull;
  List<CrewRequest> get visibleRequests => requests.where((item) {
    if (filter == 'New') return item.status == 'created';
    if (filter == 'In Progress') return item.status == 'in_progress';
    if (filter == 'Completed') return item.status == 'fulfilled';
    return true;
  }).toList();

  @override
  void dispose() {
    events?.cancel();
    api.dispose();
    super.dispose();
  }

  Future<void> connect() async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const ConnectDialog(),
    );
    if (result == null) return;
    await _connectToBackend(result.$1, result.$2);
  }

  Future<void> _connectToBackend(String baseUrl, String pairingCode) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      events?.cancel();
      api.dispose();
      api = CrewApi(baseUrl);
      final session = await api.pair(pairingCode);
      api.session = session;
      final sessionInfo = await api.fetchSession();
      final loaded = await api.fetchRequests();
      events = api.connectToEvents().listen(
        _handleEvent,
        onError: (_) =>
            _showError('Live updates disconnected; refresh to retry.'),
      );
      setState(() {
        requests = loaded;
        connected = true;
        loading = false;
        selectedId = loaded.firstOrNull?.id;
        flightNumber = sessionInfo['flight_number']?.toString() ?? flightNumber;
        flightStatus = sessionInfo['status']?.toString() ?? flightStatus;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = 'Backend unavailable. Start the communication backend, then tap Connect backend.';
      });
    }
  }

  void _handleEvent(Map<String, dynamic> event) {
    final payload =
        (event['payload'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final id = event['aggregate_id']?.toString();
    if (id == null) return;
    setState(() {
      if (event['event_type'] == 'request.created') {
        requests = [
          CrewRequest.fromJson(payload),
          ...requests.where((item) => item.id != id),
        ];
      } else if (event['event_type'] == 'request.status_changed') {
        requests = requests
            .map(
              (item) => item.id == id
                  ? item.copyWith(status: payload['status']?.toString())
                  : item,
            )
            .toList();
      }
    });
  }

  Future<void> changeStatus(String status) async {
    final request = selected;
    if (request == null) return;
    setState(
      () => requests = requests
          .map(
            (item) =>
                item.id == request.id ? item.copyWith(status: status) : item,
          )
          .toList(),
    );
    if (!connected) return;
    try {
      final updated = await api.updateStatus(request, status);
      setState(
        () => requests = requests
            .map((item) => item.id == updated.id ? updated : item)
            .toList(),
      );
    } catch (exception) {
      setState(
        () => requests = requests
            .map((item) => item.id == request.id ? request : item)
            .toList(),
      );
      _showError(exception.toString());
    }
  }

  void _showError(String message) {
    setState(() => error = message);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message), backgroundColor: navy));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            SideRail(newCount: requests.where((item) => item.isNew).length),
            Expanded(
              child: Column(
                children: [
                  TopBar(connected: connected, onConnect: connect),
                  Expanded(child: _body(constraints.maxWidth)),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _body(double width) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
    child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        _flightHeading(),
        const SizedBox(height: 16),
        _stats(),
        const SizedBox(height: 18),
        if (error != null) _errorBanner(),
        SizedBox(
          height: width > 1180 ? (requests.isEmpty ? 320 : 570) : 760,
          child: width > 1180 ? _wideContent() : _stackedContent(),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 210,
          child: width > 1180
              ? Row(
                  children: [
                    Expanded(child: SeatMap(requests: requests)),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 300,
                      child: QuickActions(onConnect: connect),
                    ),
                  ],
                )
              : SeatMap(requests: requests),
        ),
      ],
    ),
  );

  Widget _wideContent() => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        flex: 5,
        child: RequestList(
          requests: visibleRequests,
          selectedId: selectedId,
          filter: filter,
          onFilter: (value) => setState(() => filter = value),
          onSelect: (request) => setState(() => selectedId = request.id),
        ),
      ),
      const SizedBox(width: 14),
      Expanded(
        flex: 4,
        child: RequestDetails(request: selected, onStatus: changeStatus),
      ),
      const SizedBox(width: 14),
      Expanded(flex: 2, child: PassengerInfo(request: selected)),
    ],
  );

  Widget _stackedContent() => Column(
    children: [
      Expanded(
        child: RequestList(
          requests: visibleRequests,
          selectedId: selectedId,
          filter: filter,
          onFilter: (value) => setState(() => filter = value),
          onSelect: (request) => setState(() => selectedId = request.id),
        ),
      ),
      const SizedBox(height: 14),
      Expanded(
        child: RequestDetails(request: selected, onStatus: changeStatus),
      ),
    ],
  );

  Widget _flightHeading() => Wrap(
    spacing: 12,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: red.withValues(alpha: .1),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.flight_takeoff, color: red),
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            flightNumber,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: navy,
            ),
          ),
          Text(
            'Delhi (DEL)  →  Tokyo Haneda (HND)  •  $flightStatus',
            style: TextStyle(color: Colors.black54),
          ),
        ],
      ),
      if (loading)
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
    ],
  );

  Widget _stats() {
    final pending = requests.where((item) => item.status == 'created').length;
    final progress = requests
        .where((item) => item.status == 'in_progress')
        .length;
    final done = requests.where((item) => item.status == 'fulfilled').length;
    final urgent = requests.where((item) => item.isUrgent).length;
    return Row(
      children: [
        Expanded(
          child: StatCard(
            icon: Icons.chat_bubble_outline,
            value: '$pending',
            label: 'Pending Requests',
            color: red,
            onTap: () => setState(() => filter = 'New'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatCard(
            icon: Icons.schedule,
            value: '$progress',
            label: 'In Progress',
            color: const Color(0xFFE5A11B),
            onTap: () => setState(() => filter = 'In Progress'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatCard(
            icon: Icons.check_circle_outline,
            value: '$done',
            label: 'Completed Requests',
            color: const Color(0xFF16A56A),
            onTap: () => setState(() => filter = 'Completed'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatCard(
            icon: Icons.person_outline,
            value: '$urgent',
            label: 'Passengers Need Attention',
            color: const Color(0xFFD94C62),
            onTap: () => setState(() => filter = 'All'),
          ),
        ),
      ],
    );
  }

  Widget _errorBanner() => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF0F1),
      border: Border.all(color: const Color(0xFFFFCBD2)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline, color: red),
        const SizedBox(width: 8),
        Expanded(
          child: Text(error!, style: const TextStyle(color: navy)),
        ),
        IconButton(
          onPressed: () => setState(() => error = null),
          icon: const Icon(Icons.close),
        ),
      ],
    ),
  );
}

class SideRail extends StatelessWidget {
  const SideRail({super.key, required this.newCount});
  final int newCount;
  @override
  Widget build(BuildContext context) => Container(
    width: 220,
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(16, 20, 12, 16),
    child: SingleChildScrollView(
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 10, bottom: 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'HUSHIT',
                style: TextStyle(
                  color: red,
                  fontWeight: FontWeight.w900,
                  fontSize: 23,
                  letterSpacing: 1.3,
                ),
              ),
              Text(
                'Every language. One journey.',
                style: TextStyle(fontSize: 9, color: Colors.black54),
              ),
            ],
          ),
        ),
        _nav(Icons.home_outlined, 'Overview', true),
        _nav(Icons.chat_bubble_outline, 'Live Requests', false, badge: '$newCount'),
        _nav(Icons.forum_outlined, 'Conversations', false),
        _nav(Icons.airline_seat_recline_normal, 'Cabin Map', false),
        _nav(Icons.campaign_outlined, 'Announcements', false),
        _nav(Icons.person_outline, 'Passenger Preferences', false),
        _nav(Icons.verified_user_outlined, 'Exit-row Checks', false),
        _nav(Icons.nightlight_outlined, 'Quiet-seat Check-ins', false),
        _nav(Icons.bar_chart_outlined, 'System Status', false),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Row(
            children: [
              Icon(Icons.help_outline, size: 20, color: navy),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Need help?\nQuick guides and support',
                  style: TextStyle(fontSize: 11, color: navy),
                ),
              ),
            ],
          ),
        ),
        ],
      ),
    ),
  );

  Widget _nav(IconData icon, String label, bool active, {String? badge}) =>
      Container(
        margin: const EdgeInsets.only(bottom: 5),
        decoration: BoxDecoration(
          color: active ? red : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          leading: Icon(icon, size: 19, color: active ? Colors.white : navy),
          title: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? Colors.white : navy,
            ),
          ),
          trailing: badge == null
              ? null
              : Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: active ? Colors.white : red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      fontSize: 10,
                      color: active ? red : Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
        ),
      );
}

class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.connected, required this.onConnect});
  final bool connected;
  final VoidCallback onConnect;
  @override
  Widget build(BuildContext context) => Container(
    height: 75,
    padding: const EdgeInsets.symmetric(horizontal: 22),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: border)),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
        const ConnectionChip(
          icon: Icons.wifi,
          label: 'Aircraft Network',
          value: 'Connected',
          color: Color(0xFF16A56A),
        ),
        const SizedBox(width: 10),
        const ConnectionChip(
          icon: Icons.cloud_outlined,
          label: 'Internet',
          value: 'Limited',
          color: Color(0xFFE5A11B),
        ),
        const SizedBox(width: 10),
        const ConnectionChip(
          icon: Icons.devices_outlined,
          label: 'Connected Devices',
          value: '218 / 238',
          color: navy,
        ),
        const SizedBox(width: 20),
        Text(
          connected ? 'Live backend' : 'Not connected',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: connected ? const Color(0xFF16A56A) : Colors.black54,
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          onPressed: onConnect,
          icon: Icon(connected ? Icons.sync : Icons.link, size: 17),
          label: Text(connected ? 'Refresh connection' : 'Connect backend'),
          style: FilledButton.styleFrom(
            backgroundColor: red,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        const SizedBox(width: 12),
        const CircleAvatar(
          radius: 21,
          backgroundColor: Color(0xFFFFE3E7),
          child: Icon(Icons.person, color: red),
        ),
        const SizedBox(width: 8),
        const Text(
          'Cabin Crew\nA. Tanaka',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: navy,
          ),
        ),
          ],
        ),
      ),
    ),
  );
}

class ConnectionChip extends StatelessWidget {
  const ConnectionChip({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      border: Border.all(color: border),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 7),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 9, color: Colors.black54),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  color: color,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
              const SizedBox(height: 4),
              Text(
                'View all  →',
                style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });
  final String title;
  final String? trailing;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  color: navy,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const Spacer(),
            if (trailing != null)
              Flexible(
                child: Text(
                  trailing!,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontSize: 11,
                    color: red,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(child: child),
      ],
    ),
  );
}

class RequestList extends StatelessWidget {
  const RequestList({
    super.key,
    required this.requests,
    required this.selectedId,
    required this.filter,
    required this.onFilter,
    required this.onSelect,
  });
  final List<CrewRequest> requests;
  final String? selectedId;
  final String filter;
  final ValueChanged<String> onFilter;
  final ValueChanged<CrewRequest> onSelect;
  @override
  Widget build(BuildContext context) => Panel(
    title: 'Live Requests',
    trailing: '${requests.where((item) => item.isNew).length} new',
    child: Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: ['All', 'New', 'In Progress', 'Completed']
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(item),
                      selected: filter == item,
                      onSelected: (_) => onFilter(item),
                      selectedColor: const Color(0xFFFFE6EA),
                      labelStyle: TextStyle(
                        color: filter == item ? red : navy,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: requests.isEmpty
              ? const Center(child: Text('No requests in this view'))
              : ListView.separated(
                  itemCount: requests.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final request = requests[index];
                    return RequestRow(
                      request: request,
                      selected: request.id == selectedId,
                      onTap: () => onSelect(request),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}

class RequestRow extends StatelessWidget {
  const RequestRow({
    super.key,
    required this.request,
    required this.selected,
    required this.onTap,
  });
  final CrewRequest request;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFFFF4F5) : Colors.transparent,
        border: selected
            ? const Border(left: BorderSide(color: red, width: 3))
            : null,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
          SizedBox(
            width: 42,
            child: Text(
              request.seat,
              style: TextStyle(
                color: request.isUrgent ? red : navy,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          SizedBox(
            width: 120,
            child: Row(
              children: [
                Icon(_categoryIcon(request.category), size: 17, color: navy),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    request.category,
                    style: const TextStyle(fontSize: 12, color: navy),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 75,
            child: Text(
              request.passengerLanguage,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              _time(request.createdAt),
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ),
          SizedBox(width: 80, child: StatusPill(status: request.status)),
          SizedBox(
            width: 56,
            child: request.isUrgent
                ? const StatusPill(status: 'urgent')
                : const Text(
                    'Normal',
                    style: TextStyle(fontSize: 11, color: Colors.black54),
                  ),
          ),
          const Icon(Icons.chevron_right, size: 18, color: Colors.black38),
          ],
        ),
      ),
    ),
  );
}

class RequestDetails extends StatelessWidget {
  const RequestDetails({
    super.key,
    required this.request,
    required this.onStatus,
  });
  final CrewRequest? request;
  final Future<void> Function(String) onStatus;
  @override
  Widget build(BuildContext context) {
    final current = request;
    if (current == null) {
      return const Panel(
        title: 'Request Details',
        child: Center(child: Text('Select a request to view details')),
      );
    }
    return Panel(
      title: 'Request Details',
      trailing: '•••',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE7EA),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.airline_seat_recline_normal,
                  color: red,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Seat',
                    style: TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                  Text(
                    current.seat,
                    style: const TextStyle(
                      fontSize: 23,
                      color: navy,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              StatusPill(status: current.status),
            ],
          ),
          const Divider(height: 24),
          const Text(
            'Conversation',
            style: TextStyle(color: red, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          _bubble(
            Icons.person_outline,
            'Passenger (${current.passengerLanguage})',
            current.message ?? 'Assistance requested.',
            false,
          ),
          const SizedBox(height: 8),
          _bubble(
            Icons.translate,
            'Translated to Japanese',
            _translation(current.category),
            true,
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Text(
              'Suggested replies\nCertainly. I’ll bring that shortly.    Would you prefer water or juice?',
              style: TextStyle(fontSize: 11, color: navy, height: 1.5),
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: current.status == 'created'
                      ? () => onStatus('acknowledged')
                      : null,
                  icon: const Icon(Icons.check),
                  label: const Text('Acknowledge'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: red,
                    side: const BorderSide(color: red),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: current.status == 'acknowledged'
                      ? () => onStatus('in_progress')
                      : null,
                  icon: const Icon(Icons.schedule),
                  label: const Text('In Progress'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: red,
                    side: const BorderSide(color: red),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: current.status == 'in_progress'
                      ? () => onStatus('fulfilled')
                      : null,
                  icon: const Icon(Icons.check),
                  label: const Text('Complete'),
                  style: FilledButton.styleFrom(
                    backgroundColor: red,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bubble(IconData icon, String title, String text, bool translated) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: translated ? const Color(0xFFFFF0F2) : const Color(0xFFF6F8FB),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: translated ? red : navy, size: 19),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 10, color: Colors.black54),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    text,
                    style: const TextStyle(
                      fontSize: 13,
                      color: navy,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (translated)
                    const Text(
                      'Machine translated',
                      style: TextStyle(fontSize: 10, color: red),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
  String _translation(String category) =>
      category == 'Water' ? '水をお願いします。' : 'ご希望を確認しています。';
}

class PassengerInfo extends StatelessWidget {
  const PassengerInfo({super.key, this.request});
  final CrewRequest? request;
  @override
  Widget build(BuildContext context) => Panel(
    title: 'Passenger Information',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Center(
          child: CircleAvatar(
            radius: 28,
            backgroundColor: Color(0xFFFFE4E8),
            child: Icon(Icons.person, color: red, size: 30),
          ),
        ),
        const SizedBox(height: 12),
        InfoLine(
          icon: Icons.translate,
          label: 'Preferred Language',
          value: request?.passengerLanguage ?? '—',
        ),
        const InfoLine(
          icon: Icons.record_voice_over_outlined,
          label: 'Communication Method',
          value: 'Text and Voice',
        ),
        const InfoLine(
          icon: Icons.text_fields,
          label: 'Text Size',
          value: 'Large',
        ),
        const InfoLine(
          icon: Icons.volume_up_outlined,
          label: 'Read Messages Aloud',
          value: 'Enabled',
        ),
        const InfoLine(
          icon: Icons.wifi_off,
          label: 'Offline Language Kit',
          value: 'Ready',
          good: true,
        ),
        const Spacer(),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Greeting Coach',
                style: TextStyle(fontWeight: FontWeight.w800, color: navy),
              ),
              SizedBox(height: 4),
              Text(
                'Say hello in Tamil',
                style: TextStyle(fontSize: 10, color: Colors.black54),
              ),
              SizedBox(height: 8),
              Text(
                'வணக்கம்!',
                style: TextStyle(
                  fontSize: 17,
                  color: navy,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'Vanakkam!',
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class InfoLine extends StatelessWidget {
  const InfoLine({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.good = false,
  });
  final IconData icon;
  final String label;
  final String value;
  final bool good;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Icon(icon, size: 16, color: navy),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 10, color: Colors.black54),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 10,
            color: good ? const Color(0xFF16A56A) : navy,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class SeatMap extends StatelessWidget {
  const SeatMap({super.key, required this.requests});
  final List<CrewRequest> requests;
  @override
  Widget build(BuildContext context) => Panel(
    title: 'Cabin Seat Map',
    trailing: 'No request  •  Pending  •  In progress  •  Completed',
    child: Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        children: List.generate(36, (index) {
          final seat =
              '${(index ~/ 6) + 1}${String.fromCharCode(65 + (index % 6))}';
          final request = requests
              .where((item) => item.seat == seat)
              .firstOrNull;
          final color = request == null
              ? const Color(0xFFDDE2E8)
              : request.isUrgent
              ? red
              : request.status == 'fulfilled'
              ? const Color(0xFF46B682)
              : request.status == 'in_progress'
              ? const Color(0xFF65A9E8)
              : const Color(0xFFE5A11B);
          return Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Tooltip(
              message:
                  '$seat${request == null ? '' : ' • ${request.category}'}',
              child: const SizedBox(),
            ),
          );
        }),
      ),
    ),
  );
}

class QuickActions extends StatelessWidget {
  const QuickActions({super.key, required this.onConnect});
  final VoidCallback onConnect;
  @override
  Widget build(BuildContext context) => Panel(
    title: 'Quick Actions',
    child: Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        ActionButton(
          icon: Icons.campaign_outlined,
          label: 'Make Announcement',
          onTap: () {},
        ),
        ActionButton(
          icon: Icons.article_outlined,
          label: 'View Announcements',
          onTap: () {},
        ),
        ActionButton(
          icon: Icons.verified_user_outlined,
          label: 'Exit-row Checks',
          onTap: () {},
        ),
        ActionButton(
          icon: Icons.nightlight_outlined,
          label: 'Refresh Data',
          onTap: onConnect,
        ),
      ],
    ),
  );
}

class ActionButton extends StatelessWidget {
  const ActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: SizedBox(
      width: 115,
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF0F2),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: red),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10,
              color: navy,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final isUrgent = status == 'urgent';
    final color = isUrgent
        ? red
        : status == 'fulfilled'
        ? const Color(0xFF168C5A)
        : status == 'in_progress'
        ? const Color(0xFF1976D2)
        : const Color(0xFFB77600);
    final label = isUrgent
        ? 'High'
        : status == 'fulfilled'
        ? 'Completed'
        : status == 'in_progress'
        ? 'In Progress'
        : 'New';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          color: color,
          fontWeight: FontWeight.w800,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class ConnectDialog extends StatefulWidget {
  const ConnectDialog({super.key});
  @override
  State<ConnectDialog> createState() => _ConnectDialogState();
}

class _ConnectDialogState extends State<ConnectDialog> {
  final url = TextEditingController(text: 'http://127.0.0.1:8001');
  final code = TextEditingController(text: 'CREW-DEMO');
  @override
  void dispose() {
    url.dispose();
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Connect crew tablet'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: url,
          decoration: const InputDecoration(labelText: 'Aircraft backend URL'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: code,
          decoration: const InputDecoration(labelText: 'Crew pairing code'),
          obscureText: true,
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () =>
            Navigator.pop(context, (url.text.trim(), code.text.trim())),
        child: const Text('Connect'),
      ),
    ],
  );
}

String _time(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
IconData _categoryIcon(String category) =>
    category.toLowerCase().contains('water')
    ? Icons.local_drink_outlined
    : category.toLowerCase().contains('food')
    ? Icons.restaurant_outlined
    : category.toLowerCase().contains('blanket') ||
          category.toLowerCase().contains('pillow')
    ? Icons.bed_outlined
    : Icons.person_outline;
