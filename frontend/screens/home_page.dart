// lib/ui/pages/home_page.dart
import 'package:flutter/material.dart';
import '../../services/api.dart';
import 'messages_page.dart';
import 'profile_detail_page.dart';

/// HomePage with bottom navigation.
/// By default it lands on Feed (MatchesFeedPage) and immediately
/// calls recommendMatches(). You can toggle between Feed and Messages.
class HomePage extends StatefulWidget {
  final ApiService apiService;
  final Map<String, dynamic>? currentUser;

  const HomePage({
    Key? key,
    required this.apiService,
    this.currentUser,
  }) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0; // 0 = Feed, 1 = Messages

  @override
  Widget build(BuildContext context) {
    final pages = [
      MatchesFeedPage(
        apiService: widget.apiService,
        currentUser: widget.currentUser,
      ),
      MessagesPage(apiService: widget.apiService),
    ];

    return Scaffold(
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() => _selectedIndex = index);
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: "Feed",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            label: "Messages",
          ),
        ],
      ),
    );
  }
}

/// MatchesFeedPage: fetches recommended profiles via ApiService.recommendMatches()
/// and lists them. Tapping a profile opens ProfileDetailPage.
class MatchesFeedPage extends StatefulWidget {
  final ApiService apiService;
  final Map<String, dynamic>? currentUser;

  const MatchesFeedPage({
    Key? key,
    required this.apiService,
    this.currentUser,
  }) : super(key: key);

  @override
  State<MatchesFeedPage> createState() => _MatchesFeedPageState();
}

class _MatchesFeedPageState extends State<MatchesFeedPage> {
  late Future<List<Map<String, dynamic>>> _futureMatches;

  @override
  void initState() {
    super.initState();
    _futureMatches = widget.apiService.recommendMatches(); // ✅ fetch on load
  }

  Future<void> _refresh() async {
    setState(() {
      _futureMatches = widget.apiService.recommendMatches();
    });
    await _futureMatches;
  }

  Widget _buildCard(Map<String, dynamic> profile) {
    final id = (profile['id'] ??
            profile['user_id'] ??
            profile['userId'] ??
            profile['id_str'] ??
            '')
        .toString();
    final name = (profile['user_name'] ??
            profile['name'] ??
            profile['full_name'] ??
            'Unknown')
        .toString();
    final image = profile['photo_url'] ?? profile['image'] ?? profile['avatar'];
    final subtitle =
        profile['headline'] ?? profile['bio'] ?? profile['location'] ?? '';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          if (id.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Invalid profile id')),
            );
            return;
          }

          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ProfileDetailPage(
                profileData: profile,
                currentUser: widget.currentUser ?? {},
              ),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image box: modest rectangular size, rounded corners
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
              child: Container(
                height: 140, // decently visible but not too large
                width: double.infinity,
                color: Theme.of(context).colorScheme.surfaceVariant,
                child: (image != null && image.toString().isNotEmpty)
                    ? Image.network(
                        image.toString(),
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: 140,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const Center(child: CircularProgressIndicator());
                        },
                        errorBuilder: (context, error, stackTrace) {
                          // fallback: show initial letter
                          return Center(
                            child: CircleAvatar(
                              radius: 28,
                              child: Text(
                                name.isNotEmpty ? name[0].toUpperCase() : '?',
                                style: const TextStyle(fontSize: 24),
                              ),
                            ),
                          );
                        },
                      )
                    : Center(
                        child: CircleAvatar(
                          radius: 28,
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                      ),
              ),
            ),

            // Name and subtitle area
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name
                  Text(
                    name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                  // Subtitle (if present)
                  if (subtitle.toString().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      subtitle.toString(),
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Feed'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _futureMatches,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 60),
                  Icon(Icons.error_outline,
                      color: Theme.of(context).colorScheme.error, size: 48),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Text(
                      'Failed to load matches:\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ),
                ],
              );
            } else {
              final items = snapshot.data ?? <Map<String, dynamic>>[];
              if (items.isEmpty) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 80),
                    Center(
                        child: Text('No matches found',
                            style: TextStyle(fontSize: 16))),
                  ],
                );
              }

              return ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 0),
                itemBuilder: (context, idx) => _buildCard(items[idx]),
              );
            }
          },
        ),
      ),
    );
  }
}
