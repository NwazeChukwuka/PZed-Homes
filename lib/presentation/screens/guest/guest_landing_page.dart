import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:pzed_homes/presentation/screens/guest/gallery_folder_screen.dart';
import 'package:shimmer/shimmer.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pzed_homes/presentation/widgets/guest_auth_dialog.dart';
import 'package:pzed_homes/presentation/widgets/animated_wrapper.dart';
import 'package:pzed_homes/core/theme/responsive_helpers.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/core/performance/optimization_helpers.dart';
import 'package:pzed_homes/presentation/screens/guest/available_rooms_screen.dart';
import 'package:pzed_homes/presentation/screens/guest/gallery_viewer_screen.dart';
import 'package:pzed_homes/data/models/gallery_item.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:pzed_homes/core/state/app_state.dart';
import 'package:pzed_homes/core/services/payment_service.dart';

class GuestLandingPage extends StatefulWidget {
  const GuestLandingPage({super.key});

  @override
  State<GuestLandingPage> createState() => _GuestLandingPageState();
}

class _GuestLandingPageState extends State<GuestLandingPage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  DateTime? _checkInDate;
  DateTime? _checkOutDate;
  final int _guestCount = 1;
  final Map<String, dynamic> _bookingData = {
    'checkIn': null,
    'checkOut': null,
    'adults': 1,
    'children': 0,
  };

  // Image paths - loaded from assets only
  List<String> _heroImages = [];
  Map<String, List<String>> _roomImages = {}; // roomType -> list of image URLs
  List<Map<String, dynamic>> _roomTypes = []; // Room types loaded from database
  bool _isLoadingRoomTypes = false;
  bool _hasPrecached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hasPrecached || !mounted) return;
    _hasPrecached = true;
    // Precache asynchronously - do NOT block UI
    WidgetsBinding.instance.addPostFrameCallback((_) => _precachePriorityImages());
  }

  /// Precaches Hero images + first Facility card only (priority above-the-fold content)
  Future<void> _precachePriorityImages() async {
    if (!mounted) return;
    final priorityPaths = [
      ..._heroImages,
      'assets/images/VIP Bar/VIP Bar 1.JPG', // First facility card user sees
    ];
    for (final path in priorityPaths) {
      if (!mounted) return;
      try {
        await precacheImage(AssetImage(path), context);
      } catch (e) {
        if (kDebugMode) debugPrint('DEBUG precache $path: $e');
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _loadRoomTypes();
    
    // Initialize with asset images IMMEDIATELY (synchronous)
    _heroImages = [
      'assets/images/Front View/Front View 1.JPG',
      'assets/images/Front View/Front View 2.JPG',
      'assets/images/Front View/Front View 3.jpg',
      'assets/images/Front View/Front View 4.jpg',
    ];
    
    _roomImages = {
      'Standard Room': [
        'assets/images/Standard Room/Standard 1.png',
        'assets/images/Standard Room/Standard 2.JPG',
        'assets/images/Standard Room/Standard 3.jpg',
      ],
      'Classic Room': [
        'assets/images/Classic Room/Classic 1.JPG',
        'assets/images/Classic Room/Classic 2.png',
        'assets/images/Classic Room/Classic 3.JPG',
      ],
      'Diplomatic Room': [
        'assets/images/Diplomatic Room/Diplomatic 1.png',
        'assets/images/Diplomatic Room/Diplomatic 2.JPG',
        'assets/images/Diplomatic Room/Diplomatic 3.jpg',
      ],
      'Deluxe Room': [
        'assets/images/Deluxe Room/Deluxe 1.JPG',
        'assets/images/Deluxe Room/Deluxe 2.JPG',
        'assets/images/Deluxe Room/Deluxe 3.png',
      ],
      'Executive Room': [ // Fixed: Use 'Executive Room' to match room type name
        'assets/images/Executive Room/Executive 1.png',
        'assets/images/Executive Room/Executive 2.png',
        'assets/images/Executive Room/Executive 3.jpg',
      ],
    };

  }

  /// Load room types from database to get accurate prices
  Future<void> _loadRoomTypes() async {
    setState(() => _isLoadingRoomTypes = true);
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('room_types')
          .select('type, price')
          .timeout(const Duration(seconds: 5));
      
      if (mounted) {
        setState(() {
          _roomTypes = List<Map<String, dynamic>>.from(response);
          _isLoadingRoomTypes = false;
        });
      }
    } catch (e, stack) {
      if (kDebugMode) debugPrint('DEBUG load room types: $e\n$stack');
      if (mounted) {
        setState(() => _isLoadingRoomTypes = false);
      }
    }
  }

  /// Get price for a room type from database, fallback to hardcoded if not found
  int _getRoomPrice(String roomTypeName) {
    try {
      final roomType = _roomTypes.firstWhere(
        (rt) => (rt['type'] as String?) == roomTypeName,
        orElse: () => <String, dynamic>{},
      );
      
      if (roomType.isNotEmpty) {
        final priceInKobo = roomType['price'] as int? ?? 0;
        return priceInKobo; // Keep in kobo
      }
    } catch (e, stack) {
      if (kDebugMode) debugPrint('DEBUG _getRoomPrice: $e\n$stack');
    }
    
    // Fallback to hardcoded prices if database query fails
    final fallbackPrices = {
      'Standard Room': PaymentService.nairaToKobo(20000.0),
      'Classic Room': PaymentService.nairaToKobo(25000.0),
      'Diplomatic Room': PaymentService.nairaToKobo(30000.0),
      'Deluxe Room': PaymentService.nairaToKobo(35000.0),
      'Executive Room': PaymentService.nairaToKobo(50000.0),
    };
    return fallbackPrices[roomTypeName] ?? 0;
  }

  /// Gallery items - loaded from assets only (no database)
  List<Map<String, dynamic>> _getGalleryItems() {
    return [
      {
        'media_url': 'assets/images/Front View/Front View 1.JPG',
        'title': 'Front View',
        'is_video': false,
      },
      {
        'media_url': 'assets/images/VIP Bar/VIP Bar 1.JPG',
        'title': 'VIP Bar',
        'is_video': false,
      },
      {
        'media_url': 'assets/images/Restaurant/Restaurant 1.jpg',
        'title': 'Restaurant',
        'is_video': false,
      },
      {
        'media_url': 'assets/images/Reception/Reception 1.JPG',
        'title': 'Reception',
        'is_video': false,
      },
      {
        'media_url': 'assets/images/Outside bar/Outside Bar 2.jpg',
        'title': 'Outside Bar',
        'is_video': false,
      },
    ];
  }
  
  // Navigate to a specific route
  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ErrorHandler.showWarningMessage(
        context,
        'Could not launch URL. Please check your device settings.',
      );
    }
  }

  Future<void> _openMaps() async {
    final url = Uri.encodeFull(
      'https://www.google.com/maps/search/?api=1&query=Unity+FM+Junction%2C+Amike-Aba%2C+Abakaliki',
    );
    await _launchUrl(url);
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final url = 'tel:$phoneNumber';
    await _launchUrl(url);
  }

  Future<void> _sendEmail(String email) async {
    final url = 'mailto:$email';
    await _launchUrl(url);
  }

  Future<void> _navigateTo(String route) async {
    if (!mounted) return;
    
    // Close the drawer if it's open
    if (Scaffold.maybeOf(context)?.isEndDrawerOpen ?? false) {
      Navigator.pop(context);
    }
    
    if (route.startsWith('/guest/')) {
      if (!mounted) return;
      context.push(route);
    } else if (route == 'gallery') {
      if (!mounted) return;
      
      // Navigate to the new folder-based gallery
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => GalleryFolderScreen(),
        ),
      );
    } else if (route == 'contact') {
      // Show contact options
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Contact Us'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                leading: const Icon(Icons.phone),
                title: const Text('+234 815 750 5978'),
                onTap: () => _makePhoneCall('+2348157505978'),
              ),
              ListTile(
                leading: const Icon(Icons.email),
                title: const Text('pzedglobal@gmail.com'),
                onTap: () => _sendEmail('pzedglobal@gmail.com'),
              ),
              const SizedBox(height: 16),
              const Text('Unity FM Junction, Amike-Aba, Abakaliki'),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _showContactForm(context);
                  },
                  icon: const Icon(Icons.message),
                  label: const Text('Send us a message'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } else if (route == 'directions') {
      // Show directions dialog with map option
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Directions to P-ZED Hotels'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Unity FM Junction, Amike-Aba, Abakaliki'),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _openMaps,
                  icon: const Icon(Icons.directions),
                  label: const Text('Open in Maps'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } else if (route == 'contact') {
      // Show contact dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Contact Us'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Phone: +234 815 750 5978'),
              const SizedBox(height: 8),
              const Text('Email: pzedglobal@gmail.com'),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  // Implement call functionality
                  // For example: _makePhoneCall('+2348157505978');
                },
                icon: const Icon(Icons.phone),
                label: const Text('Call Us'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  // Toggle theme mode
  void _toggleTheme() {
    if (mounted) {
      final appState = Provider.of<AppState>(context, listen: false);
      appState.toggleTheme();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      endDrawer: Drawer(
        width: 280,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: Colors.green[800],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber[700],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Image.asset(
                      'assets/images/PZED logo.png',
                      height: 40,
                      width: 40,
                      fit: BoxFit.contain,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'P-ZED Luxury Hotels & Suites',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            _buildDrawerItem(
              icon: Icons.info_outline,
              title: 'About Us',
              onTap: () => _navigateTo('/guest/about'),
            ),
            _buildDrawerItem(
              icon: Icons.room_service,
              title: 'Services',
              onTap: () => _navigateTo('/guest/services'),
            ),
            _buildDrawerItem(
              icon: Icons.contact_mail,
              title: 'Contact Us',
              onTap: () => _navigateTo('contact'),
            ),
            _buildDrawerItem(
              icon: Icons.directions,
              title: 'Directions',
              onTap: () => _navigateTo('directions'),
            ),
            _buildDrawerItem(
              icon: Icons.photo_library,
              title: 'Gallery',
              onTap: () => _navigateTo('gallery'),
            ),
            const Divider(),
            _buildDrawerItem(
              icon: Icons.login,
              title: 'Login / Sign Up',
              onTap: () {
                Navigator.pop(context);
                _showAuthDialog(context, isLogin: true);
              },
            ),
            Consumer<AppState>(
              builder: (context, appState, child) {
                return SwitchListTile(
                  title: const Text('Dark Mode'),
                  secondary: const Icon(Icons.dark_mode),
                  value: appState.isDarkMode,
                  onChanged: (bool value) {
                    _toggleTheme();
                  },
                );
              },
            ),
          ],
        ),
      ),
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.amber[700],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Image.asset(
                'assets/images/PZED logo.png',
                height: 18,
                width: 18,
                fit: BoxFit.contain,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            const Text('P-ZED Luxury Hotels & Suites'),
          ],
        ),
        backgroundColor: Colors.green[800],
        elevation: 0,
        actions: [
          // Hamburger Menu Button
          IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
        ],
      ),
      body: SingleChildScrollView(
                child: Column(
                  children: [
                    // == 1. Hero Section ==
                    AnimatedFadeIn(
                      delay: Duration.zero,
                      child: _buildHeroSection(context),
                    ),

                    // == 2. "Our Rooms & Suites" Section ==
                    AnimatedSlideIn(
                      delay: const Duration(milliseconds: 300),
                      child: _buildSectionHeader(context, 'Our Rooms & Suites'),
                    ),
                    AnimatedWrapper(
                      index: 0,
                      child: _buildRoomTypeShowcase(
                        name: 'Standard Room',
                        description: 'Comfortable, affordable, and equipped with all the essentials for a pleasant stay.',
                        price: _getRoomPrice('Standard Room'),
                        imageUrls: _roomImages['Standard Room'] ?? [
                          'assets/images/Standard Room/Standard 1.png',
                          'assets/images/Standard Room/Standard 2.JPG',
                          'assets/images/Standard Room/Standard 3.jpg',
                        ],
                      ),
                    ),
                    AnimatedWrapper(
                      index: 1,
                      child: _buildRoomTypeShowcase(
                        name: 'Classic Room',
                        description: 'A touch of elegance with enhanced amenities and more space to relax and unwind.',
                        price: _getRoomPrice('Classic Room'),
                        imageUrls: _roomImages['Classic Room'] ?? [
                          'assets/images/Classic Room/Classic 1.JPG',
                          'assets/images/Classic Room/Classic 2.png',
                          'assets/images/Classic Room/Classic 3.JPG',
                        ],
                      ),
                    ),
                    AnimatedWrapper(
                      index: 2,
                      child: _buildRoomTypeShowcase(
                        name: 'Diplomatic Room',
                        description: 'Spacious and refined, designed for the discerning traveler requiring extra comfort.',
                        price: _getRoomPrice('Diplomatic Room'),
                        imageUrls: _roomImages['Diplomatic Room'] ?? [
                          'assets/images/Diplomatic Room/Diplomatic 1.png',
                          'assets/images/Diplomatic Room/Diplomatic 2.JPG',
                          'assets/images/Diplomatic Room/Diplomatic 3.jpg',
                        ],
                      ),
                    ),
                    AnimatedWrapper(
                      index: 3,
                      child: _buildRoomTypeShowcase(
                        name: 'Deluxe Room',
                        description: 'A premium experience with superior furnishings and breathtaking views.',
                        price: _getRoomPrice('Deluxe Room'),
                        imageUrls: _roomImages['Deluxe Room'] ?? [
                          'assets/images/Deluxe Room/Deluxe 1.JPG',
                          'assets/images/Deluxe Room/Deluxe 2.JPG',
                          'assets/images/Deluxe Room/Deluxe 3.png',
                        ],
                      ),
                    ),
                    AnimatedWrapper(
                      index: 4,
                      child: _buildRoomTypeShowcase(
                        name: 'Executive Room',
                        description: 'A generously sized room crafted for refined comfort, combining elegant finishes with enhanced space, ideal for work, privacy, and relaxation.',
                        price: _getRoomPrice('Executive Room'),
                        imageUrls: _roomImages['Executive Room'] ?? [ // Fixed: Use 'Executive Room' not 'Executive Suite'
                          'assets/images/Executive Room/Executive 1.png',
                          'assets/images/Executive Room/Executive 2.png',
                          'assets/images/Executive Room/Executive 3.jpg',
                        ],
                      ),
                    ),

                    // == 3. "Our Facilities" Section ==
                    AnimatedSlideIn(
                      delay: const Duration(milliseconds: 800),
                      child: _buildSectionHeader(context, 'Our Facilities'),
                    ),
                    AnimatedWrapper(
                      index: 0,
                      child: _buildFacilityShowcase(
                        name: 'VIP Bar',
                        description: 'An exclusive lounge for premium drinks and a serene ambiance.',
                        imageUrl: 'assets/images/VIP Bar/VIP Bar 1.JPG',
                      ),
                    ),
                    AnimatedWrapper(
                      index: 1,
                      child: _buildFacilityShowcase(
                        name: 'Restaurant',
                        description: 'Savor a wide range of local and continental dishes prepared by our expert chefs.',
                        imageUrl: 'assets/images/Restaurant/Restaurant 1.jpg',
                      ),
                    ),
                    AnimatedWrapper(
                      index: 2,
                      child: _buildFacilityShowcase(
                        name: 'Reception',
                        description: 'Our welcoming reception area with professional staff ready to assist you 24/7.',
                        imageUrl: 'assets/images/Reception/Reception 1.JPG',
                      ),
                    ),
                    AnimatedWrapper(
                      index: 3,
                      child: _buildFacilityShowcase(
                        name: 'Outside Bar',
                        description: 'Savor a wide range of local and continental dishes prepared by our expert chefs.',
                        imageUrl: 'assets/images/Outside bar/Outside Bar 2.jpg',
                      ),
                    ),
                    
                    // == 4. "Hotel Gallery" Section ==
                    AnimatedSlideIn(
                      delay: const Duration(milliseconds: 1000),
                      child: _buildSectionHeader(context, 'Hotel Gallery'),
                    ),
                    AnimatedWrapper(
                      index: 0,
                      child: _buildGallerySection(context, _getGalleryItems()),
                    ),

                    // == 5. Footer ==
                    AnimatedFadeIn(
                      delay: const Duration(milliseconds: 1200),
                      child: _buildFooter(context),
                    ),
                  ],
                ),
      ),
    );
  }

  // --- GALLERY SECTION WIDGET ---
  Widget _buildGallerySection(BuildContext context, List<Map<String, dynamic>> items) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = GalleryItem(
            url: items[index]['media_url'] ?? '',
            title: items[index]['title'] ?? 'Image $index',
            isVideo: items[index]['is_video'] ?? false,
          );

          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => GalleryViewerScreen(
                    items: [item],
                    initialIndex: 0,
                  ),
                ),
              );
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Image with shimmer
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: item.isVideo
                      ? const Center(child: Icon(Icons.videocam, size: 48, color: Colors.white))
                      : item.url.startsWith('http')
                          ? CachedNetworkImage(
                              imageUrl: item.url,
                              fit: BoxFit.cover,
                              memCacheWidth: 800,
                              memCacheHeight: 600,
                              placeholder: (context, url) => Shimmer.fromColors(
                                baseColor: Colors.grey[300]!,
                                highlightColor: Colors.grey[100]!,
                                child: Container(color: Colors.white),
                              ),
                              errorWidget: (context, url, error) => const Icon(Icons.error),
                            )
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                final size = constraints.maxWidth.clamp(100.0, 400.0);
                                return OptimizationHelpers.buildAssetImage(
                                  assetPath: item.url,
                                  width: size,
                                  height: size,
                                  fit: BoxFit.cover,
                                  frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                                    if (frame == null) {
                                      return Shimmer.fromColors(
                                        baseColor: Colors.grey[300]!,
                                        highlightColor: Colors.grey[100]!,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.grey[300],
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                      );
                                    }
                                    return TweenAnimationBuilder<double>(
                                      tween: Tween(begin: 0, end: 1),
                                      duration: const Duration(milliseconds: 300),
                                      curve: Curves.easeOut,
                                      builder: (context, value, _) => Opacity(opacity: value, child: child),
                                      child: child,
                                    );
                                  },
                                  errorWidget: const Icon(Icons.error),
                                );
                              },
                            ),
                ),
                // Gradient overlay
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.7),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                // Title
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: Text(
                    item.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Video indicator
                if (item.isVideo)
                  const Positioned(
                    top: 8,
                    right: 8,
                    child: Icon(Icons.play_circle_fill, color: Colors.white, size: 24),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  // --- Helper Widgets for building the page sections ---

  // Auto-scrolling hero section with front view images
  Widget _buildHeroSection(BuildContext context) {
    return _HeroSectionWidget(heroImages: _heroImages);
  }

  // Removed booking card methods - no longer needed since booking card was removed from hero section

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Container(
      padding: ResponsiveHelper.getResponsivePadding(
        context,
        mobile: const EdgeInsets.fromLTRB(16, 40, 16, 24),
        tablet: const EdgeInsets.fromLTRB(24, 50, 24, 30),
        desktop: const EdgeInsets.fromLTRB(32, 60, 32, 40),
      ),
      child: Column(
        children: [
          Text(
            title, 
            style: TextStyle(
              fontSize: ResponsiveHelper.getResponsiveFontSize(
                context,
                mobile: 28,
                tablet: 32,
                desktop: 36,
              ),
              fontWeight: FontWeight.w800,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: ResponsiveHelper.getResponsiveValue(
              context,
              mobile: 50,
              tablet: 60,
              desktop: 70,
            ),
            height: 4,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.amber[600]!, Colors.amber[800]!],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomTypeShowcase({
    required String name,
    required String description,
    required int price,
    required List<String> imageUrls,
  }) {
    return AnimatedHover(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 15,
              offset: const Offset(0, 5),
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 220,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: PageView.builder(
                  itemCount: imageUrls.length,
                  itemBuilder: (context, index) {
                    final imagePath = imageUrls[index];
                    // Check if it's a network URL or local asset
                    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
                      return CachedNetworkImage(
                        imageUrl: imagePath,
                        fit: BoxFit.cover,
                        memCacheWidth: 800,
                        memCacheHeight: 600,
                        placeholder: (context, url) => Shimmer.fromColors(
                          baseColor: Colors.grey.shade300,
                          highlightColor: Colors.grey.shade100,
                          child: Container(color: Colors.grey.shade300),
                        ),
                        errorWidget: (context, url, error) => Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.green[200]!, Colors.green[400]!],
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset(
                                'assets/images/PZED logo.png',
                                height: 60,
                                width: 60,
                                fit: BoxFit.contain,
                                color: Colors.white.withOpacity(0.8),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                name,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    } else {
                      return Image.asset(
                        imagePath,
                        fit: BoxFit.cover,
                        cacheWidth: 800,
                        cacheHeight: 600,
                        gaplessPlayback: true,
                        errorBuilder: (context, error, stackTrace) {
                          if (kDebugMode) {
                            print('Failed to load room image: $imagePath');
                            print('Error: $error');
                          }
                          return Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.green[200]!, Colors.green[400]!],
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Image.asset(
                                  'assets/images/PZED logo.png',
                                  height: 60,
                                  width: 60,
                                  fit: BoxFit.contain,
                                  color: Colors.white.withOpacity(0.8),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  name,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.9),
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (kDebugMode)
                                  Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Text(
                                      'Failed: ${imagePath.split('/').last}',
                                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      );
                    }
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name, 
                          style: const TextStyle(
                            fontSize: 22, 
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          ...List.generate(5, (index) => Icon(
                            Icons.star,
                            size: 16,
                            color: Colors.amber[600],
                          )),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    description, 
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Starts from',
                              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                            ),
                            Text(
                              '${NumberFormat.currency(locale: 'en_NG', symbol: '₦').format(PaymentService.koboToNaira(price))} / night',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800, 
                                color: Colors.green, 
                                fontSize: 20,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.amber[600]!, Colors.amber[800]!],
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.amber[600]!.withOpacity(0.3),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: () {
                            _showRoomDetails(name, description, price, imageUrls);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'View Details',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFacilityShowcase({
    required String name,
    required String description,
    required String imageUrl,
  }) {
    return AnimatedHover(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 15,
              offset: const Offset(0, 5),
              spreadRadius: 1,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 250,
              width: double.infinity,
              child: OptimizationHelpers.buildAssetImage(
                assetPath: imageUrl,
                width: double.infinity,
                height: 250,
                fit: BoxFit.cover,
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                  if (frame == null) {
                    return Shimmer.fromColors(
                      baseColor: Colors.grey[300]!,
                      highlightColor: Colors.grey[100]!,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    );
                  }
                  return TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    builder: (context, value, _) => Opacity(opacity: value, child: child),
                    child: child,
                  );
                },
                errorWidget: Container(
                  height: 250,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.green[200]!, Colors.green[400]!],
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        name.toLowerCase().contains('bar') ? Icons.local_bar :
                        name.toLowerCase().contains('restaurant') ? Icons.restaurant : Icons.hotel,
                        color: Colors.white.withOpacity(0.8),
                        size: 60,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        name,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name, 
                    style: const TextStyle(
                      fontSize: 22, 
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    description, 
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                      height: 1.4,
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

  // Helper method to build drawer items
  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.grey[800]),
      title: Text(title, style: const TextStyle(fontSize: 16)),
      onTap: onTap,
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green[800]!, Colors.green[900]!],
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber[700],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Image.asset(
                        'assets/images/PZED logo.png',
                        height: 28,
                        width: 28,
                        fit: BoxFit.contain,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'P-ZED Luxury Hotels & Suites',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isMobile = ResponsiveHelper.isMobile(context);
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Text(
                                'Contact Us',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (isMobile)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    const Text('+234 815 750 5978', style: TextStyle(color: Colors.white70)),
                                    const SizedBox(height: 4),
                                    const Text('pzedglobal@gmail.com', style: TextStyle(color: Colors.white70)),
                                    const SizedBox(height: 4),
                                    const Text('Unity FM Junction, Amike-Aba, Abakaliki', style: TextStyle(color: Colors.white70)),
                                  ],
                                )
                              else
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Text('+234 815 750 5978', style: TextStyle(color: Colors.white70)),
                                        Text(' | ', style: TextStyle(color: Colors.white70.withOpacity(0.6))),
                                        const Text('pzedglobal@gmail.com', style: TextStyle(color: Colors.white70)),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    const Text('Unity FM Junction, Amike-Aba, Abakaliki', style: TextStyle(color: Colors.white70)),
                                  ],
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Text(
                                'Quick Links',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (isMobile)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    InkWell(
                                      onTap: () => context.push('/guest/about'),
                                      child: const Text('About Us', style: TextStyle(color: Colors.white70)),
                                    ),
                                    const SizedBox(height: 4),
                                    InkWell(
                                      onTap: () => context.push('/guest/services'),
                                      child: const Text('Services', style: TextStyle(color: Colors.white70)),
                                    ),
                                    const SizedBox(height: 4),
                                    InkWell(
                                      onTap: () => context.push('/guest/contact'),
                                      child: const Text('Contact', style: TextStyle(color: Colors.white70)),
                                    ),
                                  ],
                                )
                              else
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    InkWell(
                                      onTap: () => context.push('/guest/about'),
                                      child: const Text('About Us', style: TextStyle(color: Colors.white70)),
                                    ),
                                    Text(' | ', style: TextStyle(color: Colors.white70.withOpacity(0.6))),
                                    InkWell(
                                      onTap: () => context.push('/guest/services'),
                                      child: const Text('Services', style: TextStyle(color: Colors.white70)),
                                    ),
                                    Text(' | ', style: TextStyle(color: Colors.white70.withOpacity(0.6))),
                                    InkWell(
                                      onTap: () => context.push('/guest/contact'),
                                      child: const Text('Contact', style: TextStyle(color: Colors.white70)),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 32),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
            ),
            child: const Text(
              '© 2026 P-ZED Luxury Hotels & Suites. All rights reserved.',
              style: TextStyle(color: Colors.white60),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectDate(BuildContext context, Function(DateTime?) onDateSelected) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    
    if (picked != null) {
      onDateSelected(picked);
    }
  }

  void _showAvailableRooms() {
    if (_checkInDate == null || _checkOutDate == null) {
      if (mounted) {
        ErrorHandler.showWarningMessage(
          context,
          'Please select check-in and check-out dates',
        );
      }
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AvailableRoomsScreen(),
        settings: RouteSettings(
          arguments: {
            'checkInDate': _checkInDate!,
            'checkOutDate': _checkOutDate!,
          },
        ),
      ),
    );
  }
  
  void _showAuthDialog(BuildContext context, {required bool isLogin}) {
    showDialog(
      context: context,
      builder: (context) => const GuestAuthDialog(),
    ).then((_) {
      // This will be called when the dialog is closed
      // You can add any post-dialog logic here if needed
    });
  }

  void _showContactForm(BuildContext context) {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    final subjectController = TextEditingController();
    final messageController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Contact Us'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Name (Optional)
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Your Name (Optional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                
                // Email (Optional)
                TextFormField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email (Optional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value != null && value.isNotEmpty && !value.contains('@')) {
                      return 'Please enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                
                // Phone (Optional)
                TextFormField(
                  controller: phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Phone (Optional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                
                // Subject (Required)
                TextFormField(
                  controller: subjectController,
                  decoration: const InputDecoration(
                    labelText: 'Subject *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.subject_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a subject';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                
                // Message (Required)
                TextFormField(
                  controller: messageController,
                  decoration: const InputDecoration(
                    labelText: 'Your Message *',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 4,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your message';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                const Text(
                  '* Required fields',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                // Here you would typically send the message to your backend
                // For now, we'll just show a success message and close the dialog
                Navigator.pop(context);
                if (mounted) {
                  ErrorHandler.showSuccessMessage(
                    context,
                    'Your message has been sent successfully!',
                    duration: const Duration(seconds: 3),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[700],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('SEND MESSAGE'),
          ),
        ],
      ),
    );
  }

  void _showRoomDetails(String name, String description, int price, List<String> imageUrls) {
    showDialog(
      context: context,
      builder: (context) => _RoomDetailsDialog(
        name: name,
        description: description,
        price: price,
        imageUrls: imageUrls,
        onBookNow: () {
          context.pop();
          // Navigate directly to availability screen with room type info
          // Then user can select dates and proceed to booking
          context.push('/guest/rooms', extra: {
            'roomType': {
              'name': name,
              'price': price,
              'description': description,
            },
          });
        },
      ),
    );
  }
}

// Separate StatefulWidget for hero section to manage its own state
class _HeroSectionWidget extends StatefulWidget {
  final List<String> heroImages;

  const _HeroSectionWidget({required this.heroImages});

  @override
  State<_HeroSectionWidget> createState() => _HeroSectionWidgetState();
}

class _HeroSectionWidgetState extends State<_HeroSectionWidget> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  Timer? _timer;
  bool _isUserInteracting = false;

  @override
  void initState() {
    super.initState();
    _startAutoScroll();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  // Auto-scroll functionality (pauses when user interacts)
  void _startAutoScroll() {
    _timer = Timer.periodic(const Duration(seconds: 3), (timer) {
      // Don't auto-scroll if user is manually swiping
      if (_isUserInteracting) return;
      
      if (_currentPage < widget.heroImages.length - 1) {
        _currentPage++;
      } else {
        _currentPage = 0;
      }
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          _currentPage,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentPage = index;
    });
  }

  void _onUserInteraction() {
    // Pause auto-scroll when user starts swiping
    setState(() {
      _isUserInteracting = true;
    });
    // Resume auto-scroll after 5 seconds of no interaction
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _isUserInteracting = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final heroHeight = ResponsiveHelper.getResponsiveValue(
      context,
      mobile: 600.0,
      tablet: 650.0,
      desktop: 700.0,
    );

    return SizedBox(
      height: heroHeight,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // PageView for auto-scrolling images (allows manual swipe)
          GestureDetector(
            onPanStart: (_) => _onUserInteraction(),
            onPanUpdate: (_) => _onUserInteraction(),
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.heroImages.length,
              onPageChanged: _onPageChanged,
              allowImplicitScrolling: false,
              itemBuilder: (context, index) {
                final imagePath = widget.heroImages[index];
                final size = MediaQuery.sizeOf(context);
                final cacheW = (size.width * 2).round().clamp(1, OptimizationHelpers.maxCacheDimension);
                final cacheH = (size.height * 2).round().clamp(1, OptimizationHelpers.maxCacheDimension);
                return Image.asset(
                  imagePath,
                  fit: BoxFit.cover,
                  cacheWidth: cacheW,
                  cacheHeight: cacheH,
                  gaplessPlayback: true,
                  frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                    if (frame == null) {
                      return Shimmer.fromColors(
                        baseColor: Colors.grey[300]!,
                        highlightColor: Colors.grey[100]!,
                        child: Container(color: Colors.grey[300]),
                      );
                    }
                    return TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                      builder: (context, value, _) => Opacity(opacity: value, child: child),
                      child: child,
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    if (kDebugMode) {
                      print('Failed to load image: $imagePath');
                      print('Error: $error');
                    }
                    return Container(
                      color: Colors.grey[200],
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.broken_image, size: 50, color: Colors.grey),
                            if (kDebugMode)
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  'Failed: ${imagePath.split('/').last}',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          
          // Page indicator
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List<Widget>.generate(
                widget.heroImages.length,
                (index) => Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentPage == index ? Colors.white : Colors.white.withOpacity(0.5),
                  ),
                ),
              ),
            ),
          ),
          
          // Dark overlay for better text readability
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.3),
                  Colors.black.withOpacity(0.5),
                  Colors.black.withOpacity(0.7)
                ],
              ),
            ),
          ),

          // Content - Welcome text only (no booking card)
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Welcome Text
                Text(
                  'Welcome to P-ZED Luxury Hotels & Suites',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: ResponsiveHelper.getResponsiveFontSize(
                      context,
                      mobile: 34,
                      tablet: 38,
                      desktop: 42,
                    ),
                    fontWeight: FontWeight.w800, 
                    color: Colors.white, 
                    shadows: [
                      Shadow(
                        blurRadius: 15.0,
                        color: Colors.black.withOpacity(0.5),
                        offset: const Offset(0, 4),
                      )
                    ]
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Your Comfort is Our Priority',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: ResponsiveHelper.getResponsiveFontSize(
                      context,
                      mobile: 20,
                      tablet: 22,
                      desktop: 24,
                    ),
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.w400,
                    shadows: [
                      Shadow(
                        blurRadius: 10.0,
                        color: Colors.black.withOpacity(0.3),
                      )
                    ]
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomDetailsDialog extends StatefulWidget {
  final String name;
  final String description;
  final int price;
  final List<String> imageUrls;
  final VoidCallback onBookNow;

  const _RoomDetailsDialog({
    required this.name,
    required this.description,
    required this.price,
    required this.imageUrls,
    required this.onBookNow,
  });

  @override
  State<_RoomDetailsDialog> createState() => _RoomDetailsDialogState();
}

class _RoomDetailsDialogState extends State<_RoomDetailsDialog> {
  int _currentImageIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: SizedBox(
        width: MediaQuery.sizeOf(context).width * 0.9,
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: Column(
          children: [
            // Header with close button
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.name,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.close),
                    color: Colors.grey[600],
                  ),
                ],
              ),
            ),
            
            // Image carousel
            Expanded(
              flex: 3,
              child: Stack(
                children: [
                  PageView.builder(
                    onPageChanged: (index) {
                      setState(() => _currentImageIndex = index);
                    },
                    itemCount: widget.imageUrls.length,
                    itemBuilder: (context, index) {
                      return CachedNetworkImage(
                        imageUrl: widget.imageUrls[index],
                        fit: BoxFit.cover,
                        memCacheWidth: 800,
                        memCacheHeight: 600,
                        placeholder: (context, url) => Shimmer.fromColors(
                          baseColor: Colors.grey.shade300,
                          highlightColor: Colors.grey.shade100,
                          child: Container(color: Colors.grey.shade300),
                        ),
                        errorWidget: (context, url, error) => Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.green[200]!, Colors.green[400]!],
                            ),
                          ),
                          child: Image.asset(
                            'assets/images/PZED logo.png',
                            height: 60,
                            width: 60,
                            fit: BoxFit.contain,
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                      );
                    },
                  ),
                  
                  // Image indicators
                  if (widget.imageUrls.length > 1)
                    Positioned(
                      bottom: 16,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          widget.imageUrls.length,
                          (index) => Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _currentImageIndex == index
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.5),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            
            // Content
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Scrollable content (Description and Features)
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Description
                            Text(
                              widget.description,
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                                height: 1.5,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            
                            const SizedBox(height: 20),
                            
                            // Features
                            Text(
                              'Room Features:',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[800],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildFeatureChip('WiFi', Icons.wifi),
                                _buildFeatureChip('AC', Icons.ac_unit),
                                _buildFeatureChip('TV', Icons.tv),
                                _buildFeatureChip('Mini Bar', Icons.local_bar),
                                _buildFeatureChip('Room Service', Icons.room_service),
                                _buildFeatureChip('Safe', Icons.security),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Price and Book button (Fixed at bottom)
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Starts from',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                              Text(
                                '${NumberFormat.currency(locale: 'en_NG', symbol: '₦').format(PaymentService.koboToNaira(widget.price))} / night',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green[600],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton(
                          onPressed: widget.onBookNow,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green[600],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Book Now',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green[200]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.green[600]),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.green[700],
            ),
          ),
        ],
      ),
    );
  }
}