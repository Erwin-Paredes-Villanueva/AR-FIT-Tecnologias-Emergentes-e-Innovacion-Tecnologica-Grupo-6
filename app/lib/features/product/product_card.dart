import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/labels.dart';
import '../../core/models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'product_detail.dart';

class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.product, this.recommendation, this.showReason = false});
  final Product product;
  final Recommendation? recommendation;
  final bool showReason;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final fav = state.favorites.contains(product.id);
    final fit = recommendation?.fit;
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetail(product: product))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Stack(children: [
            Positioned.fill(child: Hero(tag: 'img-${product.id}-$showReason', child: GarmentImage(product.imageUrl))),
            Positioned(
              top: 6,
              right: 6,
              child: Material(
                color: Colors.white.withValues(alpha: 0.9),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => state.toggleFavorite(product.id),
                  child: Padding(
                    padding: const EdgeInsets.all(7),
                    child: Icon(fav ? Icons.favorite : Icons.favorite_border, size: 18, color: fav ? AppColors.accent : AppColors.ink),
                  ),
                ),
              ),
            ),
            if (product.chainVerified)
              const Positioned(
                left: 8,
                top: 8,
                child: Pill('Auténtica', icon: Icons.verified, color: AppColors.chain, filled: true),
              ),
            if (fit != null)
              Positioned(
                left: 8,
                bottom: 8,
                child: Pill('Tu talla: ${fit.size}', color: AppColors.ai, filled: true),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        Text(product.brand.toUpperCase(),
            style: const TextStyle(fontSize: 10.5, letterSpacing: 0.8, color: AppColors.muted, fontWeight: FontWeight.w600)),
        Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(money.format(product.price), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.accent)),
        if (showReason && recommendation != null && recommendation!.reasons.isNotEmpty)
          Text(recommendation!.reasons.first,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: AppColors.ai)),
      ]),
    );
  }
}
