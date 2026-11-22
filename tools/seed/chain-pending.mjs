// Registra en ARFitTrace (ya verificadas) las prendas del catálogo que aún no
// están en blockchain, en lotes de 6 por transacción. No toca nada más.
//   node seed/chain-pending.mjs [--dry]
import fs from 'node:fs';
import path from 'node:path';
import dotenv from 'dotenv';
import { createClient } from '@supabase/supabase-js';
import { Contract, JsonRpcProvider, Wallet, formatEther, keccak256, parseUnits, sha256, toUtf8Bytes } from 'ethers';

const here = import.meta.dirname;
dotenv.config({ path: path.join(here, '../.env') });
const chainEnv = dotenv.parse(fs.readFileSync(path.join(here, '../../contracts/.env')));
const db = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
const provider = new JsonRpcProvider(chainEnv.AMOY_RPC_URL, 80002, { staticNetwork: true });
const wallet = new Wallet(chainEnv.RELAYER_PRIVATE_KEY, provider);
const { abi } = JSON.parse(fs.readFileSync(path.join(here, '../../contracts/build/ARFitTrace.json'), 'utf8'));
const contract = new Contract(chainEnv.CONTRACT_ADDRESS, abi, wallet);
const TIP = parseUnits(chainEnv.GAS_PRIORITY_GWEI ?? '25', 'gwei');

const ref = (uuid) => keccak256(toUtf8Bytes(uuid));
// Igual que productDataHash en supabase/functions/_shared/chain.ts
const dataHash = (p) => sha256(toUtf8Bytes([p.id, p.supplier_id, p.name, p.brand, p.category, p.color, p.origin, p.materials].join('|')));

const dry = process.argv.includes('--dry');
const { data: pending, error } = await db.from('products').select('*').is('chain_product_id', null).order('created_at');
if (error) throw error;
console.log(`${pending.length} prendas sin registrar · saldo ${formatEther(await provider.getBalance(wallet.address))} POL`);

for (let i = 0; i < pending.length; i += 6) {
  const batch = pending.slice(i, i + 6);
  const args = [
    batch.map((p) => ref(p.id)),
    batch.map((p) => ref(p.supplier_id)),
    batch.map((p) => p.name),
    batch.map((p) => p.origin),
    batch.map((p) => p.materials),
    batch.map(dataHash),
    true,
  ];
  const gas = await contract.registerProducts.estimateGas(...args);
  console.log(`Lote ${i / 6 + 1}: ${batch.map((p) => p.name).join(', ')} · gas ${gas}`);
  if (dry) continue;
  const tx = await contract.registerProducts(...args, { maxPriorityFeePerGas: TIP, maxFeePerGas: TIP + parseUnits('5', 'gwei') });
  await tx.wait(1, 120_000);
  for (const p of batch) {
    await db.from('products').update({ chain_product_id: ref(p.id), chain_tx: tx.hash, data_hash: dataHash(p), chain_verified: true }).eq('id', p.id);
  }
  console.log(`  ⛓  https://amoy.polygonscan.com/tx/${tx.hash}`);
}
