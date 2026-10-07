// Acceso a Supabase (datos protegidos por RLS) y a las Edge Functions.
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

SupabaseClient get sb => Supabase.instance.client;

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

const _orderSelect = '*, order_items(*), shipment_events(*)';

class Api {
  // ------------------------------------------------------------ edge functions
  static Future<Map<String, dynamic>> fn(String name, Map<String, dynamic> body) async {
    try {
      final res = await sb.functions.invoke(name, body: body);
      return Map<String, dynamic>.from(res.data as Map);
    } on FunctionException catch (e) {
      final details = e.details;
      final msg = details is Map && details['error'] != null ? details['error'].toString() : 'Error del servidor (${e.status})';
      throw ApiException(msg);
    }
  }

  // ------------------------------------------------------------------ perfil
  static Future<Profile> myProfile() async {
    final row = await sb.from('profiles').select().eq('id', sb.auth.currentUser!.id).single();
    return Profile.fromJson(row);
  }

  static Future<void> updateProfile(Map<String, dynamic> values) =>
      sb.from('profiles').update(values).eq('id', sb.auth.currentUser!.id);

  static Future<List<PublicProfile>> publicProfiles({String? role}) async {
    var q = sb.from('public_profiles').select();
    if (role != null) q = q.eq('role', role);
    final rows = await q;
    return rows.map(PublicProfile.fromJson).toList();
  }

  // ---------------------------------------------------------------- catálogo
  static Future<List<Product>> products({String? supplierId}) async {
    var q = sb.from('products').select();
    if (supplierId != null) {
      q = q.eq('supplier_id', supplierId);
    } else {
      q = q.eq('active', true);
    }
    final rows = await q.order('created_at', ascending: false);
    return rows.map(Product.fromJson).toList();
  }

  static Future<Product?> product(String id) async {
    final row = await sb.from('products').select().eq('id', id).maybeSingle();
    return row == null ? null : Product.fromJson(row);
  }

  static Future<({List<Recommendation> items, StyleProfile profile})> recommendations() async {
    final res = await fn('recommend', {'limit': 100});
    return (
      items: (res['items'] as List).map((e) => Recommendation.fromJson(Map<String, dynamic>.from(e))).toList(),
      profile: StyleProfile.fromJson(Map<String, dynamic>.from(res['profile'])),
    );
  }

  /// Registra una señal para el recomendador (vista, favorito, prueba RA...).
  static Future<void> track(String productId, String kind) async {
    try {
      await sb.from('interactions').insert({'user_id': sb.auth.currentUser!.id, 'product_id': productId, 'kind': kind});
    } catch (_) {/* no bloquea la UI */}
  }

  static Future<Set<String>> favorites() async {
    final rows = await sb.from('favorites').select('product_id');
    return rows.map((r) => r['product_id'] as String).toSet();
  }

  static Future<void> setFavorite(String productId, bool fav) async {
    final uid = sb.auth.currentUser!.id;
    if (fav) {
      await sb.from('favorites').upsert({'user_id': uid, 'product_id': productId});
      await track(productId, 'like');
    } else {
      await sb.from('favorites').delete().eq('user_id', uid).eq('product_id', productId);
    }
  }

  // ----------------------------------------------------------------- carrito
  static Future<List<CartItem>> cart() async {
    final rows = await sb.from('cart_items').select('*, products(*)').order('created_at');
    return rows.map(CartItem.fromJson).toList();
  }

  static Future<void> addToCart(String productId, String size, {int quantity = 1}) async {
    final uid = sb.auth.currentUser!.id;
    final existing = await sb
        .from('cart_items')
        .select('id,quantity')
        .eq('user_id', uid)
        .eq('product_id', productId)
        .eq('size', size)
        .maybeSingle();
    if (existing != null) {
      await sb.from('cart_items').update({'quantity': (existing['quantity'] as int) + quantity}).eq('id', existing['id']);
    } else {
      await sb.from('cart_items').insert({'user_id': uid, 'product_id': productId, 'size': size, 'quantity': quantity});
    }
    await track(productId, 'cart');
  }

  static Future<void> setCartQuantity(String id, int quantity) => quantity <= 0
      ? sb.from('cart_items').delete().eq('id', id)
      : sb.from('cart_items').update({'quantity': quantity}).eq('id', id);

  static Future<List<String>> checkout({
    required String name,
    required String address,
    required String city,
    required String paymentMethod,
  }) async {
    final res = await fn('checkout', {
      'shipping_name': name,
      'shipping_address': address,
      'shipping_city': city,
      'payment_method': paymentMethod,
    });
    return List<String>.from(res['orders']);
  }

  // ----------------------------------------------------------------- pedidos
  static Future<List<Order>> orders({String? asRole}) async {
    final uid = sb.auth.currentUser!.id;
    var q = sb.from('orders').select(_orderSelect);
    switch (asRole) {
      case 'comprador':
        q = q.eq('buyer_id', uid);
      case 'proveedor':
        q = q.eq('supplier_id', uid);
      case 'transportista':
        q = q.eq('carrier_id', uid);
    }
    final rows = await q.order('created_at', ascending: false);
    return rows.map(Order.fromJson).toList();
  }

  static Future<Order> order(String id) async {
    final row = await sb.from('orders').select(_orderSelect).eq('id', id).single();
    return Order.fromJson(row);
  }

  static Future<Map<String, dynamic>> orderEvent({
    required String orderId,
    required String status,
    String? location,
    String? note,
    String? carrierId,
  }) =>
      fn('order-event', {
        'order_id': orderId,
        'status': status,
        'location': location,
        'note': note,
        'carrier_id': carrierId,
      });

  // --------------------------------------------------------------- proveedor
  static Future<String> uploadImage(Uint8List bytes, String fileName, String contentType) async {
    final path = '${sb.auth.currentUser!.id}/${DateTime.now().millisecondsSinceEpoch}_$fileName';
    await sb.storage.from('products').uploadBinary(path, bytes, fileOptions: FileOptions(contentType: contentType));
    return sb.storage.from('products').getPublicUrl(path);
  }

  static Future<Product> saveProduct(Map<String, dynamic> values, {String? id}) async {
    final row = id == null
        ? await sb.from('products').insert({...values, 'supplier_id': sb.auth.currentUser!.id}).select().single()
        : await sb.from('products').update(values).eq('id', id).select().single();
    return Product.fromJson(row);
  }

  static Future<Map<String, dynamic>> registerOnChain(String productId) =>
      fn('chain-product', {'action': 'register', 'product_id': productId});

  // ------------------------------------------------------------------- admin
  static Future<List<Profile>> allProfiles() async {
    final rows = await sb.from('profiles').select().order('created_at', ascending: false);
    return rows.map(Profile.fromJson).toList();
  }

  static Future<void> setVerified(String profileId, bool verified) =>
      sb.from('profiles').update({'verified': verified}).eq('id', profileId);

  static Future<Map<String, dynamic>> verifyProductOnChain(String productId, bool verified) =>
      fn('chain-product', {'action': 'verify', 'product_id': productId, 'verified': verified});
}
