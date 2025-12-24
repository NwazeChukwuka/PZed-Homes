import 'package:pzed_homes/data/models/menu_item.dart';

class OrderItem {
  final MenuItem menuItem;
  int quantity;

  OrderItem({
    required this.menuItem,
    this.quantity = 1,
  });

  int get totalPrice => menuItem.price * quantity;
}