// Carga el catálogo demo en Supabase y registra cada prenda en Polygon Amoy.
//   1. crea cuentas demo (admin, 2 proveedores, 1 transportista, compradores)
//   2. sube las imágenes al bucket "products"
//   3. inserta las prendas con su tabla de tallas, stock y anclajes RA
//   4. registra cada prenda en el contrato ARFitTrace y la marca como verificada
//   5. genera interacciones sintéticas de compradores (señal inicial para la IA)
// Las contraseñas generadas se guardan en tools/demo-accounts.local.json
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import dotenv from 'dotenv';
import { createClient } from '@supabase/supabase-js';
import { Contract, JsonRpcProvider, Wallet, keccak256, parseUnits, sha256, toUtf8Bytes } from 'ethers';
import { CHARTS, PRODUCTS, TRYON_TYPE } from './catalog.mjs';

const here = import.meta.dirname;
dotenv.config({ path: path.join(here, '../.env') });
const chainEnv = dotenv.parse(fs.readFileSync(path.join(here, '../../contracts/.env')));

const db = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
const { abi } = JSON.parse(fs.readFileSync(path.join(here, '../../contracts/build/ARFitTrace.json'), 'utf8'));
const provider = new JsonRpcProvider(chainEnv.AMOY_RPC_URL, 80002, { staticNetwork: true });
// sin contrato desplegado se carga solo la base de datos; re-ejecutar tras `npm run deploy`
const contract = chainEnv.CONTRACT_ADDRESS
  ? new Contract(chainEnv.CONTRACT_ADDRESS, abi, new Wallet(chainEnv.RELAYER_PRIVATE_KEY, provider))
  : null;

const ACCOUNTS = [
  { key: 'admin', email: 'admin@arfit.demo', full_name: 'Admin AR-FIT', role: 'admin' },
  { key: 'prov0', email: 'andina@arfit.demo', full_name: 'Rosa Quispe', role: 'proveedor', store_name: 'Andina Textil', company_name: 'Andina Textil S.A.C.', city: 'Lima' },
  { key: 'prov1', email: 'qori@arfit.demo', full_name: 'Luis Mamani', role: 'proveedor', store_name: 'Qori Moda', company_name: 'Qori Moda E.I.R.L.', city: 'Arequipa' },
  { key: 'carrier', email: 'envios@arfit.demo', full_name: 'Carlos Huamán', role: 'transportista', company_name: 'Rápido Andino Courier', city: 'Lima' },
  { key: 'buyer', email: 'comprador@arfit.demo', full_name: 'Valeria Torres', role: 'comprador', gender: 'mujer', weight_kg: 58, height_cm: 163, size: 'S', style_prefs: ['casual', 'romántico'], color_prefs: ['rosado', 'blanco'], category_prefs: ['vestido', 'polo'] },
];

// compradores sintéticos (solo generan interacciones para el filtrado colaborativo)
const PERSONAS = [
  { styles: ['urbano', 'streetwear'], gender: 'hombre' },
  { styles: ['elegante', 'oficina'], gender: 'mujer' },
  { styles: ['casual', 'clásico'], gender: 'hombre' },
  { styles: ['romántico', 'bohemio'], gender: 'mujer' },
  { styles: ['deportivo', 'urbano'], gender: 'mujer' },
  { styles: ['formal', 'minimalista'], gender: 'hombre' },
];

const credsPath = path.join(here, '../demo-accounts.local.json');
const creds = fs.existsSync(credsPath) ? JSON.parse(fs.readFileSync(credsPath, 'utf8')) : {};

async function ensureUser(acc) {
  const { data: list } = await db.auth.admin.listUsers({ perPage: 1000 });
  const existing = list.users.find((u) => u.email === acc.email);
  if (existing) return existing.id; // no se pisan los cambios hechos al probar la app
  const password = creds[acc.email] ?? crypto.randomBytes(9).toString('base64url');
  const { data, error: createErr } = await db.auth.admin.createUser({
    email: acc.email, password, email_confirm: true,
    user_metadata: { full_name: acc.full_name, role: acc.role === 'admin' ? 'comprador' : acc.role },
  });
  if (createErr) throw createErr;
  const user = data.user;
  creds[acc.email] = password;
  const { key, email, ...profile } = acc;
  const { error } = await db.from('profiles').update({ ...profile, verified: true, onboarded: true }).eq('id', user.id);
  if (error) throw error;
  return user.id;
}

const TIP = parseUnits(process.env.GAS_PRIORITY_GWEI || chainEnv.GAS_PRIORITY_GWEI || '30', 'gwei');
const IMAGE_VERSION = 'v2';
const ref = (uuid) => keccak256(toUtf8Bytes(uuid));
const dataHash = (p) => sha256(toUtf8Bytes([p.id, p.supplier_id, p.name, p.brand, p.category, p.color, p.origin, p.materials].join('|')));

async function main() {
  const ids = {};
  for (const acc of ACCOUNTS) {
    ids[acc.key] = await ensureUser(acc);
    console.log('usuario', acc.email, acc.role);
  }
  for (let i = 0; i < PERSONAS.length; i++) {
    ids[`p${i}`] = await ensureUser({
      key: `p${i}`, email: `persona${i + 1}@arfit.demo`, full_name: `Comprador demo ${i + 1}`, role: 'comprador',
      gender: PERSONAS[i].gender, style_prefs: PERSONAS[i].styles,
    });
  }
  fs.writeFileSync(credsPath, JSON.stringify(creds, null, 2), { mode: 0o600 });

  const anchors = JSON.parse(fs.readFileSync(path.join(here, 'images/anchors.json'), 'utf8'));
  const products = [];
  for (const item of PRODUCTS) {
    const supplierId = ids[`prov${item.supplier}`];
    const file = fs.readFileSync(path.join(here, `images/${item.img}.png`));
    // versión en el nombre: evita que cachés (CDN/teléfono) sirvan una imagen anterior
    const objectPath = `${supplierId}/${item.img}.${IMAGE_VERSION}.png`;
    const { error: upErr } = await db.storage.from('products').upload(objectPath, file, { contentType: 'image/png', upsert: true });
    if (upErr) throw upErr;
    const url = db.storage.from('products').getPublicUrl(objectPath).data.publicUrl;
    // vista de espalda (mismo recorte → comparte el rig)
    const backPath = `${supplierId}/${item.img}-back.${IMAGE_VERSION}.png`;
    const { error: backErr } = await db.storage.from('products')
      .upload(backPath, fs.readFileSync(path.join(here, `images/${item.img}-back.png`)), { contentType: 'image/png', upsert: true });
    if (backErr) throw backErr;
    const backUrl = db.storage.from('products').getPublicUrl(backPath).data.publicUrl;
    const { rig, ...anchor } = anchors[item.img];

    const sizeChart = CHARTS[item.chart ?? item.category];
    const stock = Object.fromEntries(Object.keys(sizeChart).map((s) => [s, 3 + Math.floor(Math.random() * 12)]));
    const row = {
      supplier_id: supplierId, name: item.name, description: item.desc, brand: item.brand, category: item.category,
      gender: item.gender, style_tags: item.style, color: item.color, price: item.price, size_chart: sizeChart, stock,
      image_url: url, tryon_image_url: url, tryon_type: TRYON_TYPE[item.category], tryon_anchor: anchor,
      tryon_rig: rig, tryon_back_url: backUrl,
      origin: item.origin, materials: item.materials,
    };
    const { data: existing } = await db.from('products').select('*').eq('supplier_id', supplierId).eq('name', item.name).maybeSingle();
    // en prendas existentes se conserva el stock (las compras de prueba lo descuentan)
    const { stock: _initialStock, ...rowWithoutStock } = row;
    const { data: p, error } = existing
      ? await db.from('products').update(rowWithoutStock).eq('id', existing.id).select().single()
      : await db.from('products').insert(row).select().single();
    if (error) throw error;
    products.push(p);
  }

  // registro on-chain por lotes (6 prendas por transacción) ya verificadas
  // SEED_CHAIN_PRODUCTS="Nombre 1,Nombre 2" registra solo esas prendas (útil con poco saldo)
  const only = process.env.SEED_CHAIN_PRODUCTS?.split(',').map((x) => x.trim());
  // SEED_SKIP_CHAIN=1 actualiza solo la base de datos (sin gastar POL)
  const pendingChain = contract && !process.env.SEED_SKIP_CHAIN
    ? products.filter((p) => !p.chain_product_id && (!only || only.includes(p.name)))
    : [];
  if (!contract) console.log('⚠ CONTRACT_ADDRESS vacío: se omite el registro en blockchain');
  for (let i = 0; i < pendingChain.length; i += 6) {
    const batch = pendingChain.slice(i, i + 6);
    const tx = await contract.registerProducts(
      batch.map((p) => ref(p.id)),
      batch.map((p) => ref(p.supplier_id)),
      batch.map((p) => p.name),
      batch.map((p) => p.origin),
      batch.map((p) => p.materials),
      batch.map(dataHash),
      true,
      { maxPriorityFeePerGas: TIP, maxFeePerGas: TIP + parseUnits('5', 'gwei') },
    );
    await tx.wait();
    for (const p of batch) {
      await db.from('products').update({ chain_product_id: ref(p.id), chain_tx: tx.hash, data_hash: dataHash(p), chain_verified: true }).eq('id', p.id);
    }
    console.log(`⛓  ${batch.length} prendas registradas: https://amoy.polygonscan.com/tx/${tx.hash}`);
  }

  // interacciones sintéticas coherentes con cada persona
  const kinds = ['view', 'view', 'view', 'like', 'tryon', 'cart', 'purchase'];
  const rows = [];
  PERSONAS.forEach((persona, i) => {
    const uid = ids[`p${i}`];
    for (const p of products) {
      const match = p.style_tags.filter((s) => persona.styles.includes(s)).length;
      const genderOk = p.gender === 'unisex' || p.gender === persona.gender;
      if (!match || !genderOk) continue;
      const n = 1 + match * 2;
      for (let k = 0; k < n; k++) {
        const daysAgo = Math.random() * 30;
        rows.push({ user_id: uid, product_id: p.id, kind: kinds[Math.floor(Math.random() * kinds.length)], created_at: new Date(Date.now() - daysAgo * 86400000).toISOString() });
      }
    }
  });
  await db.from('interactions').delete().in('user_id', PERSONAS.map((_, i) => ids[`p${i}`]));
  await db.from('interactions').insert(rows);
  console.log(`${rows.length} interacciones sintéticas`);
  console.log('Cuentas demo y contraseñas →', credsPath);
}

main().catch((e) => { console.error(e); process.exit(1); });
