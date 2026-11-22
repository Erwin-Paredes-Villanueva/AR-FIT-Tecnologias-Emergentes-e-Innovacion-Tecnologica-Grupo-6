// deno test supabase/tests/units_test.ts
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { Wallet, verifyMessage } from 'npm:ethers@6';
import { demoGtin, ean13CheckDigit, isValidEan13, newSerial, qrPayload, sizeBytes8, unitMessage } from '../functions/_shared/units.ts';

Deno.test('EAN-13: dígito de control', () => {
  // Ejemplos reales de GS1
  assertEquals(ean13CheckDigit('400638133393'), 1);
  assert(isValidEan13('4006381333931'));
  assert(!isValidEan13('4006381333932'));
  assert(!isValidEan13('400638133393'));
});

Deno.test('GTIN de demostración: válido, peruano y estable', () => {
  const g = demoGtin('2b7c0d3e-0000-4000-8000-000000000001', 'M');
  assertMatch(g, /^775\d{10}$/);
  assert(isValidEan13(g));
  assertEquals(g, demoGtin('2b7c0d3e-0000-4000-8000-000000000001', 'M'));
  assert(g !== demoGtin('2b7c0d3e-0000-4000-8000-000000000001', 'L'));
});

Deno.test('serie: formato legible y aleatoria', () => {
  const a = newSerial();
  assertMatch(a, /^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$/);
  assert(a !== newSerial());
});

Deno.test('talla → bytes8', () => {
  assertEquals(sizeBytes8('M'), '0x4d00000000000000');
  assertEquals(sizeBytes8('XL'), '0x584c000000000000');
});

Deno.test('firma de la etiqueta: se recupera la dirección del emisor', async () => {
  const w = Wallet.createRandom();
  const msg = unitMessage('AF7K-2M9Q-X4PT', '2b7c0d3e-0000-4000-8000-000000000001', 'M', '7750202600011');
  const sig = await w.signMessage(msg);
  assertEquals(verifyMessage(msg, sig), w.address);
  const qr = qrPayload('AF7K-2M9Q-X4PT', '2b7c0d3e-0000-4000-8000-000000000001', 'M', '7750202600011', sig);
  assert(qr.startsWith('arfit://u/AF7K-2M9Q-X4PT?p='));
});
