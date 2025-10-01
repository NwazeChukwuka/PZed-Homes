import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:go_router/go_router.dart';
import 'package:pzed_homes/presentation/widgets/guest_auth_dialog.dart';
import 'package:pzed_homes/presentation/widgets/animated_wrapper.dart';
import 'package:pzed_homes/core/theme/responsive_helpers.dart';
import 'package:pzed_homes/presentation/screens/guest/available_rooms_screen.dart';

class GuestLandingPage extends StatefulWidget {
  const GuestLandingPage({super.key});

  @override
  State<GuestLandingPage> createState() => _GuestLandingPageState();
}

class _GuestLandingPageState extends State<GuestLandingPage> {
  DateTime? _checkInDate;
  DateTime? _checkOutDate;
  int _guestCount = 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.amber[600]!, Colors.amber[800]!],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.amber[700]!.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context, 
                    builder: (_) => const GuestAuthDialog(),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text('Login / Sign Up'),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // == 1. Hero Section with Booking Card ==
            AnimatedFadeIn(
              delay: const Duration(milliseconds: 100),
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
                price: 15000,
                imageUrls: [
                  'https://images.unsplash.com/photo-1631049307264-da0ec9d70304?w=800&q=80',
                  'https://images.unsplash.com/photo-1522771739844-6a9f6d5f14af?w=800&q=80',
                  'https://images.unsplash.com/photo-1590490360182-c33d57733427?w=800&q=80',
                ],
              ),
            ),
            AnimatedWrapper(
              index: 1,
              child: _buildRoomTypeShowcase(
                name: 'Classic Room',
                description: 'A touch of elegance with enhanced amenities and more space to relax and unwind.',
                price: 20000,
                imageUrls: [
                  'https://images.unsplash.com/photo-1618773928121-c32242e63f39?w=800&q=80',
                  'https://images.unsplash.com/photo-1582719478250-c89cae4dc85b?w=800&q=80',
                  'https://images.unsplash.com/photo-1571896349842-33c89424de2d?w=800&q=80',
                ],
              ),
            ),
            AnimatedWrapper(
              index: 2,
              child: _buildRoomTypeShowcase(
                name: 'Diplomatic Room',
                description: 'Spacious and refined, designed for the discerning traveler requiring extra comfort.',
                price: 25000,
                imageUrls: [
                  'https://images.unsplash.com/photo-1564013799919-ab600027ffc6?w=800&q=80',
                  'https://images.unsplash.com/photo-1578683010236-d716f9a3f461?w=800&q=80',
                  'https://images.unsplash.com/photo-1520637836862-4d197d17c60a?w=800&q=80',
                ],
              ),
            ),
            AnimatedWrapper(
              index: 3,
              child: _buildRoomTypeShowcase(
                name: 'Deluxe Room',
                description: 'A premium experience with superior furnishings and breathtaking views.',
                price: 30000,
                imageUrls: [
                  'https://images.unsplash.com/photo-1611892440504-42a792e24d32?w=800&q=80',
                  'https://images.unsplash.com/photo-1595576508898-0ad5c879a061?w=800&q=80',
                  'https://images.unsplash.com/photo-1586023492125-27b2c045efd7?w=800&q=80',
                ],
              ),
            ),
            AnimatedWrapper(
              index: 4,
              child: _buildRoomTypeShowcase(
                name: 'Executive Suite',
                description: 'The pinnacle of luxury, featuring a separate living area and exclusive amenities.',
                price: 50000,
                imageUrls: [
                  'https://images.unsplash.com/photo-1512918728675-ed5a9ecdebfd?w=800&q=80',
                  'https://images.unsplash.com/photo-1590381105924-c72589b9ef3f?w=800&q=80',
                  'https://images.unsplash.com/photo-1582719478250-c89cae4dc85b?w=800&q=80',
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
                imageUrl: 'https://images.unsplash.com/photo-1572116469696-31de0f17cc34?w=800&q=80',
              ),
            ),
            AnimatedWrapper(
              index: 1,
              child: _buildFacilityShowcase(
                name: 'Outside Bar',
                description: 'Enjoy refreshing beverages and cocktails in our beautiful outdoor setting.',
                imageUrl: 'https://images.unsplash.com/photo-1544148103-0773bf10d330?w=800&q=80',
              ),
            ),
            AnimatedWrapper(
              index: 2,
              child: _buildFacilityShowcase(
                name: 'Restaurant',
                description: 'Savor a wide range of local and continental dishes prepared by our expert chefs.',
                imageUrl: 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=800&q=80',
              ),
            ),

            // == 4. Footer ==
            AnimatedFadeIn(
              delay: const Duration(milliseconds: 1200),
              child: _buildFooter(context),
            ),
          ],
        ),
      ),
    );
  }

  // --- Helper Widgets for building the page sections ---

  Widget _buildHeroSection(BuildContext context) {
    final heroHeight = ResponsiveHelper.getResponsiveValue(
      context,
      mobile: 600.0,
      tablet: 650.0,
      desktop: 700.0,
    );

    return Container(
      height: heroHeight,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background Image
          CachedNetworkImage(
            imageUrl: 'https://images.unsplash.com/photo-1566073771259-6a8506099945?w=1200&q=80',
            fit: BoxFit.cover,
            placeholder: (context, url) => Shimmer.fromColors(
              baseColor: Colors.grey.shade300,
              highlightColor: Colors.grey.shade100,
              child: Container(color: Colors.grey.shade300),
            ),
            errorWidget: (context, url, error) => Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green[300]!, Colors.green[600]!],
                ),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/PZED logo.png',
                    height: 80,
                    width: 80,
                    fit: BoxFit.contain,
                    color: Colors.white.withOpacity(0.7),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'P-ZED Luxury Hotels',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
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

          // Content
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Welcome Text
                Text(
                  'Welcome to P-ZED Homes',
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
                const SizedBox(height: 40),
                
                // Booking Card - Responsive width
                Container(
                  width: ResponsiveHelper.getResponsiveValue(
                    context,
                    mobile: double.infinity,
                    tablet: 450,
                    desktop: 500,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 25,
                        offset: const Offset(0, 10),
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: _buildBookingCardContent(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookingCardContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.search, color: Colors.green[700], size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'Check Availability',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        
        // Date Picker Fields
        _buildDateField('Check-in Date', Icons.calendar_today, _checkInDate, (date) {
          setState(() => _checkInDate = date);
        }),
        const SizedBox(height: 14),
        _buildDateField('Check-out Date', Icons.calendar_today, _checkOutDate, (date) {
          setState(() => _checkOutDate = date);
        }),
        const SizedBox(height: 14),
        
        // Guest Selector
        _buildGuestSelector(),
        const SizedBox(height: 24),
        
        // Search Button
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _checkInDate != null && _checkOutDate != null 
                ? [Colors.amber[600]!, Colors.amber[800]!]
                : [Colors.grey[400]!, Colors.grey[500]!],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: _checkInDate != null && _checkOutDate != null ? [
              BoxShadow(
                color: Colors.amber[700]!.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ] : [],
          ),
          child: ElevatedButton(
            onPressed: _checkInDate != null && _checkOutDate != null ? _showAvailableRooms : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Check Availability',
              style: TextStyle(
                fontSize: 16, 
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateField(String label, IconData icon, DateTime? selectedDate, Function(DateTime?) onDateSelected) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey[50],
      ),
      child: TextFormField(
        readOnly: true,
        controller: TextEditingController(
          text: selectedDate != null 
              ? '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}'
              : '',
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.grey[600]),
          prefixIcon: Icon(icon, color: Colors.green[600], size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(16),
          suffixIcon: IconButton(
            icon: Icon(Icons.calendar_month, color: Colors.green[600]),
            onPressed: () => _selectDate(context, onDateSelected),
          ),
        ),
        onTap: () => _selectDate(context, onDateSelected),
      ),
    );
  }

  Widget _buildGuestSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey[50],
      ),
      child: Row(
        children: [
          Icon(Icons.person, color: Colors.green[600], size: 20),
          const SizedBox(width: 12),
          const Text('Guests', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          const Spacer(),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove, size: 18),
                  onPressed: _guestCount > 1 ? () {
                    setState(() => _guestCount--);
                  } : null,
                  color: _guestCount > 1 ? Colors.green[600] : Colors.grey[400],
                ),
                Text('$_guestCount', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: _guestCount < 10 ? () {
                    setState(() => _guestCount++);
                  } : null,
                  color: _guestCount < 10 ? Colors.green[600] : Colors.grey[400],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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
                  return CachedNetworkImage(
                    imageUrl: imageUrls[index],
                    fit: BoxFit.cover,
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
                            '₦${price.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} / night', 
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
        children: [
          CachedNetworkImage(
            imageUrl: imageUrl,
            height: 250,
            width: double.infinity,
            fit: BoxFit.cover,
            placeholder: (context, url) => Shimmer.fromColors(
              baseColor: Colors.grey.shade300,
              highlightColor: Colors.grey.shade100,
              child: Container(height: 250, color: Colors.grey.shade300),
            ),
            errorWidget: (context, url, error) => Container(
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
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
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
                const SizedBox(height: 32),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Contact Us',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 12),
                          Text('+234 815 750 5978 ', style: TextStyle(color: Colors.white70)),
                          SizedBox(height: 4),
                          Text('info@pzedhotels.com', style: TextStyle(color: Colors.white70)),
                          SizedBox(height: 4),
                          Text('Unity FM Junction, off Nwiboko Enigwe Street, Amike-Aba, Abakaliki', style: TextStyle(color: Colors.white70)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Quick Links',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 12),
                          InkWell(
                            onTap: () => context.push('/guest/about'),
                            child: Text('About Us', style: TextStyle(color: Colors.white70)),
                          ),
                          SizedBox(height: 6),
                          InkWell(
                            onTap: () => context.push('/guest/services'),
                            child: Text('Services', style: TextStyle(color: Colors.white70)),
                          ),
                          SizedBox(height: 6),
                          InkWell(
                            onTap: () => context.push('/guest/contact'),
                            child: Text('Contact', style: TextStyle(color: Colors.white70)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
            ),
            child: const Text(
              '© 2025 P-ZED Luxury Hotels & Suites. All rights reserved.',
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
    if (_checkInDate != null && _checkOutDate != null) {
      context.push('/guest/rooms', extra: {
        'checkInDate': _checkInDate!,
        'checkOutDate': _checkOutDate!,
      });
    }
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
          _showAvailableRooms();
        },
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
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
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
                  children: [
                    // Description
                    Text(
                      widget.description,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                        height: 1.5,
                      ),
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
                    
                    const Spacer(),
                    
                    // Price and Book button
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Starts from',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                              Text(
                                '₦${widget.price.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} / night',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green[600],
                                ),
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