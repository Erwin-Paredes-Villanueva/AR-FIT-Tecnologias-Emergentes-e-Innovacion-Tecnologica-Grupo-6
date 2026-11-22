// Etiquetas anti-fraude de AR-FIT: código de barras EAN-13 + QR firmado por unidad.
import { keccak256, toUtf8Bytes } from 'npm:ethers@6';

/** Dígito de control EAN-13 (GS1): pesos 1,3,1,3… sobre los 12 primeros dígitos. */
export function ean13CheckDigit(first12: string): number {
  let sum = 0;
  for (let i = 0; i < 12; i++) sum += Number(first12[i]) * (i % 2 === 0 ? 1 : 3);
  return (10 - (sum % 10)) % 10;
}

export function isValidEan13(code: string): boolean {
  return /^[0-9]{13}$/.test(code) && ean13CheckDigit(code.slice(0, 12)) === Number(code[12]);
}

/**
 * GTIN de demostración para una prenda y talla: prefijo GS1 Perú (775), un
 * prefijo de empresa ficticio y un número de artículo derivado del producto.
 * En producción el proveedor ingresa el GTIN real de su etiqueta.
 */
export function demoGtin(productId: string, size: string, salt = 0): string {
  const h = keccak256(toUtf8Bytes(`${productId}|${size}|${salt}`));
  const item = (BigInt(h) % 100000n).toString().padStart(5, '0');
  const first12 = `7750${'2026'}${item}`.slice(0, 12);
  return first12 + ean13CheckDigit(first12);
}

// Alfabeto Crockford base32 (sin I, L, O, U): legible y sin ambigüedades
const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/** Número de serie aleatorio de 12 símbolos (60 bits), p. ej. "AF7K-2M9Q-X4PT". */
export function newSerial(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(12));
  const s = Array.from(bytes, (b) => ALPHABET[b % 32]).join('');
  return `${s.slice(0, 4)}-${s.slice(4, 8)}-${s.slice(8, 12)}`;
}

/** Clave de la unidad en ARFitUnits (la serie no se publica en claro). */
export const unitId = (serial: string) => keccak256(toUtf8Bytes(serial));

/** Mensaje que firma AR-FIT; la app lo reconstruye para comprobar la firma. */
export const unitMessage = (serial: string, productId: string, size: string, gtin: string) =>
  `ARFIT|${serial}|${productId}|${size}|${gtin}`;

/** Contenido del QR. */
export const qrPayload = (serial: string, productId: string, size: string, gtin: string, signature: string) =>
  `arfit://u/${serial}?p=${productId}&t=${encodeURIComponent(size)}&g=${gtin}&s=${signature}`;

/** Talla → bytes8 (ASCII, relleno a la derecha con ceros). */
export function sizeBytes8(size: string): string {
  const b = toUtf8Bytes(size);
  if (b.length > 8) throw new Error('Talla demasiado larga');
  return '0x' + Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('').padEnd(16, '0');
}
