import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/labels.dart';
import '../../core/models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../cart/cart_screen.dart';
import '../product/product_card.dart';
import '../product/product_detail.dart';

class BuyerHome extends StatefulWidget {
  const BuyerHome({super.key});

  @override
  State<BuyerHome> createState() => _BuyerHomeState();
}

class _BuyerHomeState extends State<BuyerHome> {
  String? _category;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<AppState>().loadFeed());
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final profile = state.profile!;
    final ranked = state.rankedCatalog;
    final picks = state.recommendations
        .take(8)
        .map((r) => state.productById(r.productId))
        .whereType<Product>()
        .toList();
    final filtered = ranked.where((p) {
      if (_category != null && p.category != _category) return false;
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          p.brand.toLowerCase().contains(q) ||
          p.color.contains(q) ||
          p.styleTags.any((s) => s.contains(q));
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Logo(size: 24),
        actions: [
          IconButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartScreen())),
            icon: Badge(
              isLabelVisible: state.cartCount > 0,
              label: Text('${state.cartCount}'),
              child: const Icon(Icons.shopping_bag_outlined),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: state.loadFeed,
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Hola, ${profile.fullName.split(' ').first} 👋',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                const Text('Tu vitrina se adapta a tu estilo y a tus medidas', style: TextStyle(color: AppColors.muted)),
                const SizedBox(height: 14),
                TextField(
                  onChanged: (v) => setState(() => _query = v.trim()),
                  decoration: const InputDecoration(
                    hintText: 'Buscar prendas, marcas, estilos…',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ]),
            ),
          ),
          if (state.loadingFeed && state.catalog.isEmpty)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
          else ...[
            if (picks.isNotEmpty && _query.isEmpty && _category == null) ...[
              SliverToBoxAdapter(
                child: SectionTitle(
                  'Elegido para ti',
                  subtitle: 'Recomendaciones de la IA según tus gustos y medidas',
                  trailing: const Pill('IA', icon: Icons.auto_awesome, color: AppColors.ai),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 300,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    scrollDirection: Axis.horizontal,
                    itemCount: picks.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (_, i) => SizedBox(
                      width: 190,
                      child: ProductCard(product: picks[i], recommendation: state.recommendationFor(picks[i].id), showReason: true),
                    ),
                  ),
                ),
              ),
            ],
            SliverToBoxAdapter(
              child: SizedBox(
                height: 58,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                  scrollDirection: Axis.horizontal,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: const Text('Todo'),
                        selected: _category == null,
                        onSelected: (_) => setState(() => _category = null),
                      ),
                    ),
                    for (final c in categoryLabels.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(c.value),
                          selected: _category == c.key,
                          onSelected: (_) => setState(() => _category = _category == c.key ? null : c.key),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (state.feedError != null && state.catalog.isEmpty)
              SliverFillRemaining(
                child: EmptyState(
                  icon: Icons.cloud_off,
                  title: 'No se pudo cargar el catálogo',
                  message: state.feedError,
                  action: FilledButton(onPressed: state.loadFeed, child: const Text('Reintentar')),
                ),
              )
            else if (filtered.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(icon: Icons.search_off, title: 'Sin resultados'),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.62,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => ProductCard(product: filtered[i], recommendation: state.recommendationFor(filtered[i].id)),
                    childCount: filtered.length,
                  ),
                ),
              ),
          ],
        ]),
      ),
    );
  }
}

void openProduct(BuildContext context, Product p) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetail(product: p)));
