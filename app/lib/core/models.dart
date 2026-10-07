// Modelos de dominio de AR-FIT.

double? _d(dynamic v) => v == null ? null : (v as num).toDouble();

class Profile {
  final String id;
  final String fullName;
  final String role;
  final String? gender;
  final double? weightKg;
  final double? heightCm;
  final String? size;
  final double? chestCm;
  final double? waistCm;
  final double? hipCm;
  final double? shoulderCm;
  final List<String> stylePrefs;
  final List<String> colorPrefs;
  final List<String> categoryPrefs;
  final String? storeName;
  final String? companyName;
  final String? city;
  final String? address;
  final String? phone;
  final bool verified;
  final bool onboarded;

  Profile.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        fullName = j['full_name'] ?? '',
        role = j['role'] ?? 'comprador',
        gender = j['gender'],
        weightKg = _d(j['weight_kg']),
        heightCm = _d(j['height_cm']),
        size = j['size'],
        chestCm = _d(j['chest_cm']),
        waistCm = _d(j['waist_cm']),
        hipCm = _d(j['hip_cm']),
        shoulderCm = _d(j['shoulder_cm']),
        stylePrefs = List<String>.from(j['style_prefs'] ?? const []),
        colorPrefs = List<String>.from(j['color_prefs'] ?? const []),
        categoryPrefs = List<String>.from(j['category_prefs'] ?? const []),
        storeName = j['store_name'],
        companyName = j['company_name'],
        city = j['city'],
        address = j['address'],
        phone = j['phone'],
        verified = j['verified'] ?? false,
        onboarded = j['onboarded'] ?? false;

  bool get isBuyer => role == 'comprador';
  bool get isSupplier => role == 'proveedor';
  bool get isCarrier => role == 'transportista';
  bool get isAdmin => role == 'admin';
  bool get hasMeasurements => heightCm != null && weightKg != null;
  String get displayName => storeName ?? companyName ?? fullName;
}

class SizeMeasures {
  final double? chest, waist, hip, length;
  const SizeMeasures({this.chest, this.waist, this.hip, this.length});
  factory SizeMeasures.fromJson(Map<String, dynamic> j) =>
      SizeMeasures(chest: _d(j['chest']), waist: _d(j['waist']), hip: _d(j['hip']), length: _d(j['length']));
  Map<String, dynamic> toJson() => {
        if (chest != null) 'chest': chest,
        if (waist != null) 'waist': waist,
        if (hip != null) 'hip': hip,
        if (length != null) 'length': length,
      };
}

class Product {
  final String id;
  final String supplierId;
  final String name;
  final String description;
  final String brand;
  final String category;
  final String gender;
  final List<String> styleTags;
  final String color;
  final double price;
  final Map<String, SizeMeasures> sizeChart;
  final Map<String, int> stock;
  final String imageUrl;
  final String? tryonImageUrl;
  final String tryonType;
  final Map<String, List<double>>? tryonAnchor;
  final Map<String, dynamic>? tryonRig; // puntos clave para deformar la prenda (RA)
  final String? tryonBackUrl; // vista de espalda (mismo recorte que el frente)
  final String? tryonLensId; // lente de Snap Camera Kit para el probador 3D
  final String origin;
  final String materials;
  final String? chainProductId;
  final String? chainTx;
  final String? dataHash;
  final bool chainVerified;
  final bool active;
  final DateTime createdAt;

  Product.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        supplierId = j['supplier_id'],
        name = j['name'],
        description = j['description'] ?? '',
        brand = j['brand'] ?? '',
        category = j['category'],
        gender = j['gender'] ?? 'unisex',
        styleTags = List<String>.from(j['style_tags'] ?? const []),
        color = j['color'] ?? '',
        price = (j['price'] as num).toDouble(),
        sizeChart = Map<String, dynamic>.from(j['size_chart'] ?? const {})
            .map((k, v) => MapEntry(k, SizeMeasures.fromJson(Map<String, dynamic>.from(v)))),
        stock = Map<String, dynamic>.from(j['stock'] ?? const {}).map((k, v) => MapEntry(k, (v as num).toInt())),
        imageUrl = j['image_url'],
        tryonImageUrl = j['tryon_image_url'],
        tryonType = j['tryon_type'] ?? 'top',
        tryonAnchor = j['tryon_anchor'] == null
            ? null
            : Map<String, dynamic>.from(j['tryon_anchor'])
                .map((k, v) => MapEntry(k, (v as List).map((e) => (e as num).toDouble()).toList())),
        tryonRig = j['tryon_rig'] == null ? null : Map<String, dynamic>.from(j['tryon_rig']),
        tryonBackUrl = j['tryon_back_url'],
        tryonLensId = (j['tryon_lens_id'] as String?)?.trim().isEmpty ?? true ? null : (j['tryon_lens_id'] as String).trim(),
        origin = j['origin'] ?? '',
        materials = j['materials'] ?? '',
        chainProductId = j['chain_product_id'],
        chainTx = j['chain_tx'],
        dataHash = j['data_hash'],
        chainVerified = j['chain_verified'] ?? false,
        active = j['active'] ?? true,
        createdAt = DateTime.parse(j['created_at']);

  List<String> get sizes => sortSizes(sizeChart.keys);
  List<String> get sizesInStock => sizes.where((s) => (stock[s] ?? 0) > 0).toList();
  int get totalStock => stock.values.fold(0, (a, b) => a + b);
  String get arImage => tryonImageUrl ?? imageUrl;
}

const sizeOrder = ['XS', 'S', 'M', 'L', 'XL', 'XXL'];
List<String> sortSizes(Iterable<String> s) =>
    s.toList()..sort((a, b) => sizeOrder.indexOf(a).compareTo(sizeOrder.indexOf(b)));

class CartItem {
  final String id;
  final String size;
  final int quantity;
  final Product product;
  CartItem.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        size = j['size'],
        quantity = j['quantity'],
        product = Product.fromJson(j['products']);
  double get subtotal => product.price * quantity;
}

class OrderItem {
  final String productId;
  final String productName;
  final String imageUrl;
  final String size;
  final int quantity;
  final double unitPrice;
  OrderItem.fromJson(Map<String, dynamic> j)
      : productId = j['product_id'],
        productName = j['product_name'],
        imageUrl = j['image_url'],
        size = j['size'],
        quantity = j['quantity'],
        unitPrice = (j['unit_price'] as num).toDouble();
}

class ShipmentEvent {
  final String id;
  final String status;
  final String location;
  final String note;
  final String actorRole;
  final String? txHash;
  final int? blockNumber;
  final DateTime createdAt;
  ShipmentEvent.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        status = j['status'],
        location = j['location'] ?? '',
        note = j['note'] ?? '',
        actorRole = j['actor_role'],
        txHash = j['tx_hash'],
        blockNumber = j['block_number'],
        createdAt = DateTime.parse(j['created_at']);
}

class Order {
  final String id;
  final String buyerId;
  final String supplierId;
  final String? carrierId;
  final String status;
  final double total;
  final String shippingName;
  final String shippingAddress;
  final String shippingCity;
  final String paymentRef;
  final String? chainOrderId;
  final String chainStatus;
  final DateTime createdAt;
  final List<OrderItem> items;
  final List<ShipmentEvent> events;

  Order.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        buyerId = j['buyer_id'],
        supplierId = j['supplier_id'],
        carrierId = j['carrier_id'],
        status = j['status'],
        total = (j['total'] as num).toDouble(),
        shippingName = j['shipping_name'],
        shippingAddress = j['shipping_address'],
        shippingCity = j['shipping_city'],
        paymentRef = j['payment_ref'],
        chainOrderId = j['chain_order_id'],
        chainStatus = j['chain_status'] ?? 'pending',
        createdAt = DateTime.parse(j['created_at']),
        items = ((j['order_items'] ?? []) as List).map((e) => OrderItem.fromJson(e)).toList(),
        events = (((j['shipment_events'] ?? []) as List).map((e) => ShipmentEvent.fromJson(e)).toList())
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
}

class FitResult {
  final String size;
  final String fit; // ajustada | ideal | holgada
  final double confidence;
  const FitResult(this.size, this.fit, this.confidence);
  factory FitResult.fromJson(Map<String, dynamic> j) =>
      FitResult(j['size'], j['fit'], (j['confidence'] as num).toDouble());
}

class Recommendation {
  final String productId;
  final double score;
  final List<String> reasons;
  final FitResult? fit;
  Recommendation.fromJson(Map<String, dynamic> j)
      : productId = j['product_id'],
        score = (j['score'] as num).toDouble(),
        reasons = List<String>.from(j['reasons'] ?? const []),
        fit = j['fit'] == null ? null : FitResult.fromJson(j['fit']);
}

class WeightedKey {
  final String key;
  final double weight;
  WeightedKey.fromJson(Map<String, dynamic> j)
      : key = j['key'],
        weight = (j['weight'] as num).toDouble();
}

class StyleProfile {
  final List<WeightedKey> categories, styles, colors, brands;
  final int signals;
  StyleProfile.fromJson(Map<String, dynamic> j)
      : categories = _list(j['categories']),
        styles = _list(j['styles']),
        colors = _list(j['colors']),
        brands = _list(j['brands']),
        signals = j['signals'] ?? 0;
  static List<WeightedKey> _list(dynamic v) =>
      ((v ?? []) as List).map((e) => WeightedKey.fromJson(Map<String, dynamic>.from(e))).toList();
}

class PublicProfile {
  final String id;
  final String fullName;
  final String role;
  final String? storeName;
  final String? companyName;
  final String? city;
  final bool verified;
  PublicProfile.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        fullName = j['full_name'] ?? '',
        role = j['role'],
        storeName = j['store_name'],
        companyName = j['company_name'],
        city = j['city'],
        verified = j['verified'] ?? false;
  String get displayName => storeName ?? companyName ?? fullName;
}
