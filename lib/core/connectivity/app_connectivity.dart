import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:provider/provider.dart';

class AppConnectivity extends ChangeNotifier {
  bool _isOnline = true;
  ConnectivityResult _connectionStatus = ConnectivityResult.none;
  
  bool get isOnline => _isOnline;
  ConnectivityResult get connectionStatus => _connectionStatus;
  
  bool get isWifi => _connectionStatus == ConnectivityResult.wifi;
  bool get isMobile => _connectionStatus == ConnectivityResult.mobile;
  bool get isEthernet => _connectionStatus == ConnectivityResult.ethernet;
  bool get isBluetooth => _connectionStatus == ConnectivityResult.bluetooth;
  bool get isVpn => _connectionStatus == ConnectivityResult.vpn;
  bool get isOther => _connectionStatus == ConnectivityResult.other;

  AppConnectivity() {
    _initConnectivity();
    Connectivity().onConnectivityChanged.listen(_updateConnectionStatus);
  }

  Future<void> _initConnectivity() async {
    late ConnectivityResult result;
    try {
      result = await Connectivity().checkConnectivity();
    } catch (e) {
      result = ConnectivityResult.none;
    }
    _updateConnectionStatus(result);
  }

  void _updateConnectionStatus(ConnectivityResult result) {
    _connectionStatus = result;
    _isOnline = result != ConnectivityResult.none;
    notifyListeners();
  }

  String get connectionTypeString {
    switch (_connectionStatus) {
      case ConnectivityResult.wifi:
        return 'WiFi';
      case ConnectivityResult.mobile:
        return 'Mobile Data';
      case ConnectivityResult.ethernet:
        return 'Ethernet';
      case ConnectivityResult.bluetooth:
        return 'Bluetooth';
      case ConnectivityResult.vpn:
        return 'VPN';
      case ConnectivityResult.other:
        return 'Other';
      case ConnectivityResult.none:
        return 'No Connection';
    }
  }

  IconData get connectionIcon {
    switch (_connectionStatus) {
      case ConnectivityResult.wifi:
        return Icons.wifi;
      case ConnectivityResult.mobile:
        return Icons.signal_cellular_alt;
      case ConnectivityResult.ethernet:
        return Icons.cable;
      case ConnectivityResult.bluetooth:
        return Icons.bluetooth;
      case ConnectivityResult.vpn:
        return Icons.vpn_key;
      case ConnectivityResult.other:
        return Icons.network_check;
      case ConnectivityResult.none:
        return Icons.wifi_off;
    }
  }

  Color get connectionColor {
    switch (_connectionStatus) {
      case ConnectivityResult.wifi:
        return Colors.green;
      case ConnectivityResult.mobile:
        return Colors.blue;
      case ConnectivityResult.ethernet:
        return Colors.orange;
      case ConnectivityResult.bluetooth:
        return Colors.purple;
      case ConnectivityResult.vpn:
        return Colors.indigo;
      case ConnectivityResult.other:
        return Colors.grey;
      case ConnectivityResult.none:
        return Colors.red;
    }
  }
}

// Connectivity status widget
class ConnectivityStatusWidget extends StatelessWidget {
  const ConnectivityStatusWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppConnectivity>(
      builder: (context, connectivity, child) {
        if (connectivity.isOnline) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: connectivity.connectionColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: connectivity.connectionColor.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  connectivity.connectionIcon,
                  size: 16,
                  color: connectivity.connectionColor,
                ),
                const SizedBox(width: 4),
                Text(
                  connectivity.connectionTypeString,
                  style: TextStyle(
                    color: connectivity.connectionColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        } else {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.red.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.wifi_off,
                  size: 16,
                  color: Colors.red,
                ),
                const SizedBox(width: 4),
                Text(
                  'Offline',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }
      },
    );
  }
}

// Offline banner
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppConnectivity>(
      builder: (context, connectivity, child) {
        if (!connectivity.isOnline) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.red,
            child: Row(
              children: [
                const Icon(
                  Icons.wifi_off,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'You are currently offline. Some features may not be available.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 20,
                  ),
                  onPressed: () {
                    // Hide banner (you can implement this with a state variable)
                  },
                ),
              ],
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

// Connection quality indicator
class ConnectionQualityIndicator extends StatelessWidget {
  const ConnectionQualityIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppConnectivity>(
      builder: (context, connectivity, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(4, (index) {
            final isActive = connectivity.isOnline && 
                (connectivity.isWifi || connectivity.isEthernet) && 
                index < 3;
            
            return Container(
              margin: const EdgeInsets.only(right: 2),
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: isActive ? connectivity.connectionColor : Colors.grey[300],
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}
