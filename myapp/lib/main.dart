import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/cupertino.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

const String devId = '3003470';
const String apiKey = '5c90697d-df1a-4a03-b8d6-b7c8cccad1e8';
const String baseUrl = 'timetableapi.ptv.vic.gov.au';

void main() => runApp(const PtvApp());

class PtvApp extends StatelessWidget {
  const PtvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const CupertinoApp(
      title: 'PTV Tracker',
      theme: CupertinoThemeData(
        brightness: Brightness.dark,
        primaryColor: CupertinoColors.systemBlue,
        scaffoldBackgroundColor: Color(0xFF0F1115),
      ),
      home: StopSearchPage(),
    );
  }
}

// ---------------- HELPERS & MODELS ----------------

Uri buildSignedUri(
  String path,
  Map<String, String> params, {
  Map<String, List<String>> repeatedParams = const {},
}) {
  final allParams = <String, String>{...params, 'devid': devId};
  final pairs = <MapEntry<String, String>>[
    ...allParams.entries,
    for (final entry in repeatedParams.entries)
      for (final value in entry.value) MapEntry(entry.key, value),
  ];
  final query = pairs.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
  final requestToSign = '$path?$query';
  final hmac = Hmac(sha1, utf8.encode(apiKey));
  final signature = hmac.convert(utf8.encode(requestToSign)).toString().toUpperCase();
  final fullQuery = '$query&signature=$signature';
  return Uri.parse('https://$baseUrl$path?$fullQuery');
}

class Stop {
  final int stopId;
  final String stopName;
  final int routeType;

  Stop({required this.stopId, required this.stopName, required this.routeType});

  factory Stop.fromJson(Map<String, dynamic> json) => Stop(
        stopId: json['stop_id'],
        stopName: json['stop_name'] ?? 'Unnamed stop',
        routeType: json['route_type'] ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Stop && runtimeType == other.runtimeType && stopId == other.stopId;

  @override
  int get hashCode => stopId.hashCode;
}

Widget getModeIcon(int routeType) {
  switch (routeType) {
    case 0:
      return const Icon(CupertinoIcons.train_style_one, color: CupertinoColors.activeBlue);
    case 1:
      return const Icon(CupertinoIcons.tram_fill, color: CupertinoColors.activeGreen);
    case 2:
      return const Icon(CupertinoIcons.bus, color: CupertinoColors.systemOrange);
    case 3:
      return const Icon(CupertinoIcons.bus, color: CupertinoColors.systemPurple);
    default:
      return const Icon(CupertinoIcons.location_solid, color: CupertinoColors.systemGrey);
  }
}

String getModeName(int routeType) {
  switch (routeType) {
    case 0: return 'Train';
    case 1: return 'Tram';
    case 2: return 'Bus';
    case 3: return 'V/Line';
    default: return 'Transport';
  }
}

// ---------------- HOME & SEARCH PAGE ----------------

class StopSearchPage extends StatefulWidget {
  const StopSearchPage({super.key});

  @override
  State<StopSearchPage> createState() => _StopSearchPageState();
}

class _StopSearchPageState extends State<StopSearchPage> {
  final TextEditingController _controller = TextEditingController();
  List<Stop> results = [];
  bool loading = false;
  String? error;
  bool _hasSearched = false;

  final Set<Stop> _favoriteStops = {};

  void _toggleFavorite(Stop stop) {
    setState(() {
      if (_favoriteStops.contains(stop)) {
        _favoriteStops.remove(stop);
      } else {
        _favoriteStops.add(stop);
      }
    });
  }

  Future<void> _search(String term) async {
    if (term.trim().isEmpty) return;
    setState(() {
      loading = true;
      error = null;
      _hasSearched = true;
    });

    try {
      final path = '/v3/search/${Uri.encodeComponent(term.trim())}';
      final uri = buildSignedUri(
        path,
        {'include_addresses': 'false', 'include_outlets': 'false'},
        repeatedParams: {'route_types': ['0', '1', '2', '3']},
      );
      final res = await http.get(uri);
      if (res.statusCode != 200) throw Exception('API error ${res.statusCode}');
      final data = jsonDecode(res.body);
      final List<dynamic> stopsJson = data['stops'] ?? [];
      setState(() {
        results = stopsJson.map((s) => Stop.fromJson(s)).toList();
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  void _clearSearch() {
    _controller.clear();
    setState(() {
      results.clear();
      _hasSearched = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFF0F1115),
      navigationBar: CupertinoNavigationBar(
        backgroundColor: const Color(0xFF161920).withOpacity(0.8),
        middle: const Text('PTV Tracker', style: TextStyle(color: CupertinoColors.white)),
        trailing: GestureDetector(
          onTap: () => Navigator.push(
            context,
            CupertinoPageRoute(
              builder: (_) => NearbyStopsPage(
                favorites: _favoriteStops,
                onToggleFavorite: _toggleFavorite,
              ),
            ),
          ),
          child: const Icon(CupertinoIcons.location_fill, color: CupertinoColors.activeBlue),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: CupertinoSearchTextField(
                controller: _controller,
                style: const TextStyle(color: CupertinoColors.white),
                placeholder: 'Search stations, stops, or lines...',
                placeholderStyle: const TextStyle(color: CupertinoColors.systemGrey),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C2029),
                  borderRadius: BorderRadius.circular(12),
                ),
                onSubmitted: _search,
                onSuffixTap: _clearSearch,
              ),
            ),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(20.0),
                child: CupertinoActivityIndicator(radius: 14),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text('Error: $error', style: const TextStyle(color: CupertinoColors.destructiveRed)),
              ),
            Expanded(
              child: _hasSearched ? _buildSearchResults() : _buildHomeDashboard(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeDashboard() {
    if (_favoriteStops.isEmpty) {
      return const Center(
        child: Text(
          'No saved favorites yet',
          style: TextStyle(color: CupertinoColors.systemGrey, fontSize: 14),
        ),
      );
    }

    final favList = _favoriteStops.toList();

    return ListView(
      physics: const BouncingScrollPhysics(),
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 16.0, top: 8.0, bottom: 8.0),
          child: Text(
            'Saved Favorites',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: CupertinoColors.white),
          ),
        ),
        ...favList.map((stop) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF161920),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: CupertinoColors.white.withOpacity(0.05)),
              ),
              child: CupertinoListTile(
                leading: getModeIcon(stop.routeType),
                title: Text(stop.stopName, style: const TextStyle(color: CupertinoColors.white, fontWeight: FontWeight.w600)),
                subtitle: Text(getModeName(stop.routeType), style: const TextStyle(color: CupertinoColors.systemGrey)),
                trailing: GestureDetector(
                  onTap: () => _toggleFavorite(stop),
                  child: const Icon(CupertinoIcons.heart_fill, color: CupertinoColors.systemRed),
                ),
                onTap: () => Navigator.push(
                  context,
                  CupertinoPageRoute(
                    builder: (_) => DeparturesPage(
                      stop: stop,
                      isFavorite: true,
                      onToggleFavorite: () => _toggleFavorite(stop),
                    ),
                  ),
                ),
              ),
            )),
      ],
    );
  }

  Widget _buildSearchResults() {
    if (results.isEmpty && !loading) {
      return const Center(
        child: Text('No stops found', style: TextStyle(color: CupertinoColors.systemGrey)),
      );
    }

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, i) {
        final stop = results[i];
        final isFav = _favoriteStops.contains(stop);
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF161920),
            borderRadius: BorderRadius.circular(14),
          ),
          child: CupertinoListTile(
            leading: getModeIcon(stop.routeType),
            title: Text(stop.stopName, style: const TextStyle(color: CupertinoColors.white)),
            subtitle: Text(getModeName(stop.routeType), style: const TextStyle(color: CupertinoColors.systemGrey)),
            trailing: GestureDetector(
              onTap: () => _toggleFavorite(stop),
              child: Icon(
                isFav ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
                color: isFav ? CupertinoColors.systemRed : CupertinoColors.systemGrey,
              ),
            ),
            onTap: () => Navigator.push(
              context,
              CupertinoPageRoute(
                builder: (_) => DeparturesPage(
                  stop: stop,
                  isFavorite: isFav,
                  onToggleFavorite: () => _toggleFavorite(stop),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------- NEARBY STOPS PAGE ----------------

class NearbyStopsPage extends StatefulWidget {
  final Set<Stop> favorites;
  final Function(Stop) onToggleFavorite;

  const NearbyStopsPage({
    super.key,
    required this.favorites,
    required this.onToggleFavorite,
  });

  @override
  State<NearbyStopsPage> createState() => _NearbyStopsPageState();
}

class _NearbyStopsPageState extends State<NearbyStopsPage> {
  List<Stop> stops = [];
  bool loading = true;
  String? error;

  Future<void> _loadNearby() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Location services are off');
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permission denied');
        }
      }
      final pos = await Geolocator.getCurrentPosition();
      final path = '/v3/stops/location/${pos.latitude},${pos.longitude}';
      final uri = buildSignedUri(
        path,
        {'max_distance': '1000', 'max_results': '20'},
        repeatedParams: {'route_types': ['0', '1', '2', '3']},
      );
      final res = await http.get(uri);
      if (res.statusCode != 200) throw Exception('API error ${res.statusCode}');
      final data = jsonDecode(res.body);
      final List<dynamic> stopsJson = data['stops'] ?? [];
      setState(() {
        stops = stopsJson.map((s) => Stop.fromJson(s)).toList();
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadNearby();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFF0F1115),
      navigationBar: const CupertinoNavigationBar(
        backgroundColor: Color(0xFF161920),
        middle: Text('Nearby Stops', style: TextStyle(color: CupertinoColors.white)),
      ),
      child: SafeArea(
        child: loading
            ? const Center(child: CupertinoActivityIndicator(radius: 14))
            : error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text('Error: $error', textAlign: TextAlign.center, style: const TextStyle(color: CupertinoColors.destructiveRed)),
                    ),
                  )
                : CustomScrollView(
                    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                    slivers: [
                      CupertinoSliverRefreshControl(onRefresh: _loadNearby),
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            final stop = stops[i];
                            final isFav = widget.favorites.contains(stop);
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF161920),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: CupertinoListTile(
                                leading: getModeIcon(stop.routeType),
                                title: Text(stop.stopName, style: const TextStyle(color: CupertinoColors.white)),
                                subtitle: Text(getModeName(stop.routeType), style: const TextStyle(color: CupertinoColors.systemGrey)),
                                trailing: GestureDetector(
                                  onTap: () {
                                    widget.onToggleFavorite(stop);
                                    setState(() {});
                                  },
                                  child: Icon(
                                    isFav ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
                                    color: isFav ? CupertinoColors.systemRed : CupertinoColors.systemGrey,
                                  ),
                                ),
                                onTap: () => Navigator.push(
                                  context,
                                  CupertinoPageRoute(
                                    builder: (_) => DeparturesPage(
                                      stop: stop,
                                      isFavorite: isFav,
                                      onToggleFavorite: () {
                                        widget.onToggleFavorite(stop);
                                        setState(() {});
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                          childCount: stops.length,
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

// ---------------- DEPARTURES PAGE ----------------

class DeparturesPage extends StatefulWidget {
  final Stop stop;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;

  const DeparturesPage({
    super.key,
    required this.stop,
    required this.isFavorite,
    required this.onToggleFavorite,
  });

  @override
  State<DeparturesPage> createState() => _DeparturesPageState();
}

class _DeparturesPageState extends State<DeparturesPage> {
  List<dynamic> departures = [];
  Map<String, dynamic> directions = {};
  Map<String, dynamic> routes = {};
  List<dynamic> disruptions = [];
  Set<String> stopRouteNames = {};
  bool loading = true;
  String? error;
  Timer? _timer;
  late bool _isFav;

  Future<void> _loadDepartures() async {
    try {
      final stopPath = '/v3/stops/${widget.stop.stopId}/route_type/${widget.stop.routeType}';
      final stopUri = buildSignedUri(stopPath, {'stop_disruptions': 'false'});
      final stopRes = await http.get(stopUri);

      Set<String> validRouteIds = {};
      final Set<String> lineNames = {};
      
      if (stopRes.statusCode == 200) {
        final stopData = jsonDecode(stopRes.body);
        final rawStopRoutes = stopData['stop']?['routes'];
        if (rawStopRoutes is List) {
          for (var r in rawStopRoutes) {
            if (r['route_id'] != null) {
              validRouteIds.add(r['route_id'].toString());
            }
            if (r['route_name'] != null && (r['route_name'] as String).isNotEmpty) {
              lineNames.add(r['route_name'].toString());
            }
          }
        }
      }

      final path = '/v3/departures/route_type/${widget.stop.routeType}/stop/${widget.stop.stopId}';
      final uri = buildSignedUri(path, {
        'max_results': '40',
        'expand': 'All',
      });

      final res = await http.get(uri);
      if (res.statusCode != 200) throw Exception('API error ${res.statusCode}');
      final data = jsonDecode(res.body);

      Map<String, dynamic> fetchedDirections = {};
      for (var rId in validRouteIds) {
        final dirPath = '/v3/directions/route/$rId';
        final dirUri = buildSignedUri(dirPath, {});
        final dirRes = await http.get(dirUri);
        if (dirRes.statusCode == 200) {
          final dirData = jsonDecode(dirRes.body);
          final dirList = dirData['directions'];
          if (dirList is List) {
            for (var d in dirList) {
              fetchedDirections[d['direction_id'].toString()] = d;
            }
          }
        }
      }

      final disPath = '/v3/disruptions/stop/${widget.stop.stopId}';
      final disUri = buildSignedUri(disPath, {});
      final disRes = await http.get(disUri);
      List<dynamic> loadedDisruptions = [];
      if (disRes.statusCode == 200) {
        final disData = jsonDecode(disRes.body);
        final rawDis = disData['disruptions'];
        if (rawDis is Map<String, dynamic>) {
          rawDis.forEach((key, list) {
            if (list is List) loadedDisruptions.addAll(list);
          });
        }
      }

      if (mounted) {
        setState(() {
          final rawDepartures = data['departures'] as List<dynamic>? ?? [];
          if (validRouteIds.isNotEmpty) {
            departures = rawDepartures.where((dep) {
              final rId = dep['route_id']?.toString();
              return rId != null && validRouteIds.contains(rId);
            }).toList();
          } else {
            departures = rawDepartures;
          }

          disruptions = loadedDisruptions;
          directions = fetchedDirections;

          final rawRoutes = data['routes'];
          Map<String, dynamic> parsedRoutes = {};
          if (rawRoutes is Map<String, dynamic>) {
            parsedRoutes = rawRoutes;
          } else if (rawRoutes is List) {
            parsedRoutes = {for (var r in rawRoutes) r['route_id'].toString(): r};
          }
          routes = parsedRoutes;

          stopRouteNames = lineNames;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _isFav = widget.isFavorite;
    _loadDepartures();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _loadDepartures());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Map<String, List<dynamic>> _groupDeparturesByDirection() {
    final Map<String, List<dynamic>> grouped = {};

    for (var dep in departures) {
      final dirId = dep['direction_id']?.toString() ?? 'unknown';
      grouped.putIfAbsent(dirId, () => []).add(dep);
    }

    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final groupedDepartures = _groupDeparturesByDirection();

    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFF0F1115),
      navigationBar: CupertinoNavigationBar(
        backgroundColor: const Color(0xFF161920).withOpacity(0.8),
        middle: const Text('Departures', style: TextStyle(color: CupertinoColors.white)),
        trailing: GestureDetector(
          onTap: () {
            setState(() {
              _isFav = !_isFav;
            });
            widget.onToggleFavorite();
          },
          child: Icon(
            _isFav ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
            color: _isFav ? CupertinoColors.systemRed : CupertinoColors.systemGrey,
          ),
        ),
      ),
      child: SafeArea(
        child: loading
            ? const Center(child: CupertinoActivityIndicator(radius: 14))
            : CustomScrollView(
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                slivers: [
                  CupertinoSliverRefreshControl(onRefresh: _loadDepartures),
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 4),
                          child: Text(
                            widget.stop.stopName,
                            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: CupertinoColors.white),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              ...stopRouteNames.map((line) => _buildLineBadge(line)),
                              if (stopRouteNames.isEmpty) _buildLineBadge(getModeName(widget.stop.routeType)),
                              const SizedBox(width: 4),
                              Text(
                                '${disruptions.length} disruptions',
                                style: const TextStyle(color: CupertinoColors.systemGrey, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        if (disruptions.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.all(16),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6B1115),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFFF3B30).withOpacity(0.4)),
                            ),
                            child: Row(
                              children: [
                                const Icon(CupertinoIcons.exclamationmark_triangle_fill, color: Color(0xFFFF453A), size: 24),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    disruptions.first['title'] ?? 'Service disruptions reported',
                                    style: const TextStyle(color: CupertinoColors.white, fontSize: 13, fontWeight: FontWeight.w500),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),

                  if (groupedDepartures.isEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No upcoming services', style: TextStyle(color: CupertinoColors.systemGrey, fontSize: 14)),
                      ),
                    )
                  else
                    ...groupedDepartures.entries.expand((entry) {
                      final dirId = entry.key;
                      final list = entry.value.take(4).toList();

                      String directionName = 'Unknown Direction';
                      if (directions.containsKey(dirId)) {
                        directionName = directions[dirId]['direction_name'] ?? directionName;
                      }

                      return [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 16, top: 20, bottom: 8),
                            child: Row(
                              children: [
                                const Icon(CupertinoIcons.arrow_right_square_fill, color: CupertinoColors.activeBlue, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  directionName.toUpperCase(),
                                  style: const TextStyle(
                                    color: CupertinoColors.activeBlue,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, i) => _buildDepartureCard(list[i], directionName),
                            childCount: list.length,
                          ),
                        ),
                      ];
                    }),

                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
      ),
    );
  }

  Widget _buildDepartureCard(dynamic dep, String fallbackDirection) {
    final rawTime = dep['estimated_departure_utc'] ?? dep['scheduled_departure_utc'];
    final directionId = dep['direction_id']?.toString();
    final platform = dep['platform_number']?.toString();

    String destination = fallbackDirection;
    if (directionId != null && directions.containsKey(directionId)) {
      destination = directions[directionId]['direction_name'] ?? destination;
    }

    String minutesText = '--';
    String timeFormatted = '';
    bool isImminent = false;

    if (rawTime != null) {
      final utcTime = DateTime.parse(rawTime as String).toLocal();
      final diff = utcTime.difference(DateTime.now());
      final minutes = diff.inMinutes;

      final hour = utcTime.hour > 12 ? utcTime.hour - 12 : (utcTime.hour == 0 ? 12 : utcTime.hour);
      final minute = utcTime.minute.toString().padLeft(2, '0');
      final period = utcTime.hour >= 12 ? 'PM' : 'AM';
      timeFormatted = '$hour:$minute $period';

      if (minutes <= 0) {
        minutesText = 'Now';
        isImminent = true;
      } else {
        minutesText = '$minutes min';
        if (minutes <= 3) isImminent = true;
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161920),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CupertinoColors.white.withOpacity(0.04)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  destination,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: CupertinoColors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      platform != null && platform.isNotEmpty
                          ? 'Platform $platform'
                          : getModeName(widget.stop.routeType),
                      style: const TextStyle(color: CupertinoColors.systemGrey, fontSize: 13),
                    ),
                    if (timeFormatted.isNotEmpty) ...[
                      const Text(' • ', style: TextStyle(color: CupertinoColors.systemGrey, fontSize: 13)),
                      Text(
                        timeFormatted,
                        style: const TextStyle(color: CupertinoColors.systemGrey2, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isImminent ? const Color(0xFFFF3B30).withOpacity(0.2) : const Color(0xFF1C2029),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isImminent ? const Color(0xFFFF3B30).withOpacity(0.5) : CupertinoColors.white.withOpacity(0.05),
              ),
            ),
            child: Text(
              minutesText,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: isImminent ? const Color(0xFFFF453A) : const Color(0xFFFFCC00),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLineBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: CupertinoColors.activeBlue.withOpacity(0.2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: CupertinoColors.activeBlue.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: const TextStyle(color: CupertinoColors.activeBlue, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}