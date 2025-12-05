import 'package:flutter/material.dart';

class AboutUsScreen extends StatelessWidget {
  const AboutUsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About Us'),
        backgroundColor: Colors.green[800],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Hero Section
            _buildHeroSection(context),
            
            // Mission & Vision
            _buildMissionVision(context),
            
            // Our Story
            _buildOurStory(context),
            
            // Team Section
            _buildTeamSection(context),
            
            // Values
            _buildValuesSection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroSection(BuildContext context) {
    return Container(
      height: 300,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/Front View/Front View 1.JPG',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green[300]!, Colors.green[600]!],
                ),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.3),
                  Colors.black.withOpacity(0.7),
                ],
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'About P-ZED Luxury Hotels & Suites',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        blurRadius: 10.0,
                        color: Colors.black.withOpacity(0.5),
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Your Comfort is Our Priority',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.white.withOpacity(0.9),
                    shadows: [
                      Shadow(
                        blurRadius: 5.0,
                        color: Colors.black.withOpacity(0.3),
                      )
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMissionVision(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          _buildInfoCard(
            context,
            'Our Mission',
            'To craft unforgettable luxury experiences by consistently delivering the highest standards of comfort, sophistication, and genuinely personalized service that anticipates every guest need',
            Icons.flag,
            Colors.blue,
          ),
          const SizedBox(height: 20),
          _buildInfoCard(
            context,
            'Our Vision',
            'To be the leading luxury hospitality destination in Ebonyi State, and in turn Nigeria, known for our commitment to excellence, innovation, and creating unforgettable experiences for our guests.',
            Icons.visibility,
            Colors.purple,
          ),
        ],
      ),
    );
  }

  Widget _buildOurStory(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Our Story',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'P-ZED Luxury Hotels & Suites was born from a singular ambition: to redefine luxury hospitality in the heart of the South-East, Nigeria. Our journey began in Ebonyi State, a place of vibrant culture and growing economic importance, where we saw the opportunity to establish a haven of world-class standards and authentic Nigerian warmth.',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'We believe that true luxury is personal. Our founders envisioned a space where uncompromising comfort meets genuine, intuitive service. Since opening our doors, we have been committed not just to providing accommodation, but to crafting a legacy of memorable moments. We constantly invest in innovation, from smart technology integration to curated local partnerships, to ensure P-ZED remains the standard-bearer for sophisticated, evolving guest experiences in Nigeria.',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Our Team',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Our dedicated team of hospitality professionals is committed to ensuring your stay is nothing short of exceptional. From our front desk staff to our housekeeping team, every member is trained to provide the highest level of service.',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValuesSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Our Values',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 20),
          _buildValueItem(
            context,
            'Excellence',
            'We strive for excellence in everything we do, from the smallest detail to the grandest gesture.',
            Icons.star,
            Colors.amber,
          ),
          const SizedBox(height: 16),
          _buildValueItem(
            context,
            'Integrity',
            'We conduct our business with the highest ethical standards and transparency.',
            Icons.verified,
            Colors.green,
          ),
          const SizedBox(height: 16),
          _buildValueItem(
            context,
            'Innovation',
            'We continuously innovate to provide cutting-edge services and experiences.',
            Icons.lightbulb,
            Colors.orange,
          ),
          const SizedBox(height: 16),
          _buildValueItem(
            context,
            'Hospitality',
            'We treat every guest as family, ensuring their comfort and satisfaction.',
            Icons.favorite,
            Colors.red,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context, String title, String description, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            description,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValueItem(BuildContext context, String title, String description, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    height: 1.4,
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
