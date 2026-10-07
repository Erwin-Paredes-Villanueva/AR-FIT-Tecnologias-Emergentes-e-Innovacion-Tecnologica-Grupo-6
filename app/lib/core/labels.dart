// Textos en español para valores del dominio.
import 'package:intl/intl.dart';

// Formato peruano: S/ 1,299.90
final money = NumberFormat.currency(locale: 'en_US', symbol: 'S/ ', decimalDigits: 2);
final dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm');
final dateFmt = DateFormat('dd/MM/yyyy');

const categoryLabels = {
  'polo': 'Polos',
  'camisa': 'Camisas',
  'polera': 'Poleras',
  'casaca': 'Casacas',
  'vestido': 'Vestidos',
  'pantalon': 'Pantalones',
  'falda': 'Faldas',
  'short': 'Shorts',
};

const categoryTryon = {
  'polo': 'top',
  'camisa': 'top',
  'polera': 'top',
  'casaca': 'top',
  'vestido': 'full',
  'pantalon': 'bottom',
  'falda': 'bottom',
  'short': 'bottom',
};

const styleOptions = [
  'casual', 'urbano', 'streetwear', 'elegante', 'formal', 'oficina', 'minimalista', 'clásico',
  'deportivo', 'romántico', 'bohemio', 'vintage', 'rockero', 'fiesta', 'playa', 'outdoor', 'básico',
];

const colorOptions = {
  'negro': 0xFF222222,
  'blanco': 0xFFF5F5F2,
  'gris': 0xFF9A9EA6,
  'beige': 0xFFC9B28C,
  'crema': 0xFFF3E4D0,
  'marrón': 0xFF7A4E3A,
  'azul': 0xFF2F4E86,
  'celeste': 0xFFA9C7E6,
  'verde': 0xFF6B7A4B,
  'amarillo': 0xFFD9A441,
  'rojo': 0xFFB3262E,
  'rosado': 0xFFE7A9B8,
  'morado': 0xFFB7A3D6,
};

const roleLabels = {
  'comprador': 'Comprador',
  'proveedor': 'Proveedor',
  'transportista': 'Transportista',
  'admin': 'Administrador',
};

const statusLabels = {
  'created': 'Pedido pagado',
  'prepared': 'Preparado por el proveedor',
  'picked_up': 'Recogido por el transportista',
  'in_transit': 'En tránsito',
  'delivered': 'Entregado',
  'received': 'Recepción confirmada',
  'cancelled': 'Cancelado',
};

const fitLabels = {'ajustada': 'Ajustada', 'ideal': 'Calce ideal', 'holgada': 'Holgada'};

const peruCities = [
  'Lima', 'Arequipa', 'Cusco', 'Trujillo', 'Chiclayo', 'Piura', 'Iquitos', 'Huancayo', 'Tacna', 'Puno', 'Ica', 'Cajamarca',
];
