import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api.dart';
import 'models.dart';
import 'sizing.dart';

/// Estado global: sesión, perfil, favoritos, carrito y recomendaciones.
class AppState extends ChangeNotifier {
  AppState() {
    _authSub = sb.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedIn || data.event == AuthChangeEvent.initialSession) {
        if (data.session != null) loadProfile();
      } else if (data.event == AuthChangeEvent.signedOut) {
        _clear();
      }
    });
  }

  late final StreamSubscription<AuthState> _authSub;

  Profile? profile;
  bool loadingProfile = false;
  Set<String> favorites = {};
  int cartCount = 0;

  List<Product> catalog = [];
  List<Recommendation> recommendations = [];
  StyleProfile? styleProfile;
  bool loadingFeed = false;
  String? feedError;

  bool get signedIn => sb.auth.currentSession != null;
  BodyMeasures? get body => profile == null ? null : BodyMeasures.fromProfile(profile!);

  Future<void> loadProfile() async {
    loadingProfile = true;
    notifyListeners();
    try {
      profile = await Api.myProfile();
      if (profile!.isBuyer) {
        favorites = await Api.favorites();
        await refreshCart();
      }
    } catch (e) {
      debugPrint('loadProfile: $e');
    } finally {
      loadingProfile = false;
      notifyListeners();
    }
  }

  Future<void> refreshCart() async {
    final items = await Api.cart();
    cartCount = items.fold(0, (a, b) => a + b.quantity);
    notifyListeners();
  }

  /// Catálogo + ranking personalizado de la IA.
  Future<void> loadFeed() async {
    loadingFeed = true;
    feedError = null;
    notifyListeners();
    try {
      catalog = await Api.products();
      try {
        final rec = await Api.recommendations();
        recommendations = rec.items;
        styleProfile = rec.profile;
      } catch (e) {
        feedError = 'Recomendaciones no disponibles: $e';
        recommendations = [];
      }
    } catch (e) {
      feedError = e.toString();
    } finally {
      loadingFeed = false;
      notifyListeners();
    }
  }

  Product? productById(String id) {
    for (final p in catalog) {
      if (p.id == id) return p;
    }
    return null;
  }

  Recommendation? recommendationFor(String productId) {
    for (final r in recommendations) {
      if (r.productId == productId) return r;
    }
    return null;
  }

  /// Productos ordenados según el recomendador (los no puntuados al final).
  List<Product> get rankedCatalog {
    final order = {for (var i = 0; i < recommendations.length; i++) recommendations[i].productId: i};
    final list = [...catalog];
    list.sort((a, b) => (order[a.id] ?? 1 << 20).compareTo(order[b.id] ?? 1 << 20));
    return list;
  }

  Future<void> toggleFavorite(String productId) async {
    final fav = !favorites.contains(productId);
    fav ? favorites.add(productId) : favorites.remove(productId);
    notifyListeners();
    await Api.setFavorite(productId, fav);
  }

  Future<void> signOut() => sb.auth.signOut();

  void _clear() {
    profile = null;
    favorites = {};
    cartCount = 0;
    catalog = [];
    recommendations = [];
    styleProfile = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }
}
