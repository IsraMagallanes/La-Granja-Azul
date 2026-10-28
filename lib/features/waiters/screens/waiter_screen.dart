import 'package:flutter/material.dart';

import '../../tables/screens/tables_screen.dart';
import '../../orders/screens/orders_screen.dart';

class WaiterScreen extends StatelessWidget {
  const WaiterScreen({super.key});
  @override
  Widget build(BuildContext context) => const DefaultTabController(
    length: 2,
    child: Column(
      children: [
        TabBar(
          tabs: [
            Tab(text: 'Mesas'),
            Tab(text: 'Mis pedidos'),
          ],
        ),
        Expanded(child: TabBarView(children: [TablesScreen(), OrdersScreen()])),
      ],
    ),
  );
}
