// Catálogo demo de AR-FIT. Las imágenes se generan con tools/garments/generate.py
// Medidas de la tabla de tallas en cm (contorno de pecho/cintura/cadera, largo).

const chart = (sizes, cols) =>
  Object.fromEntries(sizes.map((s, i) => [s, Object.fromEntries(Object.entries(cols).map(([k, v]) => [k, v[i]]))]));

const TOP4 = ['S', 'M', 'L', 'XL'];
const W4 = ['XS', 'S', 'M', 'L'];

export const CHARTS = {
  polo: chart(TOP4, { chest: [96, 102, 108, 114], length: [68, 70, 72, 74] }),
  camisa: chart(TOP4, { chest: [100, 106, 112, 118], length: [72, 74, 76, 78] }),
  polera: chart(TOP4, { chest: [104, 110, 116, 122], length: [66, 68, 70, 72] }),
  casaca: chart(TOP4, { chest: [104, 110, 116, 122], length: [64, 66, 68, 70] }),
  vestido: chart(W4, { chest: [82, 86, 90, 96], waist: [64, 68, 72, 78], hip: [90, 94, 98, 104], length: [95, 97, 99, 101] }),
  pantalon: chart(TOP4, { waist: [74, 80, 86, 92], hip: [96, 102, 108, 114], length: [100, 102, 104, 106] }),
  pantalon_m: chart(W4, { waist: [64, 68, 74, 80], hip: [90, 94, 100, 106], length: [98, 100, 102, 104] }),
  falda: chart(W4, { waist: [64, 68, 72, 78], hip: [92, 96, 100, 106], length: [45, 46, 47, 48] }),
  short: chart(TOP4, { waist: [74, 80, 86, 92], hip: [98, 104, 110, 116], length: [45, 46, 47, 48] }),
};

// supplier: 0 = Andina Textil (Lima), 1 = Qori Moda (Arequipa)
export const PRODUCTS = [
  { img: 'polo-blanco', supplier: 0, name: 'Polo básico Pima', brand: 'Andina Wear', category: 'polo', gender: 'unisex', color: 'blanco', price: 59.9, style: ['básico', 'minimalista', 'casual'], origin: 'Gamarra, Lima - Perú', materials: '100% algodón pima peruano', desc: 'Polo de corte regular en algodón pima de fibra extralarga, suave y respirable.' },
  { img: 'polo-negro', supplier: 0, name: 'Polo esencial negro', brand: 'Andina Wear', category: 'polo', gender: 'unisex', color: 'negro', price: 59.9, style: ['básico', 'urbano', 'minimalista'], origin: 'Gamarra, Lima - Perú', materials: '100% algodón pima peruano', desc: 'El básico que combina con todo. Tejido jersey 30/1 de algodón pima.' },
  { img: 'polo-mostaza', supplier: 1, name: 'Polo con bolsillo mostaza', brand: 'Qori', category: 'polo', gender: 'unisex', color: 'amarillo', price: 64.9, style: ['casual', 'urbano'], origin: 'Arequipa - Perú', materials: '100% algodón orgánico', desc: 'Polo holgado con bolsillo al pecho teñido con tintes de bajo impacto.' },
  { img: 'polo-rayas', supplier: 1, name: 'Polo marinero a rayas', brand: 'Qori', category: 'polo', gender: 'unisex', color: 'azul', price: 69.9, style: ['clásico', 'casual'], origin: 'Arequipa - Perú', materials: '95% algodón, 5% elastano', desc: 'Rayas navy clásicas en tejido con un toque de elasticidad.' },
  { img: 'polo-verde', supplier: 0, name: 'Polo oversize oliva', brand: 'Lima Urban', category: 'polo', gender: 'hombre', color: 'verde', price: 62.0, style: ['urbano', 'streetwear'], origin: 'Gamarra, Lima - Perú', materials: '100% algodón peinado', desc: 'Corte oversize de hombro caído, ideal para looks streetwear.' },
  { img: 'camisa-celeste', supplier: 0, name: 'Camisa Oxford celeste', brand: 'Andina Wear', category: 'camisa', gender: 'hombre', color: 'celeste', price: 119.0, style: ['formal', 'clásico', 'oficina'], origin: 'Gamarra, Lima - Perú', materials: '100% algodón Oxford', desc: 'Camisa Oxford de manga larga con bolsillo, perfecta para la oficina.' },
  { img: 'camisa-blanca', supplier: 1, name: 'Camisa blanca popelina', brand: 'Qori', category: 'camisa', gender: 'unisex', color: 'blanco', price: 109.0, style: ['formal', 'minimalista', 'oficina'], origin: 'Arequipa - Perú', materials: '100% algodón popelina', desc: 'Popelina ligera de caída limpia, un imprescindible del armario.' },
  { img: 'camisa-cuadros', supplier: 0, name: 'Camisa leñadora cuadros', brand: 'Lima Urban', category: 'camisa', gender: 'hombre', color: 'rojo', price: 99.0, style: ['casual', 'urbano', 'outdoor'], origin: 'Gamarra, Lima - Perú', materials: '80% algodón, 20% poliéster franela', desc: 'Franela a cuadros búfalo, abrigadora y resistente.' },
  { img: 'polera-gris', supplier: 1, name: 'Polera con capucha gris', brand: 'Qori', category: 'polera', gender: 'unisex', color: 'gris', price: 139.0, style: ['deportivo', 'urbano', 'casual'], origin: 'Arequipa - Perú', materials: '70% algodón, 30% poliéster french terry', desc: 'Hoodie de felpa french terry con bolsillo canguro y puños acanalados.' },
  { img: 'polera-lila', supplier: 1, name: 'Polera lila soft', brand: 'Qori', category: 'polera', gender: 'mujer', color: 'morado', price: 139.0, style: ['casual', 'deportivo'], origin: 'Arequipa - Perú', materials: '70% algodón, 30% poliéster', desc: 'Tono lavanda suave con interior perchado, ideal para el invierno limeño.' },
  { img: 'polera-negra', supplier: 0, name: 'Polera urbana negra', brand: 'Lima Urban', category: 'polera', gender: 'unisex', color: 'negro', price: 129.0, style: ['urbano', 'streetwear', 'deportivo'], origin: 'Gamarra, Lima - Perú', materials: '80% algodón, 20% poliéster', desc: 'Hoodie negra de corte relajado para el día a día.' },
  { img: 'casaca-denim', supplier: 0, name: 'Casaca denim clásica', brand: 'Pachacuti Denim', category: 'casaca', gender: 'unisex', color: 'azul', price: 189.0, style: ['casual', 'clásico', 'urbano'], origin: 'Gamarra, Lima - Perú', materials: '100% algodón denim 12 oz', desc: 'Chaqueta trucker en denim rígido con botones metálicos y costuras contrastantes.' },
  { img: 'casaca-cuero', supplier: 1, name: 'Casaca de cuero negra', brand: 'Qori', category: 'casaca', gender: 'unisex', color: 'negro', price: 349.0, style: ['rockero', 'urbano', 'elegante'], origin: 'Arequipa - Perú', materials: 'Cuero bovino curtido vegetal, forro de algodón', desc: 'Cuero curtido artesanalmente en Arequipa, con solapas amplias.' },
  { img: 'casaca-beige', supplier: 1, name: 'Blazer beige lino', brand: 'Qori', category: 'casaca', gender: 'mujer', color: 'beige', price: 229.0, style: ['elegante', 'oficina', 'minimalista'], origin: 'Arequipa - Perú', materials: '55% lino, 45% algodón', desc: 'Blazer desestructurado de lino, fresco y sofisticado.' },
  { img: 'vestido-rojo', supplier: 1, name: 'Vestido midi rojo', brand: 'Qori', category: 'vestido', gender: 'mujer', color: 'rojo', price: 179.0, style: ['elegante', 'fiesta', 'romántico'], origin: 'Arequipa - Perú', materials: '100% viscosa', desc: 'Vestido de escote en V con falda amplia y cintura marcada.' },
  { img: 'vestido-negro', supplier: 0, name: 'Vestido negro sin mangas', brand: 'Andina Wear', category: 'vestido', gender: 'mujer', color: 'negro', price: 169.0, style: ['elegante', 'minimalista', 'fiesta'], origin: 'Gamarra, Lima - Perú', materials: '95% poliéster, 5% elastano', desc: 'El little black dress en versión midi, fácil de combinar.' },
  { img: 'vestido-lunares', supplier: 1, name: 'Vestido lunares navy', brand: 'Qori', category: 'vestido', gender: 'mujer', color: 'azul', price: 159.0, style: ['romántico', 'vintage', 'casual'], origin: 'Arequipa - Perú', materials: '100% algodón', desc: 'Estampado de lunares con aire vintage y manga corta.' },
  { img: 'vestido-floral', supplier: 0, name: 'Vestido floral primavera', brand: 'Andina Wear', category: 'vestido', gender: 'mujer', color: 'crema', price: 165.0, style: ['romántico', 'bohemio', 'casual'], origin: 'Gamarra, Lima - Perú', materials: '100% algodón voile', desc: 'Estampado floral inspirado en la flora andina, tela ligera.' },
  { img: 'pantalon-jean', supplier: 0, name: 'Jean recto clásico', brand: 'Pachacuti Denim', category: 'pantalon', gender: 'hombre', color: 'azul', price: 149.0, style: ['casual', 'clásico', 'urbano'], origin: 'Gamarra, Lima - Perú', materials: '98% algodón, 2% elastano denim', desc: 'Jean de tiro medio y pierna recta con lavado stone.', chart: 'pantalon' },
  { img: 'pantalon-negro', supplier: 1, name: 'Pantalón de vestir negro', brand: 'Qori', category: 'pantalon', gender: 'unisex', color: 'negro', price: 139.0, style: ['formal', 'oficina', 'elegante'], origin: 'Arequipa - Perú', materials: '65% poliéster, 35% viscosa', desc: 'Pantalón slim de vestir con caída impecable.', chart: 'pantalon' },
  { img: 'pantalon-chino', supplier: 0, name: 'Pantalón chino arena', brand: 'Andina Wear', category: 'pantalon', gender: 'hombre', color: 'beige', price: 129.0, style: ['casual', 'clásico', 'oficina'], origin: 'Gamarra, Lima - Perú', materials: '97% algodón, 3% elastano gabardina', desc: 'Chino de gabardina stretch, versátil para oficina o fin de semana.', chart: 'pantalon' },
  { img: 'pantalon-palazzo', supplier: 1, name: 'Pantalón palazzo terracota', brand: 'Qori', category: 'pantalon', gender: 'mujer', color: 'marrón', price: 135.0, style: ['bohemio', 'elegante'], origin: 'Arequipa - Perú', materials: '100% lino', desc: 'Pierna ancha y fluida en lino color terracota.', chart: 'pantalon_m' },
  { img: 'falda-plisada', supplier: 1, name: 'Falda plisada rosa', brand: 'Qori', category: 'falda', gender: 'mujer', color: 'rosado', price: 99.0, style: ['romántico', 'casual'], origin: 'Arequipa - Perú', materials: '100% poliéster reciclado', desc: 'Falda midi plisada con pretina elástica.' },
  { img: 'falda-negra', supplier: 0, name: 'Falda A negra', brand: 'Andina Wear', category: 'falda', gender: 'mujer', color: 'negro', price: 89.0, style: ['minimalista', 'oficina', 'elegante'], origin: 'Gamarra, Lima - Perú', materials: '70% algodón, 30% poliéster', desc: 'Silueta en A de largo medio, básica y elegante.' },
  { img: 'short-denim', supplier: 0, name: 'Short denim celeste', brand: 'Pachacuti Denim', category: 'short', gender: 'unisex', color: 'celeste', price: 89.0, style: ['casual', 'playa', 'urbano'], origin: 'Gamarra, Lima - Perú', materials: '100% algodón denim', desc: 'Short de denim lavado claro para el verano.' },
  { img: 'short-caqui', supplier: 1, name: 'Short chino caqui', brand: 'Qori', category: 'short', gender: 'hombre', color: 'beige', price: 85.0, style: ['casual', 'playa', 'clásico'], origin: 'Arequipa - Perú', materials: '100% algodón twill', desc: 'Short chino de corte clásico sobre la rodilla.' },
];

export const TRYON_TYPE = {
  polo: 'top', camisa: 'top', polera: 'top', casaca: 'top', vestido: 'full', pantalon: 'bottom', falda: 'bottom', short: 'bottom',
};
