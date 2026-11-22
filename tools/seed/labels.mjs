// Emite etiquetas anti-fraude de demostración (misma lógica que la Edge Function
// "units") y guarda sus datos para imprimirlas con tools/labels/render.py.
//
//   node seed/labels.mjs "Polo básico Pima:M:2" "Polera con capucha gris:M:1" ...
//   node seed/labels.mjs --dry   (estima el gas sin enviar nada)
//
// Cada argumento es "<nombre de la prenda>:<talla>:<cantidad>".
// Salida: tools/labels/out/labels.json (se agrega a lo ya emitido).
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import dotenv from 'dotenv';
import { createClient } from '@supabase/supabase-js';
import { Contract, JsonRpcProvider, Wallet, formatEther, keccak256, parseUnits, toUtf8Bytes } from 'ethers';

const here = import.meta.dirname;
dotenv.config({ path: path.join(here, '../.env') });
const chainEnv = dotenv.parse(fs.readFileSync(path.join(here, '../../contracts/.env')));
const db = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
const provider = new JsonRpcProvider(chainEnv.AMOY_RPC_URL, 80002, { staticNetwork: true });
const wallet = new Wallet(chainEnv.RELAYER_PRIVATE_KEY, provider);
const { abi } = JSON.parse(fs.readFileSync(path.join(here, '../../contracts/build/ARFitUnits.json'), 'utf8'));
const units = new Contract(chainEnv.UNITS_CONTRACT_ADDRESS, abi, wallet);
const tip = parseUnits(chainEnv.GAS_PRIORITY_GWEI ?? '25', 'gwei');
const fees = { maxPriorityFeePerGas: tip, maxFeePerGas: tip + parseUnits('5', 'gwei') };

// --- mismos helpers que supabase/functions/_shared/units.ts
const ean13Check = (s) => (10 - ([...s].reduce((a, d, i) => a + Number(d) * (i % 2 ? 3 : 1), 0) % 10)) % 10;
const demoGtin = (pid, size, salt = 0) => {
  const item = (BigInt(keccak256(toUtf8Bytes(`${pid}|${size}|${salt}`))) % 100000n).toString().padStart(5, '0');
  const first12 = `77502026${item}`.slice(0, 12);
  return first12 + ean13Check(first12);
};
const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const newSerial = () => {
  const s = Array.from(crypto.randomBytes(12), (b) => ALPHABET[b % 32]).join('');
  return `${s.slice(0, 4)}-${s.slice(4, 8)}-${s.slice(8, 12)}`;
};
const ref = (uuid) => keccak256(toUtf8Bytes(uuid));
const sizeBytes8 = (size) => '0x' + Buffer.from(size, 'utf8').toString('hex').padEnd(16, '0');
const message = (serial, pid, size, gtin) => `ARFIT|${serial}|${pid}|${size}|${gtin}`;
const payload = (serial, pid, size, gtin, sig) => `arfit://u/${serial}?p=${pid}&t=${encodeURIComponent(size)}&g=${gtin}&s=${sig}`;

const dry = process.argv.includes('--dry');
const jobs = process.argv.slice(2).filter((a) => !a.startsWith('--')).map((a) => {
  const [name, size, count] = a.split(':');
  return { name, size, count: Number(count ?? 1) };
});
if (!jobs.length) throw new Error('Uso: node seed/labels.mjs "<prenda>:<talla>:<cantidad>" ...');

const outDir = path.join(here, '../labels/out');
fs.mkdirSync(outDir, { recursive: true });
const outFile = path.join(outDir, 'labels.json');
const out = fs.existsSync(outFile) ? JSON.parse(fs.readFileSync(outFile, 'utf8')) : [];

console.log(`Emisor ${wallet.address} · saldo ${formatEther(await provider.getBalance(wallet.address))} POL`);
for (const job of jobs) {
  const { data: p, error } = await db.from('products').select('*').eq('name', job.name).single();
  if (error || !p) throw new Error(`No encontré la prenda "${job.name}"`);
  if (!p.chain_product_id) throw new Error(`"${p.name}" no está registrada en ARFitTrace`);
  if (!(job.size in (p.size_chart ?? {}))) throw new Error(`"${p.name}" no tiene talla ${job.size}`);

  const gtins = { ...(p.gtins ?? {}) };
  let gtin = gtins[job.size];
  if (!gtin) {
    const { data: all } = await db.from('products').select('gtins');
    const used = new Set(all.flatMap((r) => Object.values(r.gtins ?? {})));
    for (let salt = 0; !gtin || used.has(gtin); salt++) gtin = demoGtin(p.id, job.size, salt);
    gtins[job.size] = gtin;
    if (!dry) await db.from('products').update({ gtins }).eq('id', p.id);
  }

  const batch = [];
  for (let i = 0; i < job.count; i++) {
    const serial = newSerial();
    const sig = await wallet.signMessage(message(serial, p.id, job.size, gtin));
    batch.push({ product_id: p.id, serial, unit_id: keccak256(toUtf8Bytes(serial)), size: job.size, gtin, qr_payload: payload(serial, p.id, job.size, gtin, sig) });
  }

  const args = [ref(p.id), sizeBytes8(job.size), BigInt(gtin), batch.map((u) => u.unit_id)];
  const gas = await units.issueUnits.estimateGas(...args);
  console.log(`${p.name} · talla ${job.size} · ${job.count} u. · GTIN ${gtin} · gas ${gas} (~${formatEther(gas * (tip + 1n))} POL)`);
  if (dry) continue;

  const tx = await units.issueUnits(...args, fees);
  await tx.wait(1, 120_000);
  console.log('  tx', `https://amoy.polygonscan.com/tx/${tx.hash}`);
  const { error: insErr } = await db.from('product_units').insert(batch.map((u) => ({ ...u, issue_tx: tx.hash })));
  if (insErr) throw insErr;
  for (const u of batch) {
    out.push({ ...u, product_name: p.name, brand: p.brand, issue_tx: tx.hash });
    console.log('  ', u.serial);
  }
}
if (!dry) fs.writeFileSync(outFile, JSON.stringify(out, null, 2));
console.log(dry ? 'Simulación terminada (no se envió nada).' : `Guardado en ${path.relative(process.cwd(), outFile)}`);
