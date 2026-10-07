// Crea la wallet relayer (una sola vez) y muestra solo su dirección pública.
import fs from 'node:fs';
import path from 'node:path';
import { Wallet } from 'ethers';

const envPath = path.resolve(import.meta.dirname, '../.env');
let env = fs.existsSync(envPath) ? fs.readFileSync(envPath, 'utf8') : fs.readFileSync(envPath + '.example', 'utf8');
const match = env.match(/^RELAYER_PRIVATE_KEY=(0x[0-9a-fA-F]{64})$/m);
let wallet;
if (match) {
  wallet = new Wallet(match[1]);
  console.log('La wallet ya existe.');
} else {
  wallet = Wallet.createRandom();
  env = env.replace(/^RELAYER_PRIVATE_KEY=.*$/m, `RELAYER_PRIVATE_KEY=${wallet.privateKey}`);
  fs.writeFileSync(envPath, env, { mode: 0o600 });
  console.log('Wallet creada y guardada en contracts/.env');
}
console.log('Dirección pública:', wallet.address);
console.log('Obtén POL de prueba en https://faucet.polygon.technology (red Amoy) para esta dirección.');
